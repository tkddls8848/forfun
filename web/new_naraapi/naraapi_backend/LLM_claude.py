# backend/LLM_claude.py
from anthropic import Anthropic
import os
from typing import Dict, List, Any
from dotenv import load_dotenv

# 환경 변수 로드
load_dotenv()

# Claude API 클라이언트 초기화
anthropic = Anthropic(api_key=os.getenv("ANTHROPIC_API_KEY"))

async def search_claude(query: str) -> Dict[str, Any]:
    """Claude API를 사용한 검색"""
    try:
        # Claude API 호출
        message = anthropic.messages.create(
            model="claude-3-7-sonnet-20250219",
            max_tokens=1000,
            temperature=0.7,
            system="당신은 도움이 되는 AI 어시스턴트입니다. 질문에 대해 정확하고 유용한 답변을 제공해주세요.",
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

async def search_claude_structured(query: str) -> Dict[str, Any]:
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