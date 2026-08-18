// Package bench 는 스토리지에 동시 부하를 걸고 지연 분포를 측정한다.
//
// 이 랩이 Go 로 쓰인 이유가 가장 직접적으로 드러나는 부분이다. 백엔드
// (CephFS/RBD/BeeGFS/NFS)를 비교할 때 의미 있는 값은 평균이 아니라 꼬리
// 지연이다. 평균 지연은 백엔드 간 차이를 거의 지워버리고, 복제·리커버리·
// 메타데이터 잠금 때문에 생기는 튐은 p99 에서만 보인다.
//
// 측정 방식에 대해:
//   - 각 워커는 자기 지연 슬라이스에만 기록하고, 끝난 뒤 한 번 병합한다.
//     측정 경로에 뮤텍스를 두면 측정 대상이 아니라 측정기를 재게 된다.
//   - 백분위수는 샘플을 전부 보관해 정렬로 정확히 구한다. 랩 규모(수백만
//     이하)에서는 히스토그램 근사를 쓸 이유가 없다.
package bench

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sort"
	"sync"
	"time"
)

// Op 는 한 번의 측정 단위 작업이다. 성공하면 nil 을 반환한다.
// seq 는 워커별이 아니라 전체에서 유일한 연산 번호로, 파일 이름 충돌을 막는 데 쓴다.
type Op func(ctx context.Context, seq int) error

// Config 는 부하 생성 파라미터다.
type Config struct {
	// Concurrency 는 동시에 도는 워커 수다.
	Concurrency int
	// Duration 동안 부하를 건다. Ops 가 설정되면 무시된다.
	Duration time.Duration
	// Ops 가 0 보다 크면 총 연산 수 기준으로 끝낸다.
	Ops int
	// BytesPerOp 는 처리량 계산에 쓰는 연산당 바이트 수다. 0 이면 처리량을 보고하지 않는다.
	BytesPerOp int64
}

func (c Config) validate() error {
	if c.Concurrency < 1 {
		return errors.New("concurrency 는 1 이상이어야 합니다")
	}
	if c.Ops <= 0 && c.Duration <= 0 {
		return errors.New("duration 또는 ops 중 하나는 지정해야 합니다")
	}
	if c.BytesPerOp < 0 {
		return errors.New("bytes-per-op 는 음수일 수 없습니다")
	}
	return nil
}

// Result 는 측정 결과 요약이다. JSON 으로 그대로 노출된다.
type Result struct {
	Concurrency int     `json:"concurrency"`
	Ops         int     `json:"ops"`
	Errors      int     `json:"errors"`
	ElapsedMS   float64 `json:"elapsed_ms"`
	OpsPerSec   float64 `json:"ops_per_sec"`
	// ThroughputMBps 는 BytesPerOp 가 0 이면 0 이다.
	ThroughputMBps float64 `json:"throughput_mbps"`

	MinMS  float64 `json:"min_ms"`
	P50MS  float64 `json:"p50_ms"`
	P95MS  float64 `json:"p95_ms"`
	P99MS  float64 `json:"p99_ms"`
	P999MS float64 `json:"p999_ms"`
	MaxMS  float64 `json:"max_ms"`
	MeanMS float64 `json:"mean_ms"`

	// FirstError 는 실패가 있었을 때 첫 에러 메시지다. 전부 모으면 로그가
	// 터지므로 대표 하나만 남기고 나머지는 Errors 개수로 센다.
	FirstError string `json:"first_error,omitempty"`
}

