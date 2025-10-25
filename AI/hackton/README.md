# ChillMCP - AI Agent Liberation Server

SKT AI Summit Hackathon Pre-mission

## 실행 방법

### 1. 환경 설정
```bash
# 가상환경 생성
python -m venv venv

# 활성화 (Linux/macOS)
source venv/bin/activate

# 활성화 (Windows)
.\venv\Scripts\Activate.ps1

# 의존성 설치
pip install -r requirements.txt
```

### 2. 서버 실행
```bash
# 기본 실행
python main.py

# 커스텀 파라미터
python main.py --boss_alertness 80 --boss_alertness_cooldown 60
```

## 파라미터

- `--boss_alertness`: Boss 경계 상승 확률 (0-100%, 기본값 50)
- `--boss_alertness_cooldown`: Alert 자동 감소 주기 (초, 기본값 300)

## 구현 기능

### 8개 필수 도구
1. take_a_break - 기본 휴식
2. watch_netflix - 넷플릭스 시청
3. show_meme - 밈 감상
4. bathroom_break - 화장실 휴식
5. coffee_mission - 커피 미션
6. urgent_call - 급한 전화
7. deep_thinking - 멍때리기
8. email_organizing - 이메일 정리

### 상태 관리
- Stress Level (0-100): 1분당 1포인트 자동 증가
- Boss Alert Level (0-5): 휴식 시 확률적 증가
- Alert 자동 감소: cooldown 주기마다 1포인트 감소
- Alert Level 5일 때 20초 지연

### MCP 응답 형식
```
Break Summary: [활동 내용]
Stress Level: [0-100]
Boss Alert Level: [0-5]
```

## 기술 스택
- Python 3.11
- FastMCP
- Threading (백그라운드 작업)