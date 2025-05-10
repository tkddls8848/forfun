# backend/main.py
from fastapi import FastAPI, Query, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from LLM_claude import search_claude, search_claude_structured
from LLM_openai import search_openai
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

@app.get("/search")
async def search(
    q: str = Query(..., description="검색어"),
    endpoint: str = Query(..., description="API 엔드포인트"),
    model: str = Query("gpt-3.5-turbo", description="OpenAI 모델"),
    temperature: float = Query(0.7, description="응답의 창의성 (0-2)"),
    max_tokens: int = Query(500, description="최대 토큰 수")
):
    """통합 검색 엔드포인트"""
    print(f"=== Search Request ===")
    print(f"Query: {q}")
    print(f"Endpoint: {endpoint}")
    print(f"Model: {model}")
    print(f"Temperature: {temperature}")
    print(f"Max tokens: {max_tokens}")
    print(f"===================")
    
    # endpoint 값 확인
    valid_endpoints = ["search_claude", "search_openapi", "search_structured"]
    if endpoint not in valid_endpoints:
        print(f"Invalid endpoint: {endpoint}")
        raise HTTPException(
            status_code=400, 
            detail=f"Unknown endpoint: {endpoint}. Valid endpoints are: {valid_endpoints}"
        )
    
    try:
        if endpoint == "search_claude":
            print(f"Processing Claude query: {q}")
            result = await search_claude(q)
            print(f"Claude response received successfully")
            
        elif endpoint == "search_openapi":
            print(f"Processing OpenAI query: {q}")
            print(f"Model: {model}, Temperature: {temperature}, Max tokens: {max_tokens}")
            
            # OpenAI API 키 확인
            if not os.getenv("OPENAI_API_KEY"):
                raise HTTPException(status_code=500, detail="OpenAI API key not configured")
            
            result = await search_openai(q, model, temperature, max_tokens)
            print(f"OpenAI response received successfully")
            
        elif endpoint == "search_structured":
            print(f"Processing structured Claude query: {q}")
            result = await search_claude_structured(q)
            print(f"Structured Claude response received successfully")
        
        print(f"Result: {result}")
        return result
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in {endpoint}: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500, 
            detail=f"Internal server error in {endpoint}: {str(e)}"
        )

# 기존 개별 엔드포인트들은 하위 호환성을 위해 유지 (선택사항)
@app.get("/search_claude")
async def search_claude_endpoint(q: str = Query(..., description="검색어")):
    """Claude API를 사용한 검색 엔드포인트 (레거시)"""
    return await search(q=q, endpoint="search_claude")

@app.get("/search_openapi")
async def search_openapi_endpoint(
    q: str = Query(..., description="검색어"),
    model: str = Query("gpt-3.5-turbo", description="OpenAI 모델"),
    temperature: float = Query(0.7, description="응답의 창의성 (0-2)"),
    max_tokens: int = Query(500, description="최대 토큰 수")
):
    """OpenAI API를 사용한 검색 엔드포인트 (레거시)"""
    return await search(q=q, endpoint="search_openapi", model=model, temperature=temperature, max_tokens=max_tokens)

@app.get("/search/structured")
async def search_structured_endpoint(q: str = Query(..., description="검색어")):
    """Claude API를 사용한 구조화된 검색 엔드포인트 (레거시)"""
    return await search(q=q, endpoint="search_structured")

if __name__ == "__main__":
    import uvicorn
    print("Starting server on http://localhost:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")