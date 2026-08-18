// Command gostore 는 스토리지 랩의 에이전트·컨트롤러·벤치마커를 겸하는
// 단일 실행 파일이다.
//
// 역할을 하나의 바이너리에 몰아넣은 이유: 랩 배포 산출물이 파일 하나여야
// "런타임도 패키지 매니저도 없는 노드에 scp 한 번"이라는 성질이 성립한다.
// 역할별로 바이너리를 나누면 배포 대상이 다시 여러 개가 된다.
//
//	gostore agent    --store-dir /mnt/cephfs --token ... --node w1
//	gostore control  --nodes w1=10.0.0.11:4000,w2=10.0.0.12:4000 --token ...
//	gostore bench    --control 10.0.0.10:3333 --mode mixed --concurrency 32
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"gostore/internal/agent"
	"gostore/internal/bench"
	"gostore/internal/control"
	"gostore/internal/lab"
)

// version 은 빌드 시 -ldflags 로 주입한다. scripts/build.sh 참고.
var version = "dev"

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "gostore: %v\n", err)
		os.Exit(1)
	}
}

func usage() string {
	return strings.TrimSpace(`
gostore — 스토리지 랩 에이전트/컨트롤러/벤치마커 (단일 정적 바이너리)

사용법:
  gostore agent    [flags]   스토리지 노드에서 저장소를 서빙한다
  gostore control  [flags]   컨트롤 노드에서 UI 와 노드 중계를 제공한다
  gostore bench    [flags]   컨트롤러에 랩 전체 벤치마크를 요청하고 표로 출력한다
  gostore version            버전을 출력한다

각 하위 명령의 옵션은 -h 로 확인한다 (예: gostore agent -h).
`)
}

func run() error {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, usage())
		return fmt.Errorf("하위 명령이 필요합니다")
	}
	// SIGINT/SIGTERM 에 진행 중인 요청을 정리하고 내려간다. systemd 가
	// 재시작할 때 업로드가 반쯤 끊긴 파일을 남기지 않기 위한 것이다.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	switch os.Args[1] {
	case "agent":
		return runAgent(ctx, os.Args[2:])
	case "control":
		return runControl(ctx, os.Args[2:])
	case "bench":
		return runBench(ctx, os.Args[2:])
	case "version":
		fmt.Println(version)
		return nil
	case "-h", "--help", "help":
		fmt.Println(usage())
		return nil
	default:
		fmt.Fprintln(os.Stderr, usage())
		return fmt.Errorf("알 수 없는 하위 명령: %q", os.Args[1])
	}
}

func newLogger(role string) *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo})).
		With("role", role)
}

// envOr 는 플래그가 비었을 때 환경변수로 채운다. 토큰을 커맨드라인에 두면
// 같은 노드의 다른 사용자에게 ps 로 노출되므로 환경변수 경로를 항상 남겨둔다.
func envOr(flagVal, envKey string) string {
	if flagVal != "" {
		return flagVal
	}
	return os.Getenv(envKey)
}

func runAgent(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("agent", flag.ExitOnError)
	var (
		node     = fs.String("node", hostnameOr("agent"), "노드 이름 (UI 표시용)")
		addr     = fs.String("addr", ":4000", "리스닝 주소")
		storeDir = fs.String("store-dir", "/srv/gostore", "마운트된 저장소 경로")
		token    = fs.String("token", "", "컨트롤러와 공유하는 시크릿 (미지정 시 GOSTORE_TOKEN)")
		backend  = fs.String("backend", "", "백엔드 라벨 (cephfs/rbd/beegfs/nfs/local 등)")
		maxUp    = fs.Int64("max-upload", 1<<30, "업로드 상한 (바이트)")
	)
	if err := fs.Parse(args); err != nil {
		return err
	}
	log := newLogger("agent")
	a, err := agent.New(agent.Config{
		Node:      *node,
		Addr:      *addr,
		StoreDir:  *storeDir,
		Token:     envOr(*token, "GOSTORE_TOKEN"),
		Backend:   *backend,
		MaxUpload: *maxUp,
	}, log)
	if err != nil {
		return err
	}
	log.Info("에이전트 기동", "node", *node, "store", *storeDir, "backend", *backend, "version", version)
	return a.Serve(ctx)
}

