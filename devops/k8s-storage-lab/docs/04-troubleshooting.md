# 04. 트러블슈팅 & FAQ

---

## 인프라 (OpenTofu)

### `tofu apply` 시 Key Pair 오류
```
Error: InvalidKeyPair.NotFound
```

**원인**: `terraform.tfvars`의 `key_name`이 해당 리전에 존재하지 않음

**해결**:
```bash
# 현재 리전의 Key Pair 목록 확인
aws ec2 describe-key-pairs --region ap-northeast-2 --query 'KeyPairs[].KeyName'

# terraform.tfvars 수정
key_name = "실제-존재하는-키-이름"
```

### EC2 인스턴스 제한 초과
```
Error: InstanceLimitExceeded
```

**해결**: AWS 콘솔 → Service Quotas → EC2 → Running On-Demand Standard instances → 한도 증가 요청

### user_data 스크립트 실행 실패
```bash
# 해당 인스턴스에 SSH 접속 후 로그 확인
sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/cloud-init.log
```

---

## SSH 연결

### `00_hosts_setup.sh`에서 SSH 타임아웃

**원인**: 인스턴스 부팅 미완료 또는 Security Group 문제

**해결**:
```bash
# 인스턴스 상태 확인
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=k8s-storage-lab-*" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
  --output table

# SG에서 22번 포트가 0.0.0.0/0으로 열려있는지 확인
aws ec2 describe-security-groups \
  --group-ids <sg-id> \
  --query 'SecurityGroups[].IpPermissions'
```

### Permission denied (publickey)
```bash
# 올바른 키 파일인지 확인
ssh -i ~/.ssh/your-key.pem -v ubuntu@<ip>

# 키 파일 권한 확인 (600이어야 함)
chmod 600 ~/.ssh/your-key.pem
```

---

## Ceph

### `ceph status`에서 HEALTH_WARN

일반적인 WARN 메시지와 대응:

| 경고 | 원인 | 대응 |
|------|------|------|
| `too few PGs per OSD` | PG 수 부족 | `ceph osd pool set <pool> pg_num 64` |
| `no active mgr` | MGR 데몬 미시작 | `ceph orch apply mgr 3` → 대기 |
| `clock skew` | 노드 간 시간 차이 | 각 노드에서 `sudo chronyc makestep` |
| `OSD near full` | 디스크 용량 부족 | EBS 볼륨 크기 증가 후 `ceph osd reweight` |

### OSD가 생성되지 않음
```bash
# 사용 가능한 디바이스 확인
sudo ceph orch device ls

# 디바이스에 파티션/파일시스템이 있으면 OSD 생성 불가
# 강제 정리 후 재시도
sudo ceph orch device zap <host> /dev/xvdb --force
sudo ceph orch apply osd --all-available-devices
```

### CephFS MDS가 시작되지 않음
```bash
sudo ceph orch apply mds labfs --placement=3
sudo ceph fs status
```

---

## GPFS

### `mmbuildgpl` 실패

**원인**: 커널 헤더 버전 불일치
```bash
# 현재 커널과 헤더 버전 확인
uname -r
dpkg -l | grep linux-headers

# 일치하지 않으면 재설치
sudo apt-get install -y linux-headers-$(uname -r)
sudo /usr/lpp/mmfs/bin/mmbuildgpl
```

### `mmstartup` 후 노드가 active 되지 않음
```bash
# 상태 확인
sudo /usr/lpp/mmfs/bin/mmgetstate -a

# 로그 확인
sudo tail -100 /var/mmfs/gen/mmfslog

# SSH 연결 확인 (GPFS는 SSH로 노드 간 통신)
ssh nsd-1 hostname
ssh nsd-2 hostname
```

### NSD 디스크 인식 실패
```bash
# EBS 디바이스 확인
lsblk
ls -la /dev/xvd*

# Nitro 인스턴스에서는 /dev/nvme* 로 표시될 수 있음
ls -la /dev/nvme*
# 이 경우 NSDFile의 device 경로를 /dev/nvme1n1 등으로 변경
```

---

## Kubernetes

