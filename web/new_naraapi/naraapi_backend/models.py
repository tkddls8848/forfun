# Pydantic 모델 (선택사항)
from pydantic import BaseModel
from typing import List, Dict, Any, Optional

class SearchResult(BaseModel):
    type: str
    content: str
    model: str
    usage: Optional[Dict[str, int]] = None

class SearchResponse(BaseModel):
    query: str
    results: List[Dict[str, Any]]
    status: str
    raw_response: Optional[str] = None

class StructuredResponse(BaseModel):
    summary: str
    details: str
    related_info: str
    follow_up_questions: List[str]  