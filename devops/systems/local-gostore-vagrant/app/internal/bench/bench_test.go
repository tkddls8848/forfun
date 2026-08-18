package bench

import (
	"context"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"gostore/internal/store"
)

func TestPercentileNearestRank(t *testing.T) {
	// 1..100ms 샘플. nearest-rank 정의상 p50=50, p95=95, p99=99, p99.9=100.
	sorted := make([]time.Duration, 100)
	for i := range sorted {
		sorted[i] = time.Duration(i+1) * time.Millisecond
	}
	cases := []struct {
		q    float64
		want time.Duration
	}{
		{0.50, 50 * time.Millisecond},
		{0.95, 95 * time.Millisecond},
		{0.99, 99 * time.Millisecond},
		{0.999, 100 * time.Millisecond},
		{0, 1 * time.Millisecond},
		{1, 100 * time.Millisecond},
	}
	for _, c := range cases {
		if got := percentile(sorted, c.q); got != c.want {
			t.Errorf("percentile(q=%v) = %v, want %v", c.q, got, c.want)
		}
	}
}

func TestPercentileSingleSample(t *testing.T) {
	one := []time.Duration{7 * time.Millisecond}
	for _, q := range []float64{0, 0.5, 0.99, 1} {
		if got := percentile(one, q); got != 7*time.Millisecond {
			t.Errorf("percentile(q=%v) = %v, want 7ms", q, got)
		}
	}
}

func TestRunOpsMode(t *testing.T) {
	var count atomic.Int64
	res, err := Run(context.Background(), Config{Concurrency: 4, Ops: 200, BytesPerOp: 1024},
		func(ctx context.Context, seq int) error {
			count.Add(1)
			return nil
		})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	// Ops 모드는 정확히 요청한 횟수만 실행해야 한다. 워커별로 나눠 세면
	// 나머지 때문에 초과/미달이 생기기 쉬운 지점이다.
	if count.Load() != 200 {
		t.Fatalf("op 실행 횟수 = %d, want 200", count.Load())
	}
	if res.Ops != 200 {
		t.Fatalf("res.Ops = %d, want 200", res.Ops)
	}
	if res.Errors != 0 {
		t.Fatalf("res.Errors = %d, want 0", res.Errors)
	}
	if res.ThroughputMBps <= 0 {
		t.Fatal("BytesPerOp 를 줬는데 처리량이 0 입니다")
	}
}

func TestRunSeqIsUnique(t *testing.T) {
	const n = 500
	seen := make([]atomic.Bool, n)
	var dup atomic.Int64
	_, err := Run(context.Background(), Config{Concurrency: 8, Ops: n},
		func(ctx context.Context, seq int) error {
			if seq < 0 || seq >= n {
				t.Errorf("seq 범위 밖: %d", seq)
				return nil
			}
			if seen[seq].Swap(true) {
				dup.Add(1)
			}
			return nil
		})
	if err != nil {
		t.Fatal(err)
	}
	// seq 가 겹치면 워크로드가 같은 파일 이름을 동시에 다루게 된다.
	if dup.Load() != 0 {
		t.Fatalf("중복 seq %d건", dup.Load())
	}
}

func TestRunCountsErrorsButKeepsGoing(t *testing.T) {
	res, err := Run(context.Background(), Config{Concurrency: 2, Ops: 100},
		func(ctx context.Context, seq int) error {
			if seq%4 == 0 {
				return errors.New("주입된 실패")
			}
			return nil
		})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if res.Errors != 25 {
		t.Fatalf("Errors = %d, want 25", res.Errors)
	}
	if res.Ops != 75 {
		t.Fatalf("Ops = %d, want 75 (성공만 집계)", res.Ops)
	}
	if !strings.Contains(res.FirstError, "주입된 실패") {
		t.Fatalf("FirstError = %q", res.FirstError)
	}
}

func TestRunDurationModeStops(t *testing.T) {
	start := time.Now()
	res, err := Run(context.Background(), Config{Concurrency: 4, Duration: 300 * time.Millisecond},
		func(ctx context.Context, seq int) error {
			time.Sleep(5 * time.Millisecond)
			return nil
		})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	elapsed := time.Since(start)
	if elapsed > 2*time.Second {
		t.Fatalf("Duration 모드가 제때 멈추지 않았습니다: %v", elapsed)
	}
	if res.Ops == 0 {
		t.Fatal("아무 연산도 수행되지 않았습니다")
	}
	// 취소로 인한 중단이 실패로 집계되면 안 된다.
	if res.Errors != 0 {
		t.Fatalf("Errors = %d, 취소는 실패가 아닙니다", res.Errors)
	}
}

func TestRunValidates(t *testing.T) {
	noop := func(ctx context.Context, seq int) error { return nil }
	if _, err := Run(context.Background(), Config{Concurrency: 0, Ops: 1}, noop); err == nil {
		t.Error("concurrency=0 이 통과했습니다")
	}
	if _, err := Run(context.Background(), Config{Concurrency: 1}, noop); err == nil {
		t.Error("duration/ops 미지정이 통과했습니다")
	}
	if _, err := Run(context.Background(), Config{Concurrency: 1, Ops: 1}, nil); err == nil {
		t.Error("op=nil 이 통과했습니다")
	}
}

func TestParseMode(t *testing.T) {
	for _, s := range []string{"write", "READ", " mixed "} {
		if _, err := ParseMode(s); err != nil {
			t.Errorf("ParseMode(%q) 실패: %v", s, err)
		}
	}
	if _, err := ParseMode("append"); err == nil {
		t.Error("알 수 없는 모드가 통과했습니다")
	}
}

func TestLocalWorkloadModes(t *testing.T) {
	for _, mode := range []Mode{ModeWrite, ModeRead, ModeMixed} {
		t.Run(string(mode), func(t *testing.T) {
			st, err := store.New(t.TempDir())
			if err != nil {
				t.Fatal(err)
			}
			w := &LocalWorkload{Store: st, Mode: mode, Payload: 4096, Prefix: "bench-", ReadSeed: 8}
			if err := w.Prepare(); err != nil {
				t.Fatalf("Prepare: %v", err)
			}
			res, err := Run(context.Background(),
				Config{Concurrency: 4, Ops: 64, BytesPerOp: w.BytesPerOp()}, w.Op())
			if err != nil {
				t.Fatalf("Run: %v", err)
			}
			if res.Errors != 0 {
				t.Fatalf("에러 %d건: %s", res.Errors, res.FirstError)
			}
			if res.Ops != 64 {
				t.Fatalf("Ops = %d, want 64", res.Ops)
			}

			w.Cleanup()
			files, err := st.List()
			if err != nil {
				t.Fatal(err)
			}
			// Cleanup 후 이 워크로드가 만든 파일이 남아 있으면 반복 실행 시
			// 저장소가 계속 부푼다.
			if len(files) != 0 {
				t.Fatalf("Cleanup 후 파일이 남았습니다: %v", files)
			}
		})
	}
}