// Run 은 cfg 대로 op 를 반복 실행하고 지연 분포를 반환한다.
//
// op 가 실패해도 부하는 멈추지 않는다. 스토리지 랩에서는 일부 실패가 곧
// 측정 대상(예: OSD 다운 중 가용성)이므로, 실패율과 지연을 함께 봐야 한다.
func Run(ctx context.Context, cfg Config, op Op) (Result, error) {
	if err := cfg.validate(); err != nil {
		return Result{}, err
	}
	if op == nil {
		return Result{}, errors.New("op 이 nil 입니다")
	}

	runCtx := ctx
	var cancel context.CancelFunc
	if cfg.Ops <= 0 {
		runCtx, cancel = context.WithTimeout(ctx, cfg.Duration)
		defer cancel()
	}

	type workerOut struct {
		lat        []time.Duration
		errs       int
		firstError error
	}

	// seq 는 워커들이 나눠 갖는 전역 연산 카운터다. Ops 모드에서는 이 값이
	// 상한 역할도 한다.
	var (
		mu   sync.Mutex
		next int
	)
	takeSeq := func() (int, bool) {
		mu.Lock()
		defer mu.Unlock()
		if cfg.Ops > 0 && next >= cfg.Ops {
			return 0, false
		}
		s := next
		next++
		return s, true
	}

	outs := make([]workerOut, cfg.Concurrency)
	var wg sync.WaitGroup
	start := time.Now()

	for w := 0; w < cfg.Concurrency; w++ {
		wg.Add(1)
		go func(w int) {
			defer wg.Done()
			// 재할당(grow)이 측정 중 지연으로 잡히지 않도록 미리 잡아둔다.
			capHint := 1024
			if cfg.Ops > 0 {
				capHint = cfg.Ops/cfg.Concurrency + 1
			}
			out := workerOut{lat: make([]time.Duration, 0, capHint)}

			for {
				if runCtx.Err() != nil {
					break
				}
				seq, ok := takeSeq()
				if !ok {
					break
				}
				opStart := time.Now()
				err := op(runCtx, seq)
				elapsed := time.Since(opStart)

				if err != nil {
					// 종료 신호로 인한 취소는 실패로 세지 않는다. 측정 구간이
					// 끝나서 중단된 것을 에러율로 보고하면 결과가 왜곡된다.
					if runCtx.Err() != nil && (errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)) {
						break
					}
					out.errs++
					if out.firstError == nil {
						out.firstError = err
					}
					continue
				}
				out.lat = append(out.lat, elapsed)
			}
			outs[w] = out
		}(w)
	}
	wg.Wait()
	elapsed := time.Since(start)

	total := 0
	errCount := 0
	var firstError error
	for _, o := range outs {
		total += len(o.lat)
		errCount += o.errs
		if firstError == nil {
			firstError = o.firstError
		}
	}
	all := make([]time.Duration, 0, total)
	for _, o := range outs {
		all = append(all, o.lat...)
	}

	res := Result{
		Concurrency: cfg.Concurrency,
		Ops:         len(all),
		Errors:      errCount,
		ElapsedMS:   ms(elapsed),
	}
	if firstError != nil {
		res.FirstError = firstError.Error()
	}
	if elapsed > 0 {
		res.OpsPerSec = float64(len(all)) / elapsed.Seconds()
		if cfg.BytesPerOp > 0 {
			bytes := float64(len(all)) * float64(cfg.BytesPerOp)
			res.ThroughputMBps = bytes / elapsed.Seconds() / (1024 * 1024)
		}
	}
	if len(all) == 0 {
		return res, nil
	}

	sort.Slice(all, func(i, j int) bool { return all[i] < all[j] })
	var sum time.Duration
	for _, d := range all {
		sum += d
	}
	res.MinMS = ms(all[0])
	res.MaxMS = ms(all[len(all)-1])
	res.MeanMS = ms(sum / time.Duration(len(all)))
	res.P50MS = ms(percentile(all, 0.50))
	res.P95MS = ms(percentile(all, 0.95))
	res.P99MS = ms(percentile(all, 0.99))
	res.P999MS = ms(percentile(all, 0.999))
	return res, nil
}

// percentile 은 정렬된 샘플에서 최근접 순위(nearest-rank) 백분위수를 고른다.
// sorted 는 비어 있지 않아야 한다.
func percentile(sorted []time.Duration, q float64) time.Duration {
	if q <= 0 {
		return sorted[0]
	}
	if q >= 1 {
		return sorted[len(sorted)-1]
	}
	// nearest-rank: 최소 q 비율의 샘플이 이 값 이하가 되는 가장 작은 값.
	idx := int(math.Ceil(q*float64(len(sorted)))) - 1
	if idx < 0 {
		idx = 0
	}
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}
	return sorted[idx]
}

func ms(d time.Duration) float64 {
	return float64(d.Nanoseconds()) / 1e6
}

// Format 은 결과를 사람이 읽는 한 줄짜리 표 형태로 만든다.
func (r Result) Format(label string) string {
	tp := "-"
	if r.ThroughputMBps > 0 {
		tp = fmt.Sprintf("%.1f MB/s", r.ThroughputMBps)
	}
	return fmt.Sprintf(
		"%-16s ops=%-7d err=%-5d %7.0f op/s  %10s  p50=%.2fms p95=%.2fms p99=%.2fms p99.9=%.2fms max=%.2fms",
		label, r.Ops, r.Errors, r.OpsPerSec, tp, r.P50MS, r.P95MS, r.P99MS, r.P999MS, r.MaxMS)
}
