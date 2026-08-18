package control

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"

	"gostore/internal/agent"
	"gostore/internal/lab"
)

const testToken = "test-token"

func quietLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, &slog.HandlerOptions{Level: slog.LevelError}))
}

// startAgent 는 임시 디렉터리를 저장소로 쓰는 에이전트를 띄우고 "host:port" 를 반환한다.
func startAgent(t *testing.T, name, backend string) string {
	t.Helper()
	a, err := agent.New(agent.Config{
		Node: name, StoreDir: t.TempDir(), Token: testToken, Backend: backend,
	}, quietLogger())
	if err != nil {
		t.Fatalf("agent.New: %v", err)
	}
	srv := httptest.NewServer(a.Handler())
	t.Cleanup(srv.Close)
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	return u.Host
}

// startLab 은 에이전트 2대와 컨트롤러를 띄우고 컨트롤러 테스트 서버를 반환한다.
func startLab(t *testing.T) *httptest.Server {
	t.Helper()
	nodes := []lab.Node{
		{Name: "w1", Addr: startAgent(t, "w1", "cephfs"), Backend: "cephfs"},
		{Name: "w2", Addr: startAgent(t, "w2", "rbd"), Backend: "rbd"},
	}
	c, err := New(Config{Nodes: nodes, Token: testToken}, quietLogger())
	if err != nil {
		t.Fatalf("control.New: %v", err)
	}
	srv := httptest.NewServer(c.Handler())
	t.Cleanup(srv.Close)
	return srv
}

func decode[T any](t *testing.T, resp *http.Response, want int) T {
	t.Helper()
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != want {
		t.Fatalf("status = %d, want %d: %s", resp.StatusCode, want, raw)
	}
	var out T
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatalf("파싱 실패: %v (본문: %s)", err, raw)
	}
	return out
}

func TestNodesFanOut(t *testing.T) {
	srv := startLab(t)
	resp, err := http.Get(srv.URL + "/api/nodes")
	if err != nil {
		t.Fatal(err)
	}
	out := decode[struct {
		Nodes []NodeStatus `json:"nodes"`
	}](t, resp, http.StatusOK)

	if len(out.Nodes) != 2 {
		t.Fatalf("노드 %d개, want 2", len(out.Nodes))
	}
	for _, n := range out.Nodes {
		if !n.OK {
			t.Fatalf("노드 %s 가 비정상: %s", n.Name, n.Error)
		}
		if n.Backend == "" {
			t.Fatalf("노드 %s 의 백엔드 라벨이 비었습니다", n.Name)
		}
	}
	// 팬아웃은 응답 순서가 아니라 인덱스로 채워야 노드 순서가 유지된다.
	if out.Nodes[0].Name != "w1" || out.Nodes[1].Name != "w2" {
		t.Fatalf("노드 순서가 어긋났습니다: %s, %s", out.Nodes[0].Name, out.Nodes[1].Name)
	}
}

func TestUIIsEmbedded(t *testing.T) {
	srv := startLab(t)
	resp, err := http.Get(srv.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	// UI 가 바이너리 안에서 나온다는 것이 이 랩의 핵심 성질이다.
	// 정적 파일 디렉터리 없이도 서빙돼야 한다.
	if !strings.Contains(string(body), "gostore lab") {
		t.Fatalf("embed 된 UI 가 서빙되지 않았습니다 (%d bytes)", len(body))
	}
}

func TestFileRoundTripThroughController(t *testing.T) {
	srv := startLab(t)
	payload := bytes.Repeat([]byte("데이터"), 500)

	req, _ := http.NewRequest(http.MethodPut, srv.URL+"/api/files/w1/hello.bin", bytes.NewReader(payload))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("업로드 status = %d", resp.StatusCode)
	}

	resp, err = http.Get(srv.URL + "/api/files/w1/hello.bin")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	got, _ := io.ReadAll(resp.Body)
	if !bytes.Equal(got, payload) {
		t.Fatalf("내려받은 내용이 다릅니다 (%d vs %d bytes)", len(got), len(payload))
	}

	// 목록에는 w1 에만 보여야 한다 — 노드별 저장소가 분리돼 있는지 확인.
	resp, err = http.Get(srv.URL + "/api/files")
	if err != nil {
		t.Fatal(err)
	}
	list := decode[struct {
		Nodes []struct {
			Node  string         `json:"node"`
			Files []lab.FileInfo `json:"files"`
		} `json:"nodes"`
	}](t, resp, http.StatusOK)
	for _, n := range list.Nodes {
		switch n.Node {
		case "w1":
			if len(n.Files) != 1 || n.Files[0].Name != "hello.bin" {
				t.Fatalf("w1 파일 목록이 잘못됐습니다: %v", n.Files)
			}
		case "w2":
			if len(n.Files) != 0 {
				t.Fatalf("w2 에 파일이 새어 들어갔습니다: %v", n.Files)
			}
		}
	}

	req, _ = http.NewRequest(http.MethodDelete, srv.URL+"/api/files/w1/hello.bin", nil)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("삭제 status = %d", resp.StatusCode)
	}
}

