// Package store 는 마운트된 디렉터리 하나를 평평한 파일 저장소로 다룬다.
//
// 이 랩에서 STORE_DIR 은 CephFS/RBD/NFS 등 "밖에서 마운트된" 경로다. 저장소는
// 마운트를 만들지 않으며, 마운트가 사라진 상황(디렉터리는 있는데 실제 FS 가
// 빠진 경우)을 정상 동작으로 위장하지 않고 에러로 드러내는 것이 목적이다.
package store

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
)

var (
	// ErrBadName 은 저장소 밖을 가리키는 이름을 거부할 때 반환한다.
	ErrBadName = errors.New("허용되지 않는 파일 이름")
	// ErrNotFound 는 대상 파일이 없을 때 반환한다.
	ErrNotFound = errors.New("파일 없음")
)

// Store 는 root 디렉터리 하나에 대한 파일 CRUD 를 제공한다.
type Store struct {
	root string
}

// New 는 root 를 절대경로로 정규화한 Store 를 만든다.
// root 가 실제로 존재하는지는 여기서 검사하지 않는다 — 마운트는 나중에 붙을 수
// 있으므로, 존재 여부는 요청 시점에 Stat 으로 확인한다.
func New(root string) (*Store, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, fmt.Errorf("store root 경로 해석 실패(%s): %w", root, err)
	}
	return &Store{root: abs}, nil
}

// Root 는 저장소의 절대 경로를 반환한다.
func (s *Store) Root() string { return s.root }

