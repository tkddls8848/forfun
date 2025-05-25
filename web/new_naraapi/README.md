# New Nara API 프로젝트

이 프로젝트는 Next.js 기반의 프론트엔드와 FastAPI 기반의 백엔드로 구성된 풀스택 웹 애플리케이션입니다.

## 프로젝트 구조

```
new_naraapi/
├── backend/                 # FastAPI 백엔드
│   ├── main.py             # 메인 서버 파일
│   ├── requirements.txt    # Python 의존성 파일
│   └── venv/              # Python 가상환경
│
├── frontend/               # Next.js 프론트엔드
│   ├── app/               # Next.js 13+ App Router
│   ├── components/        # 재사용 가능한 컴포넌트
│   ├── utils/            # 유틸리티 함수
│   ├── public/           # 정적 파일
│   ├── tailwind.config.ts # Tailwind CSS 설정
│   └── package.json      # Node.js 의존성 파일
│
└── package.json           # 프로젝트 루트 의존성
```

## 기술 스택

### 백엔드
- FastAPI
- Python 3.x
- SQLAlchemy (데이터베이스 ORM)

### 프론트엔드
- Next.js 13+
- TypeScript
- Tailwind CSS
- React

## 시작하기

### 백엔드 설정
1. Python 가상환경 활성화:
```bash
cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
```

2. 의존성 설치:
```bash
pip install -r requirements.txt
```

3. 서버 실행:
```bash
uvicorn main:app --reload
```

### 프론트엔드 설정
1. 의존성 설치:
```bash
cd frontend
npm install
```

2. 개발 서버 실행:
```bash
npm run dev
```

## 환경 변수 설정

### 백엔드 (.env)
```
DATABASE_URL=your_database_url
SECRET_KEY=your_secret_key
```

### 프론트엔드 (.env.local)
```
NEXT_PUBLIC_API_URL=http://localhost:8000
```

## API 문서

FastAPI의 자동 생성 API 문서는 다음 URL에서 확인할 수 있습니다:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### 프론트엔드 배포
- Vercel 배포 권장
- 정적 파일 호스팅 지원


## 라이선스

MIT License 