func TestUnregisteredNodeIsRejected(t *testing.T) {
	srv := startLab(t)
	// 컨트롤러는 이름으로만 중계한다. 임의 주소를 태워 보낼 통로가 있으면
	// 그대로 SSRF 가 된다.
	resp, err := http.Get(srv.URL + "/api/files/evil.example.com:80/x")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func TestAgentRequiresToken(t *testing.T) {
	addr := startAgent(t, "w1", "local")

	// /health 는 토큰 없이 열려 있다 (배포 스크립트의 기동 대기용).
	resp, err := http.Get("http://" + addr + "/health")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("health status = %d, want 200", resp.StatusCode)
	}

	// 데이터 경로는 토큰이 없으면 막혀야 한다.
	resp, err = http.Get("http://" + addr + "/v1/files")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("토큰 없는 /v1/files status = %d, want 401", resp.StatusCode)
	}

	// 틀린 토큰도 막혀야 한다.
	req, _ := http.NewRequest(http.MethodGet, "http://"+addr+"/v1/files", nil)
	req.Header.Set("X-Gostore-Token", "wrong")
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("틀린 토큰 status = %d, want 401", resp.StatusCode)
	}
}

func TestAgentRejectsPathEscape(t *testing.T) {
	addr := startAgent(t, "w1", "local")
	// URL 인코딩된 경로 탈출 시도가 저장소 밖에 닿으면 안 된다.
	req, _ := http.NewRequest(http.MethodPut,
		"http://"+addr+"/v1/files/"+url.PathEscape("../escaped.txt"), strings.NewReader("x"))
	req.Header.Set("X-Gostore-Token", testToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status = %d, want 400 (%s)", resp.StatusCode, body)
	}
}

func TestBenchAcrossNodes(t *testing.T) {
	srv := startLab(t)
	body, _ := json.Marshal(agent.BenchRequest{
		Mode: "mixed", Concurrency: 4, Ops: 40, PayloadKB: 4,
	})
	resp, err := http.Post(srv.URL+"/api/bench", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	out := decode[struct {
		Mode    string            `json:"mode"`
		Results []BenchNodeResult `json:"results"`
	}](t, resp, http.StatusOK)

	if len(out.Results) != 2 {
		t.Fatalf("결과 %d개, want 2", len(out.Results))
	}
	for _, r := range out.Results {
		if r.Error != "" {
			t.Fatalf("노드 %s 실패: %s", r.Node, r.Error)
		}
		if r.Result.Ops != 40 {
			t.Fatalf("노드 %s ops = %d, want 40", r.Node, r.Result.Ops)
		}
		if r.Result.P99MS < r.Result.P50MS {
			t.Fatalf("노드 %s: p99(%v) < p50(%v)", r.Node, r.Result.P99MS, r.Result.P50MS)
		}
		if r.Result.ThroughputMBps <= 0 {
			t.Fatalf("노드 %s 처리량이 0 입니다", r.Node)
		}
	}
	// p99 오름차순 정렬 확인.
	if out.Results[0].Result.P99MS > out.Results[1].Result.P99MS {
		t.Fatalf("p99 정렬이 어긋났습니다: %v > %v",
			out.Results[0].Result.P99MS, out.Results[1].Result.P99MS)
	}
}

func TestBenchRejectsBadMode(t *testing.T) {
	srv := startLab(t)
	resp, err := http.Post(srv.URL+"/api/bench", "application/json",
		strings.NewReader(`{"mode":"append"}`))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

func TestControlValidatesConfig(t *testing.T) {
	if _, err := New(Config{Nodes: []lab.Node{{Name: "a", Addr: "x:1"}}}, quietLogger()); err == nil {
		t.Error("토큰 없이 생성이 통과했습니다")
	}
	if _, err := New(Config{Token: "t"}, quietLogger()); err == nil {
		t.Error("노드 없이 생성이 통과했습니다")
	}
}

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}
