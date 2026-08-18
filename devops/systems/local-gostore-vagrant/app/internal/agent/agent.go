// Package agent 는 스토리지 노드에서 도는 HTTP 에이전트다.
//
// 마운트된 저장소 하나에 대한 파일 CRUD 와, 그 저장소에 직접 부하를 거는
// 로컬 벤치마크를 제공한다. 컨트롤러만 호출하는 내부 API 이므로 공유 토큰으로
// 보호한다.
package agent

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"gostore/internal/bench"
	"gostore/internal/store"
)

// Config 는 에이전트 기동 설정이다.
type Config struct {
	Node      string // 노드 이름 (컨트롤러 UI 에 표시)
	Addr      string // 리스닝 주소
	StoreDir  string // 마운트된 저장소 경로
	Token     string // 컨트롤러와 공유하는 시크릿
	Backend   string // 이 저장소가 어떤 백엔드인지 표시용 라벨 (cephfs/rbd/nfs/local ...)
	MaxUpload int64  // 업로드 상한 (바이트)
}

// Agent 는 에이전트 HTTP 서버다.
type Agent struct {
	cfg   Config
	store *store.Store
	log   *slog.Logger

	// benchMu 는 동시에 두 개의 벤치마크가 도는 것을 막는다. 겹쳐 돌면 서로의
	// 부하가 상대의 측정값에 섞여 들어가 결과가 무의미해진다.
	benchMu sync.Mutex
}

// New 는 Agent 를 만든다.
func New(cfg Config, log *slog.Logger) (*Agent, error) {
	if cfg.Token == "" {
		return nil, errors.New("token 이 비어 있습니다 (--token 또는 GOSTORE_TOKEN)")
	}
	if cfg.StoreDir == "" {
		return nil, errors.New("store-dir 이 비어 있습니다")
	}
	if cfg.MaxUpload <= 0 {
		cfg.MaxUpload = 1 << 30 // 1GiB
	}
	if cfg.Node == "" {
		cfg.Node = "agent"
	}
	st, err := store.New(cfg.StoreDir)
	if err != nil {
		return nil, err
	}
	return &Agent{cfg: cfg, store: st, log: log}, nil
}

// Handler 는 인증이 적용된 라우터를 반환한다.
func (a *Agent) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", a.handleHealth)
	mux.HandleFunc("GET /v1/files", a.handleList)
	mux.HandleFunc("GET /v1/files/{name}", a.handleGet)
	mux.HandleFunc("PUT /v1/files/{name}", a.handlePut)
	mux.HandleFunc("DELETE /v1/files/{name}", a.handleDelete)
	mux.HandleFunc("POST /v1/bench", a.handleBench)
	return a.withAuth(mux)
}

// Serve 는 ctx 가 끝날 때까지 HTTP 서버를 돌린다.
func (a *Agent) Serve(ctx context.Context) error {
	srv := &http.Server{
		Addr:              a.cfg.Addr,
		Handler:           a.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		// 대용량 업로드와 장시간 벤치마크가 있으므로 Write/Read 전체 타임아웃은
		// 두지 않고 헤더 타임아웃만 건다.
	}
	return serveUntilDone(ctx, srv, a.log)
}

// withAuth 는 /health 를 제외한 모든 경로에 공유 토큰을 요구한다.
// /health 를 여는 이유: 노드가 아직 토큰을 못 받은 상태에서도 기동 여부를
// 확인할 수 있어야 배포 스크립트가 대기할 수 있다.
func (a *Agent) withAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			next.ServeHTTP(w, r)
			return
		}
		got := r.Header.Get("X-Gostore-Token")
		// 상수 시간 비교 — 토큰을 타이밍으로 한 바이트씩 알아내는 경로를 막는다.
		if subtle.ConstantTimeCompare([]byte(got), []byte(a.cfg.Token)) != 1 {
			writeErr(w, http.StatusUnauthorized, "토큰이 올바르지 않습니다")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// Health 는 에이전트 상태 응답이다.
type Health struct {
	Node    string      `json:"node"`
	Backend string      `json:"backend"`
	OK      bool        `json:"ok"`
	Error   string      `json:"error,omitempty"`
	Usage   store.Usage `json:"usage"`
}

func (a *Agent) handleHealth(w http.ResponseWriter, r *http.Request) {
	h := Health{Node: a.cfg.Node, Backend: a.cfg.Backend}
	usage, err := a.store.Probe()
	if err != nil {
		// 마운트가 빠진 상태를 200 OK 로 보고하지 않는다. 컨트롤러가 이 노드를
		// 정상으로 보고 트래픽을 보내면 조용히 로컬 디스크에 쓰게 된다.
		h.OK = false
		h.Error = err.Error()
		writeJSON(w, http.StatusServiceUnavailable, h)
		return
	}
	h.OK = true
	h.Usage = usage
	writeJSON(w, http.StatusOK, h)
}

func (a *Agent) handleList(w http.ResponseWriter, r *http.Request) {
	files, err := a.store.List()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"node": a.cfg.Node, "files": files})
}