func runControl(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("control", flag.ExitOnError)
	var (
		addr     = fs.String("addr", ":3333", "리스닝 주소")
		nodeSpec = fs.String("nodes", "", "노드 목록: name=host:port[:backend],... (미지정 시 GOSTORE_NODES)")
		token    = fs.String("token", "", "에이전트와 공유하는 시크릿 (미지정 시 GOSTORE_TOKEN)")
		maxUp    = fs.Int64("max-upload", 1<<30, "업로드 상한 (바이트)")
	)
	if err := fs.Parse(args); err != nil {
		return err
	}
	nodes, err := lab.ParseNodes(envOr(*nodeSpec, "GOSTORE_NODES"))
	if err != nil {
		return err
	}
	log := newLogger("control")
	c, err := control.New(control.Config{
		Addr:      *addr,
		Nodes:     nodes,
		Token:     envOr(*token, "GOSTORE_TOKEN"),
		MaxUpload: *maxUp,
	}, log)
	if err != nil {
		return err
	}
	log.Info("컨트롤러 기동", "nodes", len(nodes), "addr", *addr, "version", version)
	return c.Serve(ctx)
}

func runBench(ctx context.Context, args []string) error {
	fs := flag.NewFlagSet("bench", flag.ExitOnError)
	var (
		ctrl    = fs.String("control", "127.0.0.1:3333", "컨트롤러 주소")
		mode    = fs.String("mode", "mixed", "부하 종류: write|read|mixed")
		conc    = fs.Int("concurrency", 16, "동시 워커 수")
		seconds = fs.Int("seconds", 10, "측정 시간(초)")
		ops     = fs.Int("ops", 0, "총 연산 수 (지정 시 seconds 무시)")
		payload = fs.Int("payload-kb", 64, "연산당 페이로드 크기(KB)")
		fsync   = fs.Bool("fsync", false, "쓰기마다 fsync (스토리지까지 내려가는 지연 측정)")
		asJSON  = fs.Bool("json", false, "결과를 JSON 으로 출력")
	)
	if err := fs.Parse(args); err != nil {
		return err
	}
	if _, err := bench.ParseMode(*mode); err != nil {
		return err
	}

	req := agent.BenchRequest{
		Mode: *mode, Concurrency: *conc, Seconds: *seconds,
		Ops: *ops, PayloadKB: *payload, FSync: *fsync,
	}
	body, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("요청 직렬화 실패: %w", err)
	}

	// 컨트롤러 쪽 예산(seconds + 60s)보다 넉넉하게 잡는다. 클라이언트가 먼저
	// 끊으면 서버는 계속 도는데 결과만 못 받는 최악의 조합이 된다.
	budget := time.Duration(*seconds)*time.Second + 120*time.Second
	reqCtx, cancel := context.WithTimeout(ctx, budget)
	defer cancel()

	fmt.Fprintf(os.Stderr, "벤치마크 요청: control=%s mode=%s concurrency=%d payload=%dKB fsync=%v\n",
		*ctrl, *mode, *conc, *payload, *fsync)

	raw, err := postJSON(reqCtx, "http://"+*ctrl+"/api/bench", body)
	if err != nil {
		return err
	}
	if *asJSON {
		os.Stdout.Write(raw)
		return nil
	}

	var out struct {
		Mode    string                    `json:"mode"`
		Results []control.BenchNodeResult `json:"results"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return fmt.Errorf("응답 파싱 실패: %w", err)
	}
	fmt.Printf("\nmode=%s concurrency=%d payload=%dKB fsync=%v\n\n", out.Mode, *conc, *payload, *fsync)
	for _, r := range out.Results {
		if r.Error != "" {
			fmt.Printf("%-16s [실패] %s\n", r.Node, r.Error)
			continue
		}
		label := r.Node
		if r.Backend != "" {
			label = r.Node + "/" + r.Backend
		}
		fmt.Println(r.Result.Format(label))
	}
	fmt.Println()
	return nil
}

func hostnameOr(def string) string {
	if h, err := os.Hostname(); err == nil && h != "" {
		return h
	}
	return def
}