### kubeadm init 실패
```bash
# 로그 확인
sudo cat /tmp/kubeadm-init.log

# 흔한 원인: containerd 미실행
sudo systemctl status containerd
sudo systemctl restart containerd

# swap이 켜져있으면 실패
free -h   # Swap이 0이어야 함
sudo swapoff -a
```

### Node가 NotReady 상태
```bash
# Calico Pod 상태 확인
kubectl get pods -n calico-system

# kubelet 로그 확인
ssh ubuntu@<node-ip> "sudo journalctl -u kubelet --no-pager -n 50"
```

### Master join 실패 (token 만료)
```bash
# Master-1에서 새 token 생성
ssh ubuntu@<master-1-ip>
sudo kubeadm token create --print-join-command
sudo kubeadm init phase upload-certs --upload-certs
```

---

## CSI Driver

### Ceph CSI Pod가 CrashLoopBackOff
```bash
# Pod 로그 확인
kubectl logs -n ceph-csi-rbd <pod-name> -c csi-rbdplugin

# 흔한 원인: Ceph 키 또는 FSID 불일치
# 값 재확인
ssh ubuntu@<ceph-1-ip> "sudo ceph fsid"
ssh ubuntu@<ceph-1-ip> "sudo ceph auth get-key client.k8s"
```

### PVC가 Pending 상태에서 멈춤
```bash
# PVC 이벤트 확인
kubectl describe pvc <pvc-name>

# CSI provisioner 로그 확인
kubectl logs -n ceph-csi-rbd <provisioner-pod> -c csi-provisioner

# StorageClass 확인
kubectl get sc -o yaml
```

### GPFS CSI에서 REST API 접속 실패
```bash
# GUI 서비스 상태 확인
ssh ubuntu@<nsd-1-ip>
sudo /usr/lpp/mmfs/gui/bin/guiserver status

# 포트 확인
sudo netstat -tlnp | grep 443

# Secret 값 확인
kubectl get secret scale-secret -n ibm-spectrum-scale-csi-driver -o jsonpath='{.data.username}' | base64 -d
```

---

## 비용 관련

### 예상 월간 비용 (ap-northeast-2 기준, 2024년 참고가)

| 리소스 | 수량 | 단가(시간) | 월간(730h) |
|--------|------|-----------|-----------|
| t3.medium | 8대 | ~$0.052 | ~$303 |
| t3.large | 3대 | ~$0.104 | ~$228 |
| EBS gp3 20GB | 11개 | ~$1.60/월 | ~$18 |
| EBS gp2 10GB | 2개 | ~$1.00/월 | ~$2 |
| EBS gp2 20GB | 6개 | ~$2.00/월 | ~$12 |
| **합계** | | | **~$563/월** |

**비용 절감 팁**:
- 사용하지 않을 때 `./stop.sh snapshot`으로 EC2 중지 (EBS 비용만 발생)
- 실습 완료 후 `./stop.sh destroy`로 전체 삭제
- Spot Instance 사용 시 60~80% 절감 가능 (단, 중단 위험)

---

## FAQ

**Q: GPFS 없이 Ceph만 사용할 수 있나요?**

네. Step 0 → Step 1 → Step 4 → Step 5 → Step 7(ceph 테스트만) 순서로 실행하면 됩니다. NSD 노드 2대를 생략하려면 `modules/ec2/main.tf`에서 `aws_instance.nsd` 블록과 관련 EBS를 제거하세요.

**Q: K8s 버전을 변경하려면?**

`scripts/04_k8s_install.sh`의 `K8S_VERSION="1.29"` 값을 원하는 버전으로 변경합니다. Calico 버전도 호환성을 확인하세요.

**Q: 노드 수를 늘리거나 줄이려면?**

`modules/ec2/main.tf`의 각 `count` 값을 변경 후 `tofu apply`를 다시 실행합니다. 스크립트의 IP 수집 부분도 함께 수정해야 합니다.

**Q: 다른 리전에서 사용 가능한가요?**

`terraform.tfvars`에서 `aws_region`을 변경하면 됩니다. AMI는 `data.aws_ami`로 자동 조회되므로 별도 수정이 필요 없습니다.