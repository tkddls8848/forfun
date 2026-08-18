// Package control 은 컨트롤 노드에서 도는 컨트롤러다.
//
// 웹 UI 를 서빙하고, 등록된 스토리지 노드들에 대해 상태 조회·파일 작업·
// 벤치마크를 중계한다. 노드 팬아웃은 모두 동시에 수행한다 — 노드가 늘어날수록
// 순차 조회는 UI 응답 시간을 선형으로 늘리고, 죽은 노드 하나가 전체를 막는다.
package control

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"sort"
	"sync"
	"time"

	"gostore/internal/agent"
	"gostore/internal/bench"
	"gostore/internal/lab"
	"gostore/internal/web"
)

// Config 는 컨트롤러 기동 설정이다.
type Config struct {
	Addr      string
	Nodes     []lab.Node
	Token     string
	MaxUpload int64
}

// Controller 는 컨트롤러 서버다.
type Controller struct {
	cfg    Config
	client *lab.Client
	log    *slog.Logger

	// benchMu 는 랩 전체에서 벤치마크가 하나만 돌게 한다. 노드들이 같은
	// 백엔드를 공유하므로(예: 같은 Ceph 풀), 동시에 두 번 돌리면 서로를 방해한다.
	benchMu sync.Mutex
}

// New 는 Controller 를 만든다.
func New(cfg Config, log *slog.Logger) (*Controller, error) {
	if cfg.Token == "" {
		return nil, errors.New("token 이 비어 있습니다 (--token 또는 GOSTORE_TOKEN)")
	}
	if len(cfg.Nodes) == 0 {
		return nil, errors.New("등록된 노드가 없습니다 (--nodes)")
	}
	if cfg.MaxUpload <= 0 {
		cfg.MaxUpload = 1 << 30
	}
	return &Controller{cfg: cfg, client: lab.NewClient(cfg.Token), log: log}, nil
}

// Handler 는 라우터를 반환한다.
func (c *Controller) Handler() http.Handler {
	mux := http.NewServeMux()
	// UI 는 바이너리에 embed 되어 있다. 별도 정적 파일 배포가 없다.
	mux.Handle("GET /", http.FileServerFS(web.FS()))
	mux.HandleFunc("GET /api/nodes", c.handleNodes)
	mux.HandleFunc("GET /api/files", c.handleListFiles)
	mux.HandleFunc("PUT /api/files/{node}/{name}", c.handlePut)
	mux.HandleFunc("GET /api/files/{node}/{name}", c.handleGet)
	mux.HandleFunc("DELETE /api/files/{node}/{name}", c.handleDelete)
	mux.HandleFunc("POST /api/bench", c.handleBench)
	return mux
}

// Serve 는 ctx 가 끝날 때까지 서버를 돌린다.
func (c *Controller) Serve(ctx context.Context) error {
	srv := &http.Server{
		Addr:              c.cfg.Addr,
		Handler:           c.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}
	return serveUntilDone(ctx, srv, c.log)
}

// NodeStatus 는 UI 에 내려주는 노드 한 줄이다.
type NodeStatus struct {
	Name    string      `json:"name"`
	Addr    string      `json:"addr"`
	Backend string      `json:"backend"`
	OK      bool        `json:"ok"`
	Error   string      `json:"error,omitempty"`
	Usage   interface{} `json:"usage,omitempty"`
	// LatencyMS 는 health 응답까지 걸린 왕복 시간이다. 노드가 느려지기
	// 시작한 것을 UI 에서 바로 보기 위한 값이다.
	LatencyMS float64 `json:"latency_ms"`
}

func (c *Controller) handleNodes(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	out := make([]NodeStatus, len(c.cfg.Nodes))
	var wg sync.WaitGroup
	for i, n := range c.cfg.Nodes {
		wg.Add(1)
		go func(i int, n lab.Node) {
			defer wg.Done()
			st := NodeStatus{Name: n.Name, Addr: n.Addr, Backend: n.Backend}
			start := time.Now()
			h, err := c.client.Health(ctx, n.Addr)
			st.LatencyMS = float64(time.Since(start).Nanoseconds()) / 1e6
			switch {
			case err != nil:
				st.OK = false
				st.Error = err.Error()
			default:
				st.OK = h.OK
				st.Error = h.Error
				st.Usage = h.Usage
				if h.Backend != "" {
					st.Backend = h.Backend
				}
			}
			out[i] = st
		}(i, n)
	}
	wg.Wait()
	writeJSON(w, http.StatusOK, map[string]any{"nodes": out})
}

func (c *Controller) handleListFiles(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	type nodeFiles struct {
		Node  string         `json:"node"`
		Files []lab.FileInfo `json:"files"`
		Error string         `json:"error,omitempty"`
	}
	out := make([]nodeFiles, len(c.cfg.Nodes))
	var wg sync.WaitGroup
	for i, n := range c.cfg.Nodes {
		wg.Add(1)
		go func(i int, n lab.Node) {
			defer wg.Done()
			nf := nodeFiles{Node: n.Name, Files: []lab.FileInfo{}}
			files, err := c.client.ListFiles(ctx, n.Addr)
			if err != nil {
				nf.Error = err.Error()
			} else {
				nf.Files = files
			}
			out[i] = nf
		}(i, n)
	}
	wg.Wait()
	writeJSON(w, http.StatusOK, map[string]any{"nodes": out})
}

