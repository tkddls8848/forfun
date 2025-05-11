# backend/LLM_claude.py
from anthropic import Anthropic
import os
from typing import Dict, List, Any
from dotenv import load_dotenv

# 환경 변수 로드
load_dotenv()

# Claude API 클라이언트 초기화
anthropic = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))
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

async def query_claude(query: str) -> Dict[str, Any]:
    """Claude API를 사용한 검색"""
    try:
        # Claude API 호출
        message = anthropic.messages.create(
            model="claude-3-7-sonnet-20250219",
            max_tokens=1000,
            temperature=0.7,
            system=SYSTEM_PROMPT,
            messages=[
                {
                    "role": "user",
                    "content": f"다음 질문에 대해 답변해주세요: {query}"
                }
            ]
        )
        
        # Claude의 응답 파싱
        claude_response = message.content[0].text
        
        # 결과 반환
        return {
            "query": query,
            "results": [
                {
                    "type": "claude_response",
                    "content": claude_response,
                    "model": "claude-3-7-sonnet-20250219"
                }
            ],
            "status": "success"
        }
        
    except Exception as e:
        raise Exception(f"Claude API 호출 중 오류 발생: {str(e)}")

async def query_claude_structured(query: str) -> Dict[str, Any]:
    """Claude API를 사용한 구조화된 검색"""
    try:
        # Claude에게 구조화된 응답 요청
        message = anthropic.messages.create(
            model="claude-3-7-sonnet-20250219",
            max_tokens=1000,
            temperature=0.7,
            system="""당신은 도움이 되는 AI 어시스턴트입니다. 
            사용자의 질문에 대해 다음과 같은 구조로 답변해주세요:
            1. 간단한 요약
            2. 상세한 설명
            3. 관련 정보 (있다면)
            4. 추가 질문 제안 (있다면)""",
            messages=[
                {
                    "role": "user",
                    "content": f"다음 질문에 대해 구조화된 답변을 제공해주세요: {query}"
                }
            ]
        )
        
        claude_response = message.content[0].text
        
        # 응답을 파싱하여 구조화
        lines = claude_response.split('\n')
        structured_response = {
            "summary": "",
            "details": "",
            "related_info": "",
            "follow_up_questions": []
        }
        
        # 응답 파싱 로직
        current_section = ""
        for line in lines:
            if "1." in line or "요약" in line:
                current_section = "summary"
            elif "2." in line or "상세" in line:
                current_section = "details"
            elif "3." in line or "관련" in line:
                current_section = "related_info"
            elif "4." in line or "추가" in line:
                current_section = "follow_up_questions"
            else:
                if current_section == "summary":
                    structured_response["summary"] += line + " "
                elif current_section == "details":
                    structured_response["details"] += line + " "
                elif current_section == "related_info":
                    structured_response["related_info"] += line + " "
                elif current_section == "follow_up_questions":
                    if line.strip():
                        structured_response["follow_up_questions"].append(line.strip())
        
        return {
            "query": query,
            "results": [structured_response],
            "status": "success",
            "raw_response": claude_response
        }
        
    except Exception as e:
        raise Exception(f"Claude API 호출 중 오류 발생: {str(e)}")