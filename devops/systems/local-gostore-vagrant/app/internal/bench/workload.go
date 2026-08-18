package bench

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"math/rand/v2"
	"strings"

	"gostore/internal/store"
)

// Mode 는 부하의 종류다.
type Mode string

const (
	// ModeWrite 는 매 연산마다 새 파일을 쓴다.
	ModeWrite Mode = "write"
	// ModeRead 는 미리 준비한 파일 집합에서 하나를 읽는다.
	ModeRead Mode = "read"
	// ModeMixed 는 쓰기 1 : 읽기 3 비율로 섞는다. 스토리지 랩에서 흔한
	// 읽기 우세 패턴을 대충이라도 흉내내기 위한 값이다.
	ModeMixed Mode = "mixed"
)

// ParseMode 는 문자열을 Mode 로 바꾼다.
func ParseMode(s string) (Mode, error) {
	switch Mode(strings.ToLower(strings.TrimSpace(s))) {
	case ModeWrite:
		return ModeWrite, nil
	case ModeRead:
		return ModeRead, nil
	case ModeMixed:
		return ModeMixed, nil
	default:
		return "", fmt.Errorf("알 수 없는 mode: %q (write|read|mixed)", s)
	}
}

// LocalWorkload 는 store 에 직접 IO 를 거는 워크로드다. 에이전트가 자기
// 노드에서 실행하며, 네트워크 왕복이 섞이지 않은 순수 스토리지 지연을 잰다.
type LocalWorkload struct {
	Store    *store.Store
	Mode     Mode
	Payload  int64
	Prefix   string
	FSync    bool
	ReadSeed int // ModeRead/ModeMixed 가 읽을 준비 파일 개수

	payload []byte
}

// Prepare 는 읽기 워크로드가 읽을 파일을 미리 만들어 둔다.
// 쓰기 전용 워크로드에서는 아무것도 하지 않는다.
func (w *LocalWorkload) Prepare() error {
	if w.Payload <= 0 {
		return fmt.Errorf("payload 는 1 이상이어야 합니다: %d", w.Payload)
	}
	// 페이로드는 한 번만 만들어 재사용한다. 매 연산마다 생성하면 그 비용이
	// 스토리지 지연에 섞여 들어간다.
	// 압축·중복제거가 걸린 백엔드에서 값이 부풀지 않도록 무작위로 채운다.
	// 시드는 고정하지 않는다 — 반복 실행이 같은 블록을 재사용하면 캐시가
	// 유리하게 작동해 백엔드 비교가 왜곡된다.
	w.payload = make([]byte, w.Payload)
	for i := 0; i+8 <= len(w.payload); i += 8 {
		binary.LittleEndian.PutUint64(w.payload[i:], rand.Uint64())
	}
	for i := len(w.payload) &^ 7; i < len(w.payload); i++ {
		w.payload[i] = byte(rand.UintN(256))
	}
	if w.Mode == ModeWrite {
		return nil
	}
	if w.ReadSeed < 1 {
		w.ReadSeed = 32
	}
	for i := 0; i < w.ReadSeed; i++ {
		name := w.seedName(i)
		if _, err := w.Store.Write(name, bytes.NewReader(w.payload), w.FSync); err != nil {
			return fmt.Errorf("읽기용 준비 파일 생성 실패(%s): %w", name, err)
		}
	}
	return nil
}

// Cleanup 은 이 워크로드가 만든 파일을 지운다. 랩을 반복 실행해도 저장소가
// 계속 부풀지 않게 하려는 것이므로, 삭제 실패는 치명적이지 않다.
func (w *LocalWorkload) Cleanup() {
	files, err := w.Store.List()
	if err != nil {
		return
	}
	for _, f := range files {
		if strings.HasPrefix(f.Name, w.Prefix) {
			_ = w.Store.Delete(f.Name)
		}
	}
}

func (w *LocalWorkload) seedName(i int) string {
	return fmt.Sprintf("%sseed-%04d.bin", w.Prefix, i)
}

// BytesPerOp 는 연산당 전송 바이트 수다.
func (w *LocalWorkload) BytesPerOp() int64 { return w.Payload }

// Op 는 bench.Run 에 넘길 연산을 만든다.
func (w *LocalWorkload) Op() Op {
	return func(ctx context.Context, seq int) error {
		switch w.Mode {
		case ModeWrite:
			return w.write(seq)
		case ModeRead:
			return w.read(seq)
		case ModeMixed:
			// 4 로 나눠 1 은 쓰기, 3 은 읽기 — 읽기 우세 패턴.
			if seq%4 == 0 {
				return w.write(seq)
			}
			return w.read(seq)
		default:
			return fmt.Errorf("알 수 없는 mode: %q", w.Mode)
		}
	}
}

func (w *LocalWorkload) write(seq int) error {
	name := fmt.Sprintf("%sw-%08d.bin", w.Prefix, seq)
	if _, err := w.Store.Write(name, bytes.NewReader(w.payload), w.FSync); err != nil {
		return err
	}
	// 쓰기 워크로드가 저장소를 무한히 채우지 않도록 바로 지운다. 지연 측정
	// 대상은 Write 이며, Delete 는 측정 밖이지만 같은 연산에 포함된다는 점을
	// 결과 해석 시 감안해야 한다(README 참고).
	return w.Store.Delete(name)
}

func (w *LocalWorkload) read(seq int) error {
	name := w.seedName(seq % w.ReadSeed)
	f, err := w.Store.Open(name)
	if err != nil {
		return err
	}
	defer f.Close()
	// io.Discard 로 흘려보내되 실제로 전량을 읽는다. 크기만 stat 하면
	// 데이터 경로가 아니라 메타데이터 경로를 재게 된다.
	if _, err := io.Copy(io.Discard, f); err != nil {
		return fmt.Errorf("읽기 실패(%s): %w", name, err)
	}
	return nil
}
