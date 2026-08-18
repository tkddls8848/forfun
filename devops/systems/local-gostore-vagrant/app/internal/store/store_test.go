package store

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newTestStore(t *testing.T) *Store {
	t.Helper()
	s, err := New(t.TempDir())
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return s
}

func TestResolveRejectsEscape(t *testing.T) {
	s := newTestStore(t)
	// 저장소 밖을 노리는 이름은 "안전한 이름으로 고쳐서 성공"이 아니라 거부되어야 한다.
	bad := []string{
		"", ".", "..", "../etc/passwd", "a/../../etc/passwd", "sub/file.bin",
		`..\windows`, "/abs/path", ".hidden", "with\x00nul", "./x",
	}
	for _, name := range bad {
		t.Run(strings.ReplaceAll(name, "\x00", "NUL"), func(t *testing.T) {
			if _, err := s.resolve(name); !errors.Is(err, ErrBadName) {
				t.Fatalf("resolve(%q) = %v, ErrBadName 여야 함", name, err)
			}
		})
	}
}

func TestResolveAcceptsPlainNames(t *testing.T) {
	s := newTestStore(t)
	for _, name := range []string{"a.bin", "seed-0001.bin", "파일.txt", "a b.txt", "x..y"} {
		got, err := s.resolve(name)
		if err != nil {
			t.Fatalf("resolve(%q) 실패: %v", name, err)
		}
		if want := filepath.Join(s.Root(), name); got != want {
			t.Fatalf("resolve(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestEscapeDoesNotTouchOutsideFile(t *testing.T) {
	// 거부가 실제로 파일시스템을 보호하는지 확인한다.
	outside := filepath.Join(t.TempDir(), "victim.txt")
	if err := os.WriteFile(outside, []byte("original"), 0o644); err != nil {
		t.Fatal(err)
	}
	s := newTestStore(t)
	rel, err := filepath.Rel(s.Root(), outside)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.Write(rel, strings.NewReader("overwritten"), false); !errors.Is(err, ErrBadName) {
		t.Fatalf("Write(%q) = %v, ErrBadName 여야 함", rel, err)
	}
	got, err := os.ReadFile(outside)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "original" {
		t.Fatalf("저장소 밖 파일이 덮였습니다: %q", got)
	}
}

func TestWriteReadDelete(t *testing.T) {
	s := newTestStore(t)
	payload := bytes.Repeat([]byte("gostore"), 1000)

	n, err := s.Write("a.bin", bytes.NewReader(payload), true)
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if n != int64(len(payload)) {
		t.Fatalf("Write n = %d, want %d", n, len(payload))
	}

	f, err := s.Open("a.bin")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	got, err := io.ReadAll(f)
	f.Close()
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("읽은 내용이 다릅니다 (%d bytes)", len(got))
	}

	info, err := s.Stat("a.bin")
	if err != nil {
		t.Fatalf("Stat: %v", err)
	}
	if info.Size != int64(len(payload)) {
		t.Fatalf("Stat size = %d, want %d", info.Size, len(payload))
	}

	if err := s.Delete("a.bin"); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := s.Open("a.bin"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("삭제 후 Open = %v, ErrNotFound 여야 함", err)
	}
	if err := s.Delete("a.bin"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("없는 파일 Delete = %v, ErrNotFound 여야 함", err)
	}
}

// failingReader 는 도중에 실패하는 업로드를 흉내낸다.
type failingReader struct {
	data []byte
	n    int
}

func (f *failingReader) Read(p []byte) (int, error) {
	if f.n >= len(f.data) {
		return 0, errors.New("업로드 연결 끊김")
	}
	c := copy(p, f.data[f.n:])
	f.n += c
	return c, nil
}

func TestWriteIsAtomicOnFailure(t *testing.T) {
	s := newTestStore(t)
	if _, err := s.Write("a.bin", strings.NewReader("GOOD"), false); err != nil {
		t.Fatal(err)
	}
	// 실패한 덮어쓰기가 기존 파일을 훼손하면 안 된다.
	if _, err := s.Write("a.bin", &failingReader{data: []byte("PARTIAL")}, false); err == nil {
		t.Fatal("실패해야 할 Write 가 성공했습니다")
	}
	f, err := s.Open("a.bin")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	got, _ := io.ReadAll(f)
	if string(got) != "GOOD" {
		t.Fatalf("기존 파일이 훼손됐습니다: %q", got)
	}
	// 임시 파일이 남지 않아야 한다.
	entries, err := os.ReadDir(s.Root())
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".upload-") {
			t.Fatalf("임시 파일이 남았습니다: %s", e.Name())
		}
	}
}

func TestListSkipsNonRegular(t *testing.T) {
	s := newTestStore(t)
	if _, err := s.Write("b.bin", strings.NewReader("x"), false); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Write("a.bin", strings.NewReader("xx"), false); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(s.Root(), "adir"), 0o755); err != nil {
		t.Fatal(err)
	}
	files, err := s.List()
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 2 {
		t.Fatalf("List = %d개, want 2 (%v)", len(files), files)
	}
	// 이름순 정렬 확인.
	if files[0].Name != "a.bin" || files[1].Name != "b.bin" {
		t.Fatalf("정렬이 잘못됐습니다: %v", files)
	}
}

func TestProbeFailsWhenMissing(t *testing.T) {
	s, err := New(filepath.Join(t.TempDir(), "not-mounted"))
	if err != nil {
		t.Fatal(err)
	}
	// 마운트가 없는 경로를 정상으로 보고하면 안 된다.
	if _, err := s.Probe(); err == nil {
		t.Fatal("없는 경로에 대해 Probe 가 성공했습니다")
	}
}

func TestProbeReportsUsage(t *testing.T) {
	s := newTestStore(t)
	u, err := s.Probe()
	if err != nil {
		t.Fatalf("Probe: %v", err)
	}
	if u.TotalBytes == 0 {
		t.Fatal("TotalBytes 가 0 입니다")
	}
	if u.UsedBytes+u.FreeBytes != u.TotalBytes {
		t.Fatalf("used(%d) + free(%d) != total(%d)", u.UsedBytes, u.FreeBytes, u.TotalBytes)
	}
	if u.FSType == "" {
		t.Fatal("FSType 이 비었습니다")
	}
}
