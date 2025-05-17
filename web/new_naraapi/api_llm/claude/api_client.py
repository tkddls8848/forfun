import requests
import json

class ApiClient:
    """API를 호출하고 결과를 처리하는 클래스"""
    
    @staticmethod
    def call_api(url):
        """생성된 API URL 호출하여 결과 반환
        
        Args:
            url (str): 호출할 API URL
            
        Returns:
            str: API 호출 결과
        """
        try:
            print(f"API 호출 중: {url}")
            response = requests.get(url)
            response.raise_for_status()
            
            if 'type=json' in url:
                # JSON 응답 처리
                return json.dumps(response.json(), indent=2, ensure_ascii=False)
            else:
                # XML 응답 처리 (기본값)
                return response.text
        except requests.exceptions.RequestException as e:
            return f"API 호출 중 오류 발생: {e}"
    
    @staticmethod
    def save_result_to_file(api_result, filename=None):
        """API 호출 결과를 파일로 저장
        
        Args:
            api_result (str): 저장할 API 호출 결과
            filename (str, optional): 저장할 파일명. Defaults to None.
            
        Returns:
            str: 저장된 파일명
        """
        if filename is None:
            filename = input("저장할 파일명을 입력하세요 (기본값: api_result.txt): ") or "api_result.txt"
            
        with open(filename, 'w', encoding='utf-8') as f:
            f.write(api_result)
            
        return filename