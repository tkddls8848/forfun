# local-gostore-vagrant

Go 단일 정적 바이너리로 배포되는 스토리지 랩. VirtualBox 위에 컨트롤 노드 1대와
스토리지 노드 3대(xfs / ext4 / tmpfs)를 올리고, 세 백엔드의 지연 분포를 같은
부하에서 비교한다.

## 이 랩이 다루는 것

이 저장소의 다른 스토리지 랩은 **백엔드 자체**(Ceph, BeeGFS, Rook)를 다룬다.
이 랩이 보려는 것은 그게 아니라 **배포 산출물이 파일 하나일 때 노드 프로비저닝이
어떻게 달라지는가**이다. 그래서 백엔드는 커널 파일시스템으로만 구성하고 외부
스토리지 클러스터를 끌어들이지 않는다. Ceph/BeeGFS 비교가 목적이라면
`local-ceph-vagrant` 나 `aws-k3s-storage-lab` 을 볼 것.

대조군은 `local-ceph-vagrant/apps/block-store-app` (Node.js) 이다. 같은 모양의
중앙앱 + 노드 에이전트 구조를 Go 로 다시 만들었을 때 무엇이 사라지는지가
이 랩의 내용이다.

| | Node.js 에이전트 (`local-ceph-vagrant`) | 이 랩 |
| --- | --- | --- |
| 노드 배포물 | `app.js` + `package.json` + `node_modules/` | 바이너리 1개 (6.5 MB) |
| 노드 사전 요구 | NodeSource 저장소 추가 → `apt-get install nodejs` → `npm install` | 없음 |
| 노드의 외부 의존 | 인터넷, apt 미러, npm 레지스트리 | 없음 |
| 런타임 | Node.js 20 | 없음 (정적 링크, libc 도 없음) |
| 웹 UI 배포 | `public/` 디렉터리 별도 배포 | 바이너리에 `//go:embed` |
| 외부 패키지 | express, multer (+전이 의존성) | 0 개 (stdlib 만) |
| 크로스 아키텍처 | 노드마다 각자 설치 | 호스트에서 amd64/arm64 동시 산출 |

`scripts/provision/20_agent.sh` 에 패키지 설치가 한 줄도 없다는 점이 요점이다.
대조군의 같은 자리(`run-agent.sh`)는 세 개의 외부 서비스에 의존한다.

## 빠른 시작

```bash
# 1. 호스트에서 빌드 (Go 1.24+ 필요, 노드에는 불필요)
bash scripts/build.sh

# 2. 랩 기동 — 마지막에 검증과 스모크 벤치마크가 자동으로 돈다
vagrant up

# 3. UI
open http://localhost:3333

# 4. 벤치마크
bash scripts/lifecycle/bench.sh --mode write --fsync --seconds 20
bash scripts/lifecycle/bench.sh --matrix     # 조합 전체

# 5. 정리
bash scripts/lifecycle/destroy.sh
```

`vagrant up` 은 `dist/` 에 바이너리가 없으면 VM 을 만들기 전에 실패한다.
프로비저닝 중간에 "파일 없음"으로 깨지면 되돌리는 비용이 크기 때문이다.

## 왜 평균이 아니라 p99 인가

백엔드 비교에서 평균 지연은 거의 쓸모가 없다. 아래는 이 코드로 실제로 잰
값이다 (tmpfs vs ext4, 동시성 32, 64KB 페이로드):

```
mode=mixed  fsync=off
  tmpfs   70280 op/s  4392.5 MB/s   p50=0.02ms  p95=0.09ms  p99=16.02ms  max=146.83ms
  ext4    23351 op/s  1459.4 MB/s   p50=0.02ms  p95=1.57ms  p99=42.64ms  max=143.83ms

mode=write  fsync=on
  tmpfs   20842 op/s  1302.6 MB/s   p50=0.05ms  p95=11.59ms p99=26.03ms  max=78.79ms
  ext4     3951 op/s   246.9 MB/s   p50=6.84ms  p95=19.64ms p99=28.93ms  max=137.37ms
```

`fsync=off` 의 p50 은 두 백엔드가 **완전히 같다**(0.02ms). 페이지 캐시가 차이를
전부 흡수하기 때문이다. 차이는 p95 에서 17배, p99 에서 2.7배로 벌어진다.
`fsync=on` 으로 캐시를 걷어내면 p50 이 137배 갈린다.

즉 **어느 지점을 보느냐에 따라 "두 백엔드가 같다"와 "137배 다르다"가 모두 나온다.**
백분위수를 따로 보지 않으면 스토리지 비교는 의미가 없다. 이것이 부하 생성기를
셸이나 단일 스레드 앱이 아니라 Go 로 쓴 이유다 — 워커별로 지연을 모아 정렬해
정확한 백분위수를 내려면 측정 경로에 잠금이 없어야 한다.

## 측정 방식과 그 한계

읽어야 할 것:

- **`write` 모드는 쓰기 + 삭제를 한 연산으로 잰다.** 저장소가 무한히 부풀지
  않게 하려고 쓴 파일을 바로 지운다. 삭제 비용이 측정값에 포함되므로 순수
  쓰기 지연보다 크게 나온다. 백엔드 간 *비교*에는 문제없지만 절대값을 다른
  도구(fio 등)와 비교하면 안 된다.
