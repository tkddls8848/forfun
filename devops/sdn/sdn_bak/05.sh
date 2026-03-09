kubectl apply -f vfirewall.yaml

# MetalLB 설치
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

# IP 풀 설정
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.0.200-172.18.0.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
EOF

kubectl apply -f app-with-vlb.yaml
kubectl get svc web-lb  # EXTERNAL-IP 확인

kubectl get all                         # 전체 리소스
kubectl get pods -o wide                # Pod 위치 확인
kubectl get svc                         # 서비스/LB IP 확인
kubectl get networkpolicy               # 방화벽 정책 확인
```

---

## 전체 실습 검증 체크리스트
```
1단계 ✅ sudo mn --version 정상 출력
         sudo mn pingall 100% 성공

2단계 ✅ ODL 웹 UI 접속 가능
         REST API 토폴로지 조회 성공

3단계 ✅ ovs-vsctl show 브리지 확인
         네임스페이스 간 ping 성공

4단계 ✅ kubectl get nodes → 전체 Ready
         Calico 파드 전체 Running

5단계 ✅ vFirewall Pod Running
         web-lb EXTERNAL-IP 할당됨
         curl로 LB 통신 확인

# Mininet 정리
sudo mn -c

# OVS 정리
sudo ovs-vsctl del-br br0
sudo ip netns del host1
sudo ip netns del host2

# kind 클러스터 삭제
kind delete cluster --name sdn-lab