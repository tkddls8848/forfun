package lab

import "testing"

func TestParseNodes(t *testing.T) {
	nodes, err := ParseNodes("w1=10.0.0.11:4000, w2=10.0.0.12:4000:cephfs")
	if err != nil {
		t.Fatalf("ParseNodes: %v", err)
	}
	if len(nodes) != 2 {
		t.Fatalf("노드 %d개, want 2", len(nodes))
	}
	if nodes[0].Name != "w1" || nodes[0].Addr != "10.0.0.11:4000" || nodes[0].Backend != "" {
		t.Fatalf("nodes[0] = %+v", nodes[0])
	}
	// host:port:label 형식에서 라벨만 떼어내고 주소는 온전해야 한다.
	if nodes[1].Addr != "10.0.0.12:4000" || nodes[1].Backend != "cephfs" {
		t.Fatalf("nodes[1] = %+v", nodes[1])
	}
}

func TestParseNodesRejectsBadInput(t *testing.T) {
	bad := []string{
		"",                          // 빈 목록
		"w1",                        // = 없음
		"w1=",                       // 주소 없음
		"=10.0.0.1:4000",            // 이름 없음
		"w1=10.0.0.1",               // 포트 없음
		"w1=1.1.1.1:1,w1=2.2.2.2:2", // 이름 중복
	}
	for _, spec := range bad {
		if _, err := ParseNodes(spec); err == nil {
			t.Errorf("ParseNodes(%q) 가 통과했습니다", spec)
		}
	}
}