func (a *Agent) handleGet(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	f, err := a.store.Open(name)
	if err != nil {
		writeStoreErr(w, err)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.FormatInt(info.Size(), 10))
	// http.ServeContent 대신 Copy 를 쓰는 이유: Range 요청을 지원하지 않으므로
	// 부분 응답을 광고하지 않는 편이 정직하다.
	if _, err := io.Copy(w, f); err != nil {
		a.log.Warn("파일 전송 중단", "name", name, "err", err)
	}
}

func (a *Agent) handlePut(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	sync := r.URL.Query().Get("fsync") == "1"
	body := http.MaxBytesReader(w, r.Body, a.cfg.MaxUpload)
	defer body.Close()

	n, err := a.store.Write(name, body, sync)
	if err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			writeErr(w, http.StatusRequestEntityTooLarge,
				fmt.Sprintf("업로드 상한(%d bytes) 초과", a.cfg.MaxUpload))
			return
		}
		writeStoreErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"node": a.cfg.Node, "name": name, "size": n})
}

func (a *Agent) handleDelete(w http.ResponseWriter, r *http.Request) {
	if err := a.store.Delete(r.PathValue("name")); err != nil {
		writeStoreErr(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// BenchRequest 는 에이전트에게 요청하는 로컬 벤치마크 파라미터다.
type BenchRequest struct {
	Mode        string `json:"mode"`
	Concurrency int    `json:"concurrency"`
	Seconds     int    `json:"seconds"`
	Ops         int    `json:"ops"`
	PayloadKB   int    `json:"payload_kb"`
	FSync       bool   `json:"fsync"`
}

// BenchResponse 는 벤치마크 결과에 노드 정보를 붙인 응답이다.
type BenchResponse struct {
	Node    string       `json:"node"`
	Backend string       `json:"backend"`
	Mode    string       `json:"mode"`
	Result  bench.Result `json:"result"`
}

func (a *Agent) handleBench(w http.ResponseWriter, r *http.Request) {
	var req BenchRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "요청 본문 파싱 실패: "+err.Error())
		return
	}
	mode, err := bench.ParseMode(req.Mode)
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Concurrency < 1 {
		req.Concurrency = 8
	}
	if req.PayloadKB < 1 {
		req.PayloadKB = 64
	}
	if req.Ops <= 0 && req.Seconds <= 0 {
		req.Seconds = 10
	}

	if !a.benchMu.TryLock() {
		writeErr(w, http.StatusConflict, "이 노드에서 이미 벤치마크가 실행 중입니다")
		return
	}
	defer a.benchMu.Unlock()

	if _, err := a.store.Probe(); err != nil {
		writeErr(w, http.StatusServiceUnavailable, err.Error())
		return
	}

	wl := &bench.LocalWorkload{
		Store:   a.store,
		Mode:    mode,
		Payload: int64(req.PayloadKB) * 1024,
		Prefix:  "bench-",
		FSync:   req.FSync,
	}
	if err := wl.Prepare(); err != nil {
		writeErr(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer wl.Cleanup()

	a.log.Info("벤치마크 시작", "node", a.cfg.Node, "mode", mode,
		"concurrency", req.Concurrency, "payload_kb", req.PayloadKB, "fsync", req.FSync)

	res, err := bench.Run(r.Context(), bench.Config{
		Concurrency: req.Concurrency,
		Duration:    time.Duration(req.Seconds) * time.Second,
		Ops:         req.Ops,
		BytesPerOp:  wl.BytesPerOp(),
	}, wl.Op())
	if err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	a.log.Info("벤치마크 완료", "node", a.cfg.Node, "ops", res.Ops,
		"errors", res.Errors, "p99_ms", res.P99MS)

	writeJSON(w, http.StatusOK, BenchResponse{
		Node: a.cfg.Node, Backend: a.cfg.Backend, Mode: string(mode), Result: res,
	})
}

// writeStoreErr 는 store 에러를 알맞은 HTTP 상태로 옮긴다.
func writeStoreErr(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeErr(w, http.StatusNotFound, err.Error())
	case errors.Is(err, store.ErrBadName):
		writeErr(w, http.StatusBadRequest, err.Error())
	default:
		writeErr(w, http.StatusInternalServerError, err.Error())
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

// serveUntilDone 은 ctx 종료 시 유예 시간을 두고 서버를 닫는다.
func serveUntilDone(ctx context.Context, srv *http.Server, log *slog.Logger) error {
	errCh := make(chan error, 1)
	go func() {
		log.Info("리스닝 시작", "addr", srv.Addr)
		err := srv.ListenAndServe()
		if errors.Is(err, http.ErrServerClosed) {
			err = nil
		}
		errCh <- err
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		log.Info("종료 신호 수신, 진행 중 요청 정리")
		shutCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutCtx); err != nil {
			return fmt.Errorf("graceful shutdown 실패: %w", err)
		}
		return <-errCh
	}
}

// SplitHostPortDefault 는 "host" 또는 "host:port" 를 받아 포트가 없으면 기본값을 붙인다.
func SplitHostPortDefault(addr, defPort string) string {
	if strings.Contains(addr, ":") {
		return addr
	}
	return addr + ":" + defPort
}
