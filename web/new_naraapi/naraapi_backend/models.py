# backend/models.py
from pydantic import BaseModel
from typing import List, Dict, Any, Optional

# POST 요청을 위한 입력 모델
class QueryRequest(BaseModel):
    q: str  # 검색어
    endpoint: str  # API 엔드포인트
    model: str = "gpt-3.5-turbo"  # OpenAI 모델 (기본값)
    temperature: float = 0.7  # 응답의 창의성 (기본값)
    max_tokens: int = 500  # 최대 토큰 수 (기본값)

class QueryResult(BaseModel):
    type: str
    content: str
    model: str
    usage: Optional[Dict[str, int]] = None

class QueryResponse(BaseModel):
    query: str
    results: List[Dict[str, Any]]
    status: str
    raw_response: Optional[str] = None

class StructuredResponse(BaseModel):
    summary: str
    details: str
    related_info: str
    follow_up_questions: List[str]