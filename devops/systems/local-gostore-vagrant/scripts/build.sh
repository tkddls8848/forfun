#!/bin/bash
#
# 호스트에서 정적 바이너리를 크로스컴파일한다.
#
# 이 랩의 핵심 성질이 여기서 만들어진다:
#   CGO_ENABLED=0  → libc 를 포함해 어떤 동적 링크도 없는 바이너리.
#                    노드의 배포판·glibc 버전과 무관하게 그대로 실행된다.
#   -trimpath      → 빌드 호스트의 절대 경로가 바이너리에 남지 않는다.
#   -s -w          → 심볼/DWARF 제거. 랩에서 디버거를 붙일 일이 없으므로 크기를 줄인다.
#
# 산출물은 dist/gostore-linux-<arch> 하나뿐이다. 웹 UI 는 //go:embed 로 이미
# 안에 들어 있으므로 같이 배포할 정적 파일이 없다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$LAB_ROOT/app"
DIST_DIR="$LAB_ROOT/dist"

# 대상 아키텍처. 노드가 arm64(Apple Silicon 의 Vagrant/UTM 등)일 수 있으므로 둘 다 만든다.
ARCHES="${ARCHES:-amd64 arm64}"

VERSION="${VERSION:-$(git -C "$LAB_ROOT" describe --tags --always --dirty 2>/dev/null || echo dev)}"

command -v go >/dev/null 2>&1 || {
  echo "[build][failed] reason=go 툴체인이 없습니다. https://go.dev/dl 에서 설치하세요." >&2
  exit 1
}

echo "[build][target=local] go vet + test"
cd "$APP_DIR"
go vet ./...
go test ./...

mkdir -p "$DIST_DIR"
for arch in $ARCHES; do
  out="$DIST_DIR/gostore-linux-$arch"
  echo "[build][target=linux/$arch] 컴파일"
  CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
    go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o "$out" .
done

echo
echo "산출물 (version=$VERSION):"
ls -lh "$DIST_DIR" | tail -n +2 | awk '{printf "  %-28s %s\n", $9, $5}'
echo
# 동적 링크가 하나라도 남으면 "노드에 아무것도 설치하지 않는다"는 전제가 깨진다.
# file(1) 이 없는 환경도 있으므로 없으면 조용히 넘어간다.
if command -v file >/dev/null 2>&1; then
  echo "링크 확인:"
  for arch in $ARCHES; do
    printf "  %s\n" "$(file -b "$DIST_DIR/gostore-linux-$arch")"
  done
fi
