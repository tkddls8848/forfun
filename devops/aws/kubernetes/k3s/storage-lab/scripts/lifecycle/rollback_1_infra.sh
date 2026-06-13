#!/bin/bash
# Rollback Stage 1: AWS ?Έν”„???„μ²΄ ??  (tofu destroy) + lab.env ?? 
# ?„μ : rollback_3_beegfs.sh, rollback_2_ceph.sh ?¤ν–‰ ??(?ν”„?Έμ›¨??λ¨Όμ? ?•λ¦¬)
# ?¤ν–‰ ?μ„: rollback_3_beegfs.sh ??rollback_2_ceph.sh ??rollback_1_infra.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAB_ENV="$LAB_ROOT/lab.env"

echo "=============================="
echo " [1/1] AWS ?Έν”„????  (tofu destroy)"
echo "=============================="
echo "? οΈ  EC2 ?Έμ¤?΄μ¤, EBS λ³Όλ¥¨, VPC, Security Group ??λª¨λ‘ ?? ?©λ‹??"
echo ""

# λΉ„λ???λª¨λ“κ°€ ?„λ‹ ?λ§ ?•μΈ ?„λ΅¬?„νΈ ?μ‹
if [ -t 0 ]; then
  read -r -p "κ³„μ†?λ ¤λ©?'yes' λ¥??…λ ¥?μ„Έ?? " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "μ·¨μ†??"
    exit 0
  fi
fi

cd "$LAB_ROOT/opentofu"
tofu destroy -auto-approve

if [ -f "$LAB_ENV" ]; then
  rm -f "$LAB_ENV"
  echo "  lab.env ??  ?„λ£"
fi

echo ""
echo "??Stage 1 λ΅¤λ°± ?„λ£ ??λª¨λ“  AWS λ¦¬μ†???? ??
