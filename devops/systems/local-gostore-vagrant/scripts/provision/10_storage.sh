#!/bin/bash
#
# 저장소 마운트 준비. 이 랩에서 OS 패키지를 건드리는 유일한 단계다.
#
#   $1 = 파일시스템 (xfs|ext4|tmpfs)
#   $2 = 마운트 경로
#
# xfs/ext4 는 두 번째 디스크(/dev/sdb)를 포맷해 마운트하고, tmpfs 는 램에
# 마운트한다. 어느 쪽이든 gostore 자체를 위해 설치하는 패키지는 없다 —
# 필요한 것은 파일시스템 도구뿐이고, 에이전트는 정적 바이너리라 런타임이 없다.
set -euo pipefail

FS="${1:?파일시스템 인자가 필요합니다 (xfs|ext4|tmpfs)}"
STORE_DIR="${2:?마운트 경로 인자가 필요합니다}"
DEVICE="/dev/sdb"

log() { echo "[step=storage][target=${FS}] $*"; }
fail() { echo "[step=storage][target=${FS}][failed] reason=$*" >&2; exit 1; }

mkdir -p "$STORE_DIR"

# 이미 마운트돼 있으면 재실행(vagrant provision)에서 아무것도 하지 않는다.
if mountpoint -q "$STORE_DIR"; then
  log "이미 마운트됨: $STORE_DIR ($(findmnt -no FSTYPE "$STORE_DIR"))"
  exit 0
fi

case "$FS" in
  tmpfs)
    log "tmpfs 마운트: $STORE_DIR (512M)"
    # fstab 에 남겨 재부팅 후에도 유지한다. tmpfs 내용은 사라지지만
    # 마운트 자체가 없으면 에이전트가 health 를 503 으로 보고한다.
    grep -q "[[:space:]]${STORE_DIR}[[:space:]]" /etc/fstab \
      || echo "tmpfs ${STORE_DIR} tmpfs rw,size=512M,mode=0755 0 0" >> /etc/fstab
    mount "$STORE_DIR"
    ;;
  xfs|ext4)
    [ -b "$DEVICE" ] || fail "데이터 디스크 $DEVICE 가 없습니다. 인벤토리의 data_disk 선언을 확인하세요."

    log "필수 도구 설치"
    export DEBIAN_FRONTEND=noninteractive
    if [ "$FS" = "xfs" ]; then
      apt-get update -qq && apt-get install -y -qq xfsprogs >/dev/null
    fi

    # 이미 포맷돼 있으면 다시 만들지 않는다. mkfs 를 무조건 돌리면
    # vagrant provision 재실행이 데이터를 날린다.
    CURRENT_FS="$(blkid -o value -s TYPE "$DEVICE" 2>/dev/null || true)"
    if [ -z "$CURRENT_FS" ]; then
      log "$DEVICE 를 $FS 로 포맷"
      mkfs."$FS" -q "$DEVICE"
    elif [ "$CURRENT_FS" != "$FS" ]; then
      fail "$DEVICE 가 이미 $CURRENT_FS 로 포맷돼 있습니다(기대: $FS). 수동으로 정리하세요."
    else
      log "$DEVICE 는 이미 $FS 입니다 — 포맷 생략"
    fi

    UUID="$(blkid -o value -s UUID "$DEVICE")"
    [ -n "$UUID" ] || fail "$DEVICE 의 UUID 를 읽을 수 없습니다"
    # 디바이스 이름(/dev/sdb)은 부팅마다 바뀔 수 있으므로 UUID 로 고정한다.
    grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $STORE_DIR $FS defaults,noatime 0 2" >> /etc/fstab
    mount "$STORE_DIR"
    ;;
  *)
    fail "지원하지 않는 파일시스템: $FS"
    ;;
esac

mountpoint -q "$STORE_DIR" || fail "$STORE_DIR 마운트에 실패했습니다"
chmod 0755 "$STORE_DIR"
log "완료: $(findmnt -no SOURCE,FSTYPE,SIZE "$STORE_DIR")"
