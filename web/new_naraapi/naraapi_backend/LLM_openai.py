# backend/LLM_openai.py
from openai import OpenAI
import os
from typing import Dict, List, Any  # 이 줄을 추가
from dotenv import load_dotenv

# 환경 변수 로드
load_dotenv()

# OpenAI API 클라이언트 초기화
openai_client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

async def search_openai(
    query: str,
    model: str = "gpt-3.5-turbo",
    temperature: float = 0.7,
    max_tokens: int = 500
) -> Dict[str, Any]:
    """OpenAI API를 사용한 검색"""
    print(f"OpenAI search called with query: {query}")
    
    # API 키 확인
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise Exception("OpenAI API key not found in environment variables")
    
    print(f"API key present: {bool(api_key)}")
    print(f"API key prefix: {api_key[:8]}..." if api_key else "No key")
    
    try:
        # OpenAI ChatGPT API 호출
        response = openai_client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "system",
                    "content": "당신은 도움이 되는 AI 어시스턴트입니다. 사용자의 질문에 정확하고 유용한 답변을 제공해주세요."
                },
                {
                    "role": "user",
                    "content": query
                }
            ],
            temperature=temperature,
            max_tokens=max_tokens
        )
        
        print(f"OpenAI API response received")
        
        # 응답 데이터 추출
        openai_response = response.choices[0].message.content
        
        return {
            "query": query,
            "results": [
                {
                    "type": "openai_response",
                    "content": openai_response,
                    "model": model,
                    "usage": {
                        "prompt_tokens": response.usage.prompt_tokens,
                        "completion_tokens": response.usage.completion_tokens,
                        "total_tokens": response.usage.total_tokens
                    }
                }
            ],
            "status": "success"
        }
        
    except Exception as e:
        print(f"OpenAI API error: {str(e)}")
        print(f"Error type: {type(e).__name__}")
        raise Exception(f"OpenAI API 호출 중 오류 발생: {str(e)}")