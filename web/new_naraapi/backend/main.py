from fastapi import FastAPI

# FastAPI 앱 인스턴스 생성
app = FastAPI(title="My FastAPI Server", version="1.0.0")

# 루트 엔드포인트
@app.get("/")
async def root():
    return {"message": "Hello World"}

# 헬스체크 엔드포인트
@app.get("/health")
async def health_check():
    return {"status": "healthy"}

# 경로 매개변수를 사용하는 엔드포인트
@app.get("/query/{query_id}")
async def read_query(query_id: int):
    return {"query_id": query_id}

# 쿼리 매개변수를 사용하는 엔드포인트
@app.get("/query/")
async def read_querys(skip: int = 0, limit: int = 10):
    return {"skip": skip, "limit": limit}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)