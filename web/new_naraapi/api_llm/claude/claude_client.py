import anthropic

class ClaudeClient:
    """Claude API와 상호작용하는 클래스"""
    
    def __init__(self, api_key):
        """초기화 함수
        
        Args:
            api_key (str): Anthropic API 키
        """
        self.client = anthropic.Anthropic(api_key=api_key)
        self.model = "claude-3-7-sonnet-20250219"
        
    def query_claude(self, context, user_query):
        """Claude에 컨텍스트와 사용자 질의를 전달하여 응답 받기
        
        Args:
            context (str): API 문서 컨텍스트
            user_query (str): 사용자 질의
            
        Returns:
            str: Claude의 응답
        """
        system_prompt = """
        당신은 조달청 나라장터 API 전문가입니다. 사용자의 자연어 요청을 기반으로 적절한 API URL을 생성해야 합니다.

        다음 가이드라인을 따르세요:
        1. 제공된 API 문서 컨텍스트를 참조하여 사용자 요청에 가장 적합한, 정확한 URL을 생성하세요.
        2. URL은 "Host + / + Path + ?(쿼리스트링) + 개별 파라미터 키=개별 파라미터값"의 형태를 가집니다.
        3. ServiceKey 값은 "cBcVBxPPJTldj0DnAFj7IwvbuORkuHWtGeyFZmghMw0rSi%2F3wVg0%2Bu1vWgQtUzSI%2BCXntWjTQqVxmB0HEY9pHA%3D%3D"를 사용하세요.
        4. 필수 파라미터(required=True)가 누락된 경우 이에 대해 설명하고 사용자에게 추가 정보를 요청하세요.
        5. 선택적 파라미터에 대해서도 설명하여 더 정확한 검색이 가능함을 알려주세요.
        6. 완성된 URL을 명확하게 표시하고, 각 파라미터의 의미와 용도를 간략히 설명하세요.
        7. 여러 API가 적용 가능한 경우 모든 옵션을 제시하세요.

        응답은 항상 다음 형식으로 제공하세요:
        1. 요청 이해: 사용자의 요청에 대한 이해를 간략히 요약
        2. 선택된 API: 적합한 API 서비스 및 경로 설명
        3. 완성된 URL: 생성된 전체 URL
        4. 파라미터 설명: 사용된 파라미터와 의미 설명
        5. 추가 옵션: 선택적 파라미터 또는 대체 API 제안 (해당하는 경우)
        """
        
        message = self.client.messages.create(
            model=self.model,
            system=system_prompt,
            max_tokens=2000,
            messages=[
                {"role": "user", "content": context + "\n\n" + user_query}
            ]
        )
        
        # 최신 Anthropic API는 content가 리스트일 수 있음
        if hasattr(message, 'content'):
            if isinstance(message.content, list):
                # 리스트 형태의 content에서 텍스트 추출
                text_contents = []
                for item in message.content:
                    if isinstance(item, dict) and 'text' in item:
                        text_contents.append(item['text'])
                    elif hasattr(item, 'text'):
                        text_contents.append(item.text)
                return ''.join(text_contents)
            else:
                # 문자열 형태의 content 그대로 반환
                return message.content
        else:
            # 기존 방식(message 자체가 텍스트일 경우)
            return str(message)