package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// postJSON 은 컨트롤러에 JSON 을 보내고 본문을 그대로 돌려준다.
// bench 하위 명령 전용이라 별도 패키지로 빼지 않는다.
func postJSON(ctx context.Context, url string, body []byte) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("요청 생성 실패(%s): %w", url, err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("컨트롤러 호출 실패(%s): %w", url, err)
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, fmt.Errorf("응답 읽기 실패: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		var e struct {
			Error string `json:"error"`
		}
		if json.Unmarshal(raw, &e) == nil && e.Error != "" {
			return nil, fmt.Errorf("컨트롤러 오류(%s): %s", resp.Status, e.Error)
		}
		return nil, fmt.Errorf("컨트롤러 오류(%s)", resp.Status)
	}
	return raw, nil
}
