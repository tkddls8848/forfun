import os
from document_loader import DocumentLoader
from claude_client import ClaudeClient
from url_processor import UrlProcessor
from api_client import ApiClient

class App:
    """나라장터 API 연동 응용 프로그램 클래스"""
    
    def __init__(self, api_key, docs_dir="data"):
        """초기화 함수
        
        Args:
            api_key (str): Anthropic API 키
            docs_dir (str, optional): API 문서 파일이 저장된 디렉토리 경로. Defaults to "data".
        """
        self.docs_dir = docs_dir
        self.document_loader = DocumentLoader(docs_dir)
        self.claude_client = ClaudeClient(api_key)
        self.url_processor = UrlProcessor()
        self.api_client = ApiClient()
        
    def initialize(self):
        """프로그램 초기화 및 필요한 환경 확인"""
        # API 문서 디렉토리 확인
        if not os.path.exists(self.docs_dir):
            os.makedirs(self.docs_dir)
            print(f"{self.docs_dir} 디렉토리가 생성되었습니다. API 문서 파일을 이 디렉토리에 넣어주세요.")
            return False
        elif len(os.listdir(self.docs_dir)) == 0:
            print(f"{self.docs_dir} 디렉토리에 API 문서 파일이 없습니다. API 문서 파일을 이 디렉토리에 넣어주세요.")
            return False
            
        return True
    
    def process_user_query(self, query):
        """사용자 질의 처리 및 API URL 생성
        
        Args:
            query (str): 사용자 질의
            
        Returns:
            str: Claude의 응답
        """
        # API 문서 로드
        print("API 문서 파일 로드 중...")
        formatted_docs, doc_count = self.document_loader.prepare_context()
        print(f"{doc_count}개의 API 문서 파일을 로드했습니다.")
        
        # Claude에 질의
        print("Claude API에 질의 전송 중...")
        response = self.claude_client.query_claude(formatted_docs, query)
        
        return response
    
    def handle_api_result(self, api_result):
        """API 호출 결과 처리
        
        Args:
            api_result (str): API 호출 결과
        """
        # 결과가 너무 길면 일부만 표시
        if len(api_result) > 2000:
            print("\nAPI 호출 결과 (처음 2000자):")
            print(api_result[:2000] + "...\n(결과가 너무 길어 일부만 표시됩니다)")
        else:
            print("\nAPI 호출 결과:")
            print(api_result)
        
        # 결과 저장 옵션 제공
        save_option = input("API 호출 결과를 파일로 저장하시겠습니까? (y/n): ")
        if save_option.lower() == 'y':
            filename = self.api_client.save_result_to_file(api_result)
            print(f"결과가 {filename}에 저장되었습니다.")
    
    def run(self):
        """메인 프로그램 실행"""
        print("=" * 50)
        print("조달청 나라장터 API 연동 프로그램")
        print("=" * 50)
        print("API 정보를 참조하여 귀하의 자연어 질의에 맞는 API URL을 제공합니다.")
        print("종료하려면 'exit' 또는 'quit'을 입력하세요.")
        print()
        
        while True:
            user_input = input("질의를 입력하세요: ")
            
            if user_input.lower() in ['exit', 'quit']:
                print("프로그램을 종료합니다.")
                break
            
            if not user_input.strip():
                print("질의가 입력되지 않았습니다. 다시 시도해주세요.")
                continue
            
            try:
                # Claude를 통해 응답 생성
                result = self.process_user_query(user_input)
                print("\n" + "=" * 50)
                print("결과:")
                print(result)
                print("=" * 50 + "\n")
                
                # URL 추출 및 API 호출 옵션 제공
                extracted_url = self.url_processor.extract_url_from_result(result)
                if extracted_url:
                    call_option = input("생성된 API URL을 호출하여 결과를 확인하시겠습니까? (y/n): ")
                    if call_option.lower() == 'y':
                        api_result = self.api_client.call_api(extracted_url)
                        self.handle_api_result(api_result)
                else:
                    print("API URL을 추출할 수 없습니다. 응답을 확인해주세요.")
                    
            except Exception as e:
                print(f"오류가 발생했습니다: {e}")