// Package lab 은 노드 목록 정의와 에이전트 호출 클라이언트를 담는다.
package lab

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"gostore/internal/agent"
)

// Node 는 컨트롤러가 아는 스토리지 노드 하나다.
type Node struct {
	Name string `json:"name"`
	// Addr 은 "host:port" 형식의 에이전트 주소다.
	Addr string `json:"addr"`
	// Backend 는 표시용 라벨이다. 실제 값은 에이전트 health 응답으로 덮어쓴다.
	Backend string `json:"backend"`
}

// ParseNodes 는 "name=host:port,name2=host:port" 형식을 노드 목록으로 바꾼다.
// 백엔드 라벨은 "name=host:port:label" 로 덧붙일 수 있다.
func ParseNodes(spec string) ([]Node, error) {
	spec = strings.TrimSpace(spec)
	if spec == "" {
		return nil, fmt.Errorf("노드 목록이 비어 있습니다")
	}
	var out []Node
	seen := map[string]bool{}
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		name, rest, ok := strings.Cut(part, "=")
		if !ok {
			return nil, fmt.Errorf("노드 항목 형식이 잘못됐습니다(name=host:port): %q", part)
		}
		name = strings.TrimSpace(name)
		rest = strings.TrimSpace(rest)
		if name == "" || rest == "" {
			return nil, fmt.Errorf("노드 항목에 빈 값이 있습니다: %q", part)
		}
		if seen[name] {
			return nil, fmt.Errorf("노드 이름이 중복됐습니다: %q", name)
		}
		seen[name] = true

		n := Node{Name: name}
		// host:port[:label] — 콜론이 2개면 마지막이 라벨이다.
		if fields := strings.Split(rest, ":"); len(fields) == 3 {
			n.Addr = fields[0] + ":" + fields[1]
			n.Backend = fields[2]
		} else {
			n.Addr = rest
		}
		if !strings.Contains(n.Addr, ":") {
			return nil, fmt.Errorf("노드 주소에 포트가 없습니다: %q", n.Addr)
		}
		out = append(out, n)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("유효한 노드가 없습니다: %q", spec)
	}
	return out, nil
}

// Client 는 에이전트 HTTP API 클라이언트다.
type Client struct {
	http  *http.Client
	token string
}

// NewClient 는 타임아웃이 설정된 클라이언트를 만든다.
// 벤치마크 호출은 오래 걸리므로 Client 자체에는 전체 타임아웃을 두지 않고,
// 호출마다 context 로 제어한다.
func NewClient(token string) *Client {
	return &Client{
		http: &http.Client{
			Transport: &http.Transport{
				// 노드 수만큼 동시 연결이 필요하고, 벤치마크 중 연결 재사용이
				// 끊기면 측정에 TCP 핸드셰이크가 섞인다.
				MaxIdleConnsPerHost: 64,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		token: token,
	}
}

func (c *Client) do(ctx context.Context, method, addr, path string, body io.Reader, contentType string) (*http.Response, error) {
	u := &url.URL{Scheme: "http", Host: addr, Path: path}
	req, err := http.NewRequestWithContext(ctx, method, u.String(), body)
	if err != nil {
		return nil, fmt.Errorf("요청 생성 실패(%s %s): %w", method, u, err)
	}
	req.Header.Set("X-Gostore-Token", c.token)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("에이전트 호출 실패(%s): %w", addr, err)
	}
	return resp, nil
}

// apiError 는 에이전트가 돌려준 JSON 에러 본문을 읽어 error 로 만든다.
func apiError(resp *http.Response) error {
	defer resp.Body.Close()
	var payload struct {
		Error string `json:"error"`
	}
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 8<<10))
	if json.Unmarshal(raw, &payload) == nil && payload.Error != "" {
		return fmt.Errorf("에이전트 오류(%s): %s", resp.Status, payload.Error)
	}
	return fmt.Errorf("에이전트 오류(%s): %s", resp.Status, strings.TrimSpace(string(raw)))
}

