# backend/main.py
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from LLM_claude import query_claude, query_claude_structured
from LLM_openai import query_openai
from models import QueryRequest  # models.py에서 import
import os
from dotenv import load_dotenv
from contextlib import asynccontextmanager

# 환경 변수 로드
load_dotenv()

# Lifespan 이벤트 핸들러
@asynccontextmanager
async def lifespan(app: FastAPI):
    # 시작 시 실행되는 코드
    print("FastAPI server starting...")
    print(f"OpenAI API Key present: {'OPENAI_API_KEY' in os.environ}")
    print(f"Anthropic API Key present: {'ANTHROPIC_API_KEY' in os.environ}")
    
    yield  # 애플리케이션 실행
    
    # 종료 시 실행되는 코드 (필요한 경우)
    print("FastAPI server shutting down...")

# FastAPI 앱 생성 시 lifespan 전달
app = FastAPI(lifespan=lifespan)

# CORS 설정 - 더 자세하게
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],  # 구체적인 origin
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
)

@app.get("/test")
async def hello():
    return {"message": "Hello from FastAPI Backend!"}

@app.post("/query")
async def query(request: QueryRequest):
    """통합 검색 엔드포인트 - POST 메소드"""
    print(f"=== Query Request ===")
    print(f"Query: {request.q}")
    print(f"Endpoint: {request.endpoint}")
    print(f"Model: {request.model}")
    print(f"Temperature: {request.temperature}")
    print(f"Max tokens: {request.max_tokens}")
    print(f"===================")
    
    # endpoint 값 확인
    valid_endpoints = ["query_claude", "query_openapi", "query_structured"]
    if request.endpoint not in valid_endpoints:
        print(f"Invalid endpoint: {request.endpoint}")
        raise HTTPException(
            status_code=400, 
            detail=f"Unknown endpoint: {request.endpoint}. Valid endpoints are: {valid_endpoints}"
        )
    
    try:
        if request.endpoint == "query_claude":
            print(f"Processing Claude query: {request.q}")
            result = await query_claude(request.q)
            print(f"Claude response received successfully")
            
        elif request.endpoint == "query_openapi":
            print(f"Processing OpenAI query: {request.q}")
            print(f"Model: {request.model}, Temperature: {request.temperature}, Max tokens: {request.max_tokens}")
            
            # OpenAI API 키 확인
            if not os.getenv("OPENAI_API_KEY"):
                raise HTTPException(status_code=500, detail="OpenAI API key not configured")
            
            result = await query_openai(request.q, request.model, request.temperature, request.max_tokens)
            print(f"OpenAI response received successfully")
            
        elif request.endpoint == "query_structured":
            print(f"Processing structured Claude query: {request.q}")
            result = await query_claude_structured(request.q)
            print(f"Structured Claude response received successfully")
        
        print(f"Result: {result}")
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in {request.endpoint}: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500, 
            detail=f"Internal server error in {request.endpoint}: {str(e)}"
        )

# 하위 호환성을 위한 GET 메소드 (선택사항)
@app.get("/query/legacy")
async def query_legacy(
    q: str,
    endpoint: str,
    model: str = "gpt-3.5-turbo",
    temperature: float = 0.7,
    max_tokens: int = 500
):
    """레거시 GET 엔드포인트 (하위 호환성)"""
    request = QueryRequest(
        q=q,
        endpoint=endpoint,
        model=model,
        temperature=temperature,
        max_tokens=max_tokens
    )
    return await query(request)

@app.post("/query/structured")
async def query_structured_endpoint(request: QueryRequest):
    """Claude API를 사용한 구조화된 검색 엔드포인트"""
    request.endpoint = "query_structured"
    return await query(request)

if __name__ == "__main__":
    import uvicorn
    print("Starting server on http://localhost:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")