// nodeByName 은 등록된 노드를 찾는다. 등록되지 않은 주소로는 절대 중계하지
// 않는다 — 이름이 아니라 주소를 받아 프록시하면 SSRF 통로가 된다.
func (c *Controller) nodeByName(name string) (lab.Node, bool) {
	for _, n := range c.cfg.Nodes {
		if n.Name == name {
			return n, true
		}
	}
	return lab.Node{}, false
}

func (c *Controller) handlePut(w http.ResponseWriter, r *http.Request) {
	n, ok := c.nodeByName(r.PathValue("node"))
	if !ok {
		writeErr(w, http.StatusNotFound, "등록되지 않은 노드입니다: "+r.PathValue("node"))
		return
	}
	body := http.MaxBytesReader(w, r.Body, c.cfg.MaxUpload)
	defer body.Close()
	if err := c.client.PutFile(r.Context(), n.Addr, r.PathValue("name"), body); err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"node": n.Name, "name": r.PathValue("name")})
}

func (c *Controller) handleGet(w http.ResponseWriter, r *http.Request) {
	n, ok := c.nodeByName(r.PathValue("node"))
	if !ok {
		writeErr(w, http.StatusNotFound, "등록되지 않은 노드입니다: "+r.PathValue("node"))
		return
	}
	rc, size, err := c.client.GetFile(r.Context(), n.Addr, r.PathValue("name"))
	if err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	defer rc.Close()
	w.Header().Set("Content-Type", "application/octet-stream")
	if size >= 0 {
		w.Header().Set("Content-Length", fmt.Sprintf("%d", size))
	}
	if _, err := io.Copy(w, rc); err != nil {
		c.log.Warn("파일 중계 중단", "node", n.Name, "err", err)
	}
}

func (c *Controller) handleDelete(w http.ResponseWriter, r *http.Request) {
	n, ok := c.nodeByName(r.PathValue("node"))
	if !ok {
		writeErr(w, http.StatusNotFound, "등록되지 않은 노드입니다: "+r.PathValue("node"))
		return
	}
	if err := c.client.DeleteFile(r.Context(), n.Addr, r.PathValue("name")); err != nil {
		writeErr(w, http.StatusBadGateway, err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// BenchNodeResult 는 노드 하나의 벤치 결과다.
type BenchNodeResult struct {
	Node    string       `json:"node"`
	Backend string       `json:"backend"`
	Error   string       `json:"error,omitempty"`
	Result  bench.Result `json:"result"`
}

func (c *Controller) handleBench(w http.ResponseWriter, r *http.Request) {
	var req agent.BenchRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "요청 본문 파싱 실패: "+err.Error())
		return
	}
	if _, err := bench.ParseMode(req.Mode); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if req.Seconds <= 0 && req.Ops <= 0 {
		req.Seconds = 10
	}

	if !c.benchMu.TryLock() {
		writeErr(w, http.StatusConflict, "이미 벤치마크가 실행 중입니다")
		return
	}
	defer c.benchMu.Unlock()

	// 노드별 예상 소요 시간 + 준비/정리 여유. 이 값보다 짧게 잡으면 긴
	// 벤치마크가 클라이언트 타임아웃으로 잘려 결과를 못 받는다.
	budget := time.Duration(req.Seconds)*time.Second + 60*time.Second
	ctx, cancel := context.WithTimeout(r.Context(), budget)
	defer cancel()

	c.log.Info("랩 전체 벤치마크 시작", "nodes", len(c.cfg.Nodes), "mode", req.Mode,
		"concurrency", req.Concurrency, "seconds", req.Seconds)

	// 모든 노드에서 동시에 돌린다. 순차로 돌리면 노드 수 x 측정 시간이 되고,
	// 백엔드가 공유 자원일 때 "동시 부하 하에서의 지연"이라는 관심사가 사라진다.
	out := make([]BenchNodeResult, len(c.cfg.Nodes))
	var wg sync.WaitGroup
	for i, n := range c.cfg.Nodes {
		wg.Add(1)
		go func(i int, n lab.Node) {
			defer wg.Done()
			row := BenchNodeResult{Node: n.Name, Backend: n.Backend}
			resp, err := c.client.Bench(ctx, n.Addr, req)
			if err != nil {
				row.Error = err.Error()
			} else {
				row.Result = resp.Result
				if resp.Backend != "" {
					row.Backend = resp.Backend
				}
			}
			out[i] = row
		}(i, n)
	}
	wg.Wait()

	// p99 오름차순 — 백엔드 비교가 목적이므로 꼬리 지연이 좋은 순으로 세운다.
	// 실패한 노드는 비교 대상이 아니므로 뒤로 보낸다.
	sort.SliceStable(out, func(i, j int) bool {
		if (out[i].Error == "") != (out[j].Error == "") {
			return out[i].Error == ""
		}
		return out[i].Result.P99MS < out[j].Result.P99MS
	})
	writeJSON(w, http.StatusOK, map[string]any{"mode": req.Mode, "results": out})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

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