// Health 는 노드 상태를 조회한다.
func (c *Client) Health(ctx context.Context, addr string) (agent.Health, error) {
	resp, err := c.do(ctx, http.MethodGet, addr, "/health", nil, "")
	if err != nil {
		return agent.Health{}, err
	}
	defer resp.Body.Close()
	// 마운트가 빠지면 503 + 정상 JSON 본문이 온다. 이 경우 본문을 그대로 살려
	// 이유를 UI 에 보여준다.
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusServiceUnavailable {
		return agent.Health{}, apiError(resp)
	}
	var h agent.Health
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<16)).Decode(&h); err != nil {
		return agent.Health{}, fmt.Errorf("health 응답 파싱 실패(%s): %w", addr, err)
	}
	return h, nil
}

// ListFiles 는 노드의 파일 목록을 조회한다.
func (c *Client) ListFiles(ctx context.Context, addr string) ([]FileInfo, error) {
	resp, err := c.do(ctx, http.MethodGet, addr, "/v1/files", nil, "")
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, apiError(resp)
	}
	defer resp.Body.Close()
	var payload struct {
		Files []FileInfo `json:"files"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(&payload); err != nil {
		return nil, fmt.Errorf("파일 목록 파싱 실패(%s): %w", addr, err)
	}
	return payload.Files, nil
}

// FileInfo 는 파일 목록 항목이다.
type FileInfo struct {
	Name     string    `json:"name"`
	Size     int64     `json:"size"`
	Modified time.Time `json:"modified"`
}

// PutFile 은 파일을 업로드한다.
func (c *Client) PutFile(ctx context.Context, addr, name string, r io.Reader) error {
	resp, err := c.do(ctx, http.MethodPut, addr, "/v1/files/"+url.PathEscape(name), r, "application/octet-stream")
	if err != nil {
		return err
	}
	if resp.StatusCode != http.StatusOK {
		return apiError(resp)
	}
	resp.Body.Close()
	return nil
}

// GetFile 은 파일 내용을 스트림으로 연다. 호출자가 Close 해야 한다.
func (c *Client) GetFile(ctx context.Context, addr, name string) (io.ReadCloser, int64, error) {
	resp, err := c.do(ctx, http.MethodGet, addr, "/v1/files/"+url.PathEscape(name), nil, "")
	if err != nil {
		return nil, 0, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, 0, apiError(resp)
	}
	return resp.Body, resp.ContentLength, nil
}

// DeleteFile 은 파일을 삭제한다.
func (c *Client) DeleteFile(ctx context.Context, addr, name string) error {
	resp, err := c.do(ctx, http.MethodDelete, addr, "/v1/files/"+url.PathEscape(name), nil, "")
	if err != nil {
		return err
	}
	if resp.StatusCode != http.StatusNoContent {
		return apiError(resp)
	}
	resp.Body.Close()
	return nil
}

// Bench 는 노드에서 로컬 벤치마크를 실행하고 결과를 받는다.
func (c *Client) Bench(ctx context.Context, addr string, req agent.BenchRequest) (agent.BenchResponse, error) {
	buf, err := json.Marshal(req)
	if err != nil {
		return agent.BenchResponse{}, fmt.Errorf("벤치 요청 직렬화 실패: %w", err)
	}
	resp, err := c.do(ctx, http.MethodPost, addr, "/v1/bench", bytes.NewReader(buf), "application/json")
	if err != nil {
		return agent.BenchResponse{}, err
	}
	if resp.StatusCode != http.StatusOK {
		return agent.BenchResponse{}, apiError(resp)
	}
	defer resp.Body.Close()
	var out agent.BenchResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&out); err != nil {
		return agent.BenchResponse{}, fmt.Errorf("벤치 응답 파싱 실패(%s): %w", addr, err)
	}
	return out, nil
}