// resolve 는 사용자 입력 이름을 root 안의 실제 경로로 바꾼다.
//
// 경로 탈출 방지를 filepath.Base 로 처리하지 않는 이유: Base 는 "a/../../etc/x"
// 같은 입력을 "x" 로 조용히 바꿔치기해서, 사용자가 요청한 것과 다른 파일을
// 성공적으로 다루게 만든다. 여기서는 이름을 변형하지 않고 거부한다.
func (s *Store) resolve(name string) (string, error) {
	if name == "" || name == "." || name == ".." {
		return "", fmt.Errorf("%w: %q", ErrBadName, name)
	}
	// 구분자·상위참조·NUL·선행 점을 모두 거부한다(평평한 저장소이므로 하위 디렉터리 없음).
	if strings.ContainsAny(name, `/\`) || strings.Contains(name, "\x00") {
		return "", fmt.Errorf("%w: 경로 구분자를 포함할 수 없습니다: %q", ErrBadName, name)
	}
	if strings.HasPrefix(name, ".") {
		return "", fmt.Errorf("%w: 점으로 시작할 수 없습니다: %q", ErrBadName, name)
	}
	full := filepath.Join(s.root, name)
	// Join 이 정규화한 뒤에도 root 바로 아래인지 다시 확인한다(이중 방어).
	if filepath.Dir(full) != s.root {
		return "", fmt.Errorf("%w: 저장소 밖을 가리킵니다: %q", ErrBadName, name)
	}
	return full, nil
}

// FileInfo 는 API 로 노출되는 파일 메타데이터다.
type FileInfo struct {
	Name     string    `json:"name"`
	Size     int64     `json:"size"`
	Modified time.Time `json:"modified"`
}

// List 는 저장소의 일반 파일 목록을 이름순으로 반환한다.
// 디렉터리·심볼릭 링크 등 일반 파일이 아닌 항목은 제외한다.
func (s *Store) List() ([]FileInfo, error) {
	entries, err := os.ReadDir(s.root)
	if err != nil {
		return nil, fmt.Errorf("저장소 목록 조회 실패(%s): %w", s.root, err)
	}
	out := make([]FileInfo, 0, len(entries))
	for _, e := range entries {
		if !e.Type().IsRegular() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			// 목록 조회 중 파일이 지워질 수 있다. 그 항목만 건너뛴다.
			continue
		}
		out = append(out, FileInfo{Name: e.Name(), Size: info.Size(), Modified: info.ModTime()})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// Stat 은 파일 하나의 메타데이터를 반환한다.
func (s *Store) Stat(name string) (FileInfo, error) {
	full, err := s.resolve(name)
	if err != nil {
		return FileInfo{}, err
	}
	info, err := os.Stat(full)
	if errors.Is(err, os.ErrNotExist) {
		return FileInfo{}, fmt.Errorf("%w: %s", ErrNotFound, name)
	}
	if err != nil {
		return FileInfo{}, fmt.Errorf("stat 실패(%s): %w", name, err)
	}
	if !info.Mode().IsRegular() {
		return FileInfo{}, fmt.Errorf("%w: 일반 파일이 아닙니다: %s", ErrBadName, name)
	}
	return FileInfo{Name: name, Size: info.Size(), Modified: info.ModTime()}, nil
}

// Open 은 읽기용으로 파일을 연다. 호출자가 Close 해야 한다.
func (s *Store) Open(name string) (*os.File, error) {
	full, err := s.resolve(name)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(full)
	if errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("%w: %s", ErrNotFound, name)
	}
	if err != nil {
		return nil, fmt.Errorf("열기 실패(%s): %w", name, err)
	}
	return f, nil
}

// Write 는 r 의 내용을 name 으로 저장하고 기록된 바이트 수를 반환한다.
//
// 임시 파일에 먼저 쓰고 rename 으로 교체한다. 업로드가 중간에 끊겨도 기존
// 파일이 반쯤 덮인 상태로 남지 않는다 — 랩에서 네트워크 스토리지를 끊어보는
// 시나리오를 다루므로 이 성질이 필요하다.
//
// sync 가 true 면 rename 전에 fsync 한다. 벤치마크에서 페이지 캐시가 아니라
// 실제 스토리지 지연을 재려면 이 값을 켜야 한다.
func (s *Store) Write(name string, r io.Reader, sync bool) (n int64, err error) {
	full, err := s.resolve(name)
	if err != nil {
		return 0, err
	}
	tmp, err := os.CreateTemp(s.root, ".upload-*")
	if err != nil {
		return 0, fmt.Errorf("임시 파일 생성 실패(%s): %w", s.root, err)
	}
	tmpName := tmp.Name()
	defer func() {
		if err != nil {
			tmp.Close()
			os.Remove(tmpName)
		}
	}()

	n, err = io.Copy(tmp, r)
	if err != nil {
		return 0, fmt.Errorf("쓰기 실패(%s): %w", name, err)
	}
	if sync {
		if err = tmp.Sync(); err != nil {
			return 0, fmt.Errorf("fsync 실패(%s): %w", name, err)
		}
	}
	if err = tmp.Close(); err != nil {
		return 0, fmt.Errorf("임시 파일 닫기 실패(%s): %w", name, err)
	}
	if err = os.Chmod(tmpName, 0o644); err != nil {
		return 0, fmt.Errorf("권한 설정 실패(%s): %w", name, err)
	}
	if err = os.Rename(tmpName, full); err != nil {
		return 0, fmt.Errorf("교체 실패(%s): %w", name, err)
	}
	return n, nil
}

// Delete 는 파일을 삭제한다. 없으면 ErrNotFound.
func (s *Store) Delete(name string) error {
	full, err := s.resolve(name)
	if err != nil {
		return err
	}
	err = os.Remove(full)
	if errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("%w: %s", ErrNotFound, name)
	}
	if err != nil {
		return fmt.Errorf("삭제 실패(%s): %w", name, err)
	}
	return nil
}

// Usage 는 저장소가 올라앉은 파일시스템의 용량 정보다.
type Usage struct {
	Path       string `json:"path"`
	TotalBytes uint64 `json:"total_bytes"`
	FreeBytes  uint64 `json:"free_bytes"`
	UsedBytes  uint64 `json:"used_bytes"`
	// FSType 은 statfs 의 매직 넘버를 사람이 읽는 이름으로 옮긴 값이다.
	// 저장소가 기대한 백엔드에 실제로 올라가 있는지 확인하는 용도다.
	FSType string `json:"fs_type"`
}

// fsNames 는 이 랩에서 구분이 필요한 파일시스템 매직 넘버만 담는다.
// 목록에 없으면 16진수 매직을 그대로 노출한다 — 모르는 값을 "unknown" 으로
// 뭉개면 마운트가 어긋났을 때 원인을 못 찾는다.
var fsNames = map[int64]string{
	0x9123683E: "btrfs",
	0xC36400:   "ceph",
	0xEF53:     "ext2/3/4",
	0x6969:     "nfs",
	0x01021994: "tmpfs",
	0x58465342: "xfs",
	0x01021997: "v9fs",
	0x794C7630: "overlayfs",
	0x19830326: "fuse.beegfs",
	0x65735546: "fuse",
}

// Probe 는 저장소 디렉터리의 상태와 용량을 확인한다.
// 디렉터리가 없거나 디렉터리가 아니면 에러다 — 마운트가 빠진 노드를
// "정상"으로 보고하지 않기 위한 검사다.
func (s *Store) Probe() (Usage, error) {
	info, err := os.Stat(s.root)
	if err != nil {
		return Usage{}, fmt.Errorf("저장소 경로 확인 실패(%s): %w", s.root, err)
	}
	if !info.IsDir() {
		return Usage{}, fmt.Errorf("저장소 경로가 디렉터리가 아닙니다: %s", s.root)
	}
	var st syscall.Statfs_t
	if err := syscall.Statfs(s.root, &st); err != nil {
		return Usage{}, fmt.Errorf("statfs 실패(%s): %w", s.root, err)
	}
	bsize := uint64(st.Bsize)
	total := st.Blocks * bsize
	free := st.Bavail * bsize
	name, ok := fsNames[int64(st.Type)]
	if !ok {
		name = fmt.Sprintf("0x%x", uint64(st.Type))
	}
	return Usage{
		Path:       s.root,
		TotalBytes: total,
		FreeBytes:  free,
		UsedBytes:  total - free,
		FSType:     name,
	}, nil
}
