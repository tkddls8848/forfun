# crawler.py
import requests
import re
import json


class SwaggerCrawler:
    """
    data.go.kr 웹페이지에서 Swagger JSON 데이터를 크롤링하는 클래스
    """
    
    def __init__(self, base_url="https://www.data.go.kr/data"):
        """
        SwaggerCrawler 클래스 초기화
        
        Args:
            base_url (str): 기본 URL
        """
        self.base_url = base_url
    
    def crawl(self, api_id):
        """
        주어진 API ID에 대한 Swagger JSON 데이터 크롤링
        
        Args:
            api_id (str): API ID 번호
            
        Returns:
            dict: 추출된 swagger JSON 객체, 실패 시 None
        """
        url = f"{self.base_url}/{api_id}/openapi.do"
        
        try:
            # 웹페이지 소스 코드 가져오기
            print(f"URL {url} 접속 중...")
            response = requests.get(url)
            response.raise_for_status()
            
            # 인코딩 설정
            response.encoding = 'utf-8'
            html_content = response.text
            
            # 백틱으로 둘러싸인 JSON 문자열 추출 시도
            swagger_json = self._extract_swagger_json(html_content)
            
            if swagger_json:
                return swagger_json
            else:
                raise Exception("웹페이지에서 swaggerJson 객체를 찾을 수 없습니다.")
        
        except requests.exceptions.RequestException as e:
            print(f"웹페이지 요청 오류: {e}")
            return None
        except json.JSONDecodeError as e:
            print(f"JSON 파싱 오류: {e}")
            return None
        except Exception as e:
            print(f"오류 발생: {e}")
            return None
    
    def _extract_swagger_json(self, html_content):
        """
        HTML 내용에서 Swagger JSON 데이터 추출
        
        Args:
            html_content (str): HTML 내용
            
        Returns:
            dict: 추출된 swagger JSON 객체, 실패 시 None
        """
        # 백틱(`)으로 둘러싸인 형식 시도
        pattern = r'var\s+swaggerJson\s*=\s*`(.*?)`;'
        match = re.search(pattern, html_content, re.DOTALL)
        
        if match:
            json_str = match.group(1)
            return json.loads(json_str)
        
        # 따옴표로 둘러싸인 형식 시도
        alternate_pattern = r'var\s+swaggerJson\s*=\s*({.*?});'
        match = re.search(alternate_pattern, html_content, re.DOTALL)
        
        if match:
            json_str = match.group(1)
            return json.loads(json_str)
        
        return None