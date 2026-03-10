#!/bin/bash
# =============================================================
# 02_odl.sh
# 역할: OpenDaylight(Magnesium) 설치 + Mininet 원격 컨트롤러 연동
# 실행 위치: vm-controller (ssh sdn@192.168.100.10)
# 실행: sudo bash 02_odl.sh
# =============================================================
set -euo pipefail

ODL_VER="0.18.1"
ODL_DIR="/opt/opendaylight"
ODL_URL="https://nexus.opendaylight.org/content/repositories/opendaylight.release/org/opendaylight/integration/karaf/${ODL_VER}/karaf-${ODL_VER}.tar.gz"
JAVA_MIN=11

### ── 1. Java 설치 ───────────────────────────────────────────
echo "[1/4] Java ${JAVA_MIN}+ 설치 확인..."
if java -version 2>&1 | grep -q 'version "1[1-9]\|version "[2-9][0-9]'; then
  echo "    ↳ Java 이미 설치됨: $(java -version 2>&1 | head -1)"
else
  sudo apt update -qq
  sudo apt install -y default-jdk
fi
java -version
echo "✅  Java 준비 완료"

### ── 2. ODL 다운로드 + 압축 해제 ──────────────────────────
echo "[2/4] OpenDaylight ${ODL_VER} 다운로드 중..."
sudo mkdir -p "${ODL_DIR}"
TARBALL="/tmp/karaf-${ODL_VER}.tar.gz"

if [[ ! -f "${TARBALL}" ]]; then
  wget -q --show-progress -O "${TARBALL}" "${ODL_URL}"
fi

sudo tar -xzf "${TARBALL}" -C "${ODL_DIR}" --strip-components=1
sudo chown -R "$USER":"$USER" "${ODL_DIR}"
echo "✅  ODL 압축 해제 완료: ${ODL_DIR}"

### ── 3. systemd 서비스 등록 ────────────────────────────────
echo "[3/4] ODL systemd 서비스 등록 중..."
sudo tee /etc/systemd/system/opendaylight.service > /dev/null <<EOF
[Unit]
Description=OpenDaylight SDN Controller
After=network.target

[Service]
Type=forking
User=${USER}
ExecStart=${ODL_DIR}/bin/start
ExecStop=${ODL_DIR}/bin/stop
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable opendaylight

### ── 4. ODL 기능 설치 스크립트 ─────────────────────────────
echo "[4/4] ODL Feature 자동 설치 스크립트 생성 중..."
mkdir -p ~/sdn-lab/odl

cat > ~/sdn-lab/odl/install_features.sh <<'SHEOF'
#!/bin/bash
# ODL Karaf 콘솔에 자동으로 feature 설치
# ODL 기동 후 실행: bash ~/sdn-lab/odl/install_features.sh

ODL_DIR="/opt/opendaylight"
KARAF_CLIENT="${ODL_DIR}/bin/client"

wait_odl() {
  echo "ODL 기동 대기 중..."
  for i in $(seq 1 60); do
    if "${KARAF_CLIENT}" -u karaf "feature:list" &>/dev/null 2>&1; then
      echo "✅  ODL 응답 확인"
      return 0
    fi
    printf "  대기 중... %d/60\r" "$i"
    sleep 5
  done
  echo "❌  ODL 응답 없음. 수동 확인 필요"
  exit 1
}

install_feature() {
  echo "  Feature 설치: $1"
  "${KARAF_CLIENT}" -u karaf "feature:install $1"
  sleep 3
}

wait_odl

echo "ODL Feature 설치 시작..."
install_feature "odl-restconf"
install_feature "odl-l2switch-switch"
install_feature "odl-l2switch-switch-ui"
install_feature "odl-mdsal-apidocs"
install_feature "odl-dluxapps-applications"
install_feature "odl-openflowplugin-flow-services-ui"

echo ""
echo "========================================"
echo "✅  ODL Feature 설치 완료!"
echo ""
echo "  웹 UI:  http://$(hostname -I | awk '{print $1}'):8181/index.html"
echo "          ID: admin / PW: admin"
echo ""
echo "  REST API 토폴로지 조회:"
echo "    curl -u admin:admin http://localhost:8181/restconf/operational/network-topology:network-topology/"
echo ""
echo "  Mininet 연동 (vm-worker1에서 실행):"
echo "    sudo python3 ~/sdn-lab/mininet/topo_custom.py remote"
echo "    또는"
echo "    sudo mn --topo tree,2 --controller remote,ip=192.168.100.10,port=6633 --switch ovs,protocols=OpenFlow13"
echo "========================================"
SHEOF
chmod +x ~/sdn-lab/odl/install_features.sh

### ── 시작 안내 ──────────────────────────────────────────────
echo ""
echo "========================================"
echo "✅  ODL 설치 완료!"
echo ""
echo "  [1] ODL 시작:"
echo "      sudo systemctl start opendaylight"
echo "      또는 직접 실행: ${ODL_DIR}/bin/karaf"
echo ""
echo "  [2] Feature 설치 (ODL 기동 후):"
echo "      bash ~/sdn-lab/odl/install_features.sh"
echo ""
echo "  [3] 상태 확인:"
echo "      sudo systemctl status opendaylight"
echo "      tail -f ${ODL_DIR}/data/log/karaf.log"
echo "========================================"