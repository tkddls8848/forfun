// Package web 은 컨트롤러 UI 를 바이너리에 embed 한다.
//
// 정적 파일을 따로 배포하지 않는 것이 이 랩의 목적 중 하나다. 바이너리 하나를
// scp 하면 UI 까지 함께 간다 — 노드에 웹서버도, 정적 파일 디렉터리도 없다.
package web

import (
	"embed"
	"io/fs"
)

//go:embed assets
var assets embed.FS

// FS 는 UI 정적 자산 루트를 반환한다.
func FS() fs.FS {
	sub, err := fs.Sub(assets, "assets")
	if err != nil {
		// embed 는 컴파일 타임에 확정되므로 여기 도달하면 빌드가 잘못된 것이다.
		panic("embed 된 assets 디렉터리를 열 수 없습니다: " + err.Error())
	}
	return sub
}
