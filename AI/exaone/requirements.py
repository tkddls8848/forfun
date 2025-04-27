# requirements: requests, numpy

import sys, subprocess, pkg_resources, re

def install_dependencies():
    # 현재 스크립트 파일 내용을 읽어서 'requirements:' 주석을 찾음
    with open(__file__, 'r', encoding='utf-8') as f:
        content = f.read()
    m = re.search(r'^# requirements:\s*(.+)$', content, re.MULTILINE)
    if m:
        # 쉼표로 구분된 패키지 리스트 추출
        requirements = [req.strip() for req in m.group(1).split(',')]
        # 현재 설치된 패키지 목록
        installed = {pkg.key for pkg in pkg_resources.working_set}
        for req in requirements:
            if req.lower() not in installed:
                print(f"Installing {req}...")
                subprocess.check_call([sys.executable, "-m", "pip", "install", req])

install_dependencies()
