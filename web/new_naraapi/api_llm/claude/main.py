import os
from dotenv import load_dotenv
from app import App

def main():
    """프로그램 진입점"""
    # 환경 변수 로드
    load_dotenv()
    
    # API 키 가져오기
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        print("오류: ANTHROPIC_API_KEY 환경 변수가 설정되지 않았습니다.")
        print("API 키를 .env 파일에 설정하거나 환경 변수로 직접 설정해주세요.")
        return
    
    # 애플리케이션 인스턴스 생성
    app = App(api_key)
    
    # 초기화
    if app.initialize():
        # 애플리케이션 실행
        app.run()

if __name__ == "__main__":
    main()