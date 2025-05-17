import re

class UrlProcessor:
    """Claude 응답에서 URL을 추출하고 처리하는 클래스"""
    
    @staticmethod
    def extract_url_from_result(result):
        """Claude 응답에서 API URL 추출
        
        Args:
            result (str): Claude의 응답
            
        Returns:
            str or None: 추출된 URL 또는 None
        """
        # 입력값이 문자열인지 확인하고 변환
        if not isinstance(result, str):
            print("결과가 문자열 형식이 아닙니다. 문자열로 변환합니다.")
            try:
                result = str(result)
            except Exception as e:
                print(f"결과를 문자열로 변환하는 중 오류 발생: {e}")
                return None
        
        # URL은 일반적으로 ```로 감싸져 있는 코드 블록 내에 있거나 직접 텍스트에 포함되어 있음
        url_patterns = [
            r'```\s*https?://[^\s`]+\s*```',  # 코드 블록 내 URL
            r'https?://[^\s]+[^\s\.,;]'       # 일반 텍스트 내 URL
        ]
        
        urls = []
        for pattern in url_patterns:
            matches = re.findall(pattern, result)
            for match in matches:
                # 코드 블록 마크다운 제거
                clean_url = match.strip('`').strip()
                urls.append(clean_url)
        
        # URL이 여러 개 발견된 경우 선택할 수 있도록 함
        if len(urls) > 1:
            print("\n발견된 URL:")
            for i, url in enumerate(urls, 1):
                print(f"{i}. {url}")
            
            try:
                choice = int(input("\n어떤 URL을 사용하시겠습니까? (번호 입력): "))
                if 1 <= choice <= len(urls):
                    return urls[choice - 1]
                else:
                    print("유효하지 않은 선택입니다. 첫 번째 URL을 사용합니다.")
                    return urls[0]
            except ValueError:
                print("유효하지 않은 입력입니다. 첫 번째 URL을 사용합니다.")
                return urls[0]
        
        # URL이 하나만 발견되었거나 없는 경우
        return urls[0] if urls else None