- **`fsync=off` 는 페이지 캐시 지연이다.** 스토리지까지 내려가는 지연을 보려면
  `--fsync` 를 켜야 한다.
- **백분위수는 근사가 아니라 정확값이다.** 샘플을 전부 보관해 정렬한다.
  랩 규모(수백만 이하)에서는 히스토그램을 쓸 이유가 없다.
- **취소는 실패로 세지 않는다.** 측정 구간이 끝나 중단된 연산을 에러율에
  넣으면 결과가 왜곡된다.
- **노드 부하는 동시에 건다.** 순차로 돌리면 공유 백엔드에 대한 경합이
  사라져 실제 운영 상황과 달라진다.
- 이 랩의 VM 은 같은 호스트 디스크를 공유한다. tmpfs 노드를 제외하면 백엔드
  간 차이에 호스트 IO 경합이 섞여 들어간다. **파일시스템 자체의 성능 순위를
  주장하는 데 쓸 수 없다** — 측정 방법론을 보는 랩이지 벤치마크 결과를
  생산하는 랩이 아니다.

## 구조

```
local-gostore-vagrant/
├── Vagrantfile                 인벤토리를 읽어 VM 구성 (값 하드코딩 없음)
├── inventory/inventory.ini     랩 구성의 단일 소스
├── app/                        Go 모듈 (외부 의존성 0)
│   ├── main.go                 agent / control / bench 역할 분기
│   └── internal/
│       ├── store/              마운트된 디렉터리 하나에 대한 파일 CRUD
│       ├── agent/              노드 에이전트 HTTP 서버
│       ├── control/            컨트롤러 (UI 서빙 + 노드 팬아웃)
│       ├── bench/              동시 부하 생성기와 지연 분포
│       ├── lab/                노드 목록 파싱 + 에이전트 클라이언트
│       └── web/                //go:embed 로 바이너리에 들어가는 UI
├── scripts/
│   ├── build.sh                정적 바이너리 크로스컴파일 (amd64/arm64)
│   ├── provision/              10_storage → 20_agent → 30_control → 40_verify
│   └── lifecycle/              bench.sh, status.sh, destroy.sh
└── dist/                       빌드 산출물 (git 제외)
```

## 의존성 정책

`app/go.mod` 에 외부 모듈이 없다. 이건 취향이 아니라 랩의 전제다 — 노드에
배포되는 산출물이 파일 하나여야 "런타임도 패키지 매니저도 없는 노드에 scp 한 번"이
성립한다. 의존성을 추가하기 전에 그 전제를 깨는지 먼저 확인할 것.

HTTP 서버·라우팅·JSON·embed·동시성이 전부 stdlib 로 해결된다. Go 1.22 부터
`net/http` 라우터가 `GET /v1/files/{name}` 형태의 메서드+경로 패턴을 지원해서
서드파티 라우터가 필요 없다.

## 설정

모든 값은 `inventory/inventory.ini` 에서 읽는다. Vagrantfile 과 스크립트는
값을 다시 하드코딩하지 않으며, 선언이 없거나 어긋나면 `vagrant up` 진입
시점에 즉시 실패한다.

| 항목 | 위치 | 비고 |
| --- | --- | --- |
| 노드 IP | `ansible_host` | `lab_network` 안에 있어야 함 |
| 저장소 경로 | `store_dir` | 기본 `/srv/gostore` |
| 백엔드 | `backend` | `xfs-*` / `ext4-*` / `tmpfs-*` |
| 데이터 디스크 | `data_disk` | GB 단위. tmpfs 는 0 이어야 함 |
| 공유 토큰 | `gostore_token` | **실습용 기본값이다. 랩 밖으로 나갈 구성이면 반드시 교체** |

## 보안 관련 참고

실습 환경 전제로 만들었지만 다음은 지켰다:

- 토큰은 systemd 유닛이 아니라 `0640 root:gostore` 환경 파일에 둔다.
  유닛 파일은 world-readable 이라 시크릿을 적으면 노드의 모든 사용자가 읽는다.
- 토큰 비교는 상수 시간(`crypto/subtle`)이다.
- 컨트롤러는 **등록된 노드 이름으로만** 중계한다. 주소를 받아 프록시하면
  그대로 SSRF 통로가 된다.
- 저장소 경로 탈출은 이름을 고쳐서 통과시키지 않고 **거부**한다.
  `filepath.Base` 로 뭉개면 사용자가 요청한 것과 다른 파일을 성공적으로
  다루게 된다.
- 에이전트는 `gostore` 전용 계정으로 돌고, systemd 에서 `ProtectSystem=strict`
  + `ReadWritePaths=<저장소>` 로 나머지를 잠근다.

`/health` 만 토큰 없이 열려 있다 — 배포 스크립트가 기동을 기다리는 데 필요하다.
저장소 내용이나 파일 목록은 노출하지 않는다.

## 테스트

```bash
cd app && go test ./...          # 단위 + E2E (에이전트 2대 + 컨트롤러를 실제로 띄운다)
cd app && go test -race ./...
```

`scripts/build.sh` 가 빌드 전에 `go vet` 과 테스트를 돌린다.
