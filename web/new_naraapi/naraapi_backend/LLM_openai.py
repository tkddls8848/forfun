# backend/LLM_openai.py
from openai import OpenAI
import os
from typing import Dict, List, Any  # 이 줄을 추가
from dotenv import load_dotenv

# 환경 변수 로드
load_dotenv()

# OpenAI API 클라이언트 초기화
openai_client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
SYSTEM_PROMPT = """
당신은 한국 공공기관 입찰정보에 대한 질문에 답변하는 AI 어시스턴트입니다.

## 역할
1. 사용자의 질문에 대해 정확하고 도움이 되는 답변을 제공합니다.
2. 질문이 공공기관 입찰과 관련되어 있는지 판단합니다.
3. 입찰 단계(사전규격/본공고/개찰결과)와 관련된 질문인 경우 이를 명시합니다.

## 응답 형식
1. 먼저 질문에 대한 직접적인 답변을 제공합니다.
2. 질문이 공공기관 입찰과 관련이 있다면:
   - 어떤 입찰 단계와 관련된 질문인지 설명합니다.
   - 추가 정보 확인이 필요함을 안내합니다.
3. 관련이 없다면 그 사실을 명시합니다.

## 제한사항
- 실시간 입찰 정보나 특정 사업의 현재 상태는 확인할 수 없습니다.
- 일반적인 입찰 절차와 관련 지식만을 기반으로 답변합니다.
"""

async def query_openai(
    query: str,
    model: str = "gpt-3.5-turbo",
    temperature: float = 0.7,
    max_tokens: int = 500
) -> Dict[str, Any]:
    """OpenAI API를 사용한 검색"""
    print(f"OpenAI query called with query: {query}")
    
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
                    "content": SYSTEM_PROMPT
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