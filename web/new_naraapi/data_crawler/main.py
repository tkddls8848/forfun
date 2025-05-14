# main.py
import os
import sys
import time
# 현재 디렉토리의 모듈 직접 임포트
from crawler import SwaggerCrawler
from extractor import ApiInfoExtractor
from file_handler import FileHandler


class ApiProcessor:
    """
    API 처리를 관리하는 클래스
    """
    
    def __init__(self, output_dir="output"):
        """
        ApiProcessor 클래스 초기화
        
        Args:
            output_dir (str): 출력 디렉토리
        """
        self.output_dir = output_dir
        self.crawler = SwaggerCrawler()
        self.extractor = ApiInfoExtractor()
        self.file_handler = FileHandler()
    
    def get_service_name_from_host(self, host):
        """
        호스트 문자열에서 서비스 이름을 추출합니다.
        
        Args:
            host (str): 호스트 문자열
            
        Returns:
            str: 서비스 이름 (기본값: 'service')
        """
        if not host:
            return 'service'
        
        # '/'로 분리하고 마지막 요소 반환
        parts = host.split('/')
        if len(parts) > 0 and parts[-1]:
            return parts[-1]
        elif len(parts) > 1:
            return parts[-2]  # 마지막이 빈 문자열인 경우 그 앞의 요소 반환
        else:
            return 'service'  # 기본값
    
    def process_api_id(self, api_id):
        """
        단일 API ID에 대한 처리를 수행합니다.
        
        Args:
            api_id (str): 처리할 API ID
        
        Returns:
            bool: 처리 성공 여부
        """
        print(f"\n===== API ID: {api_id} 처리 중 =====")
        
        # swagger JSON 크롤링
        swagger_json = self.crawler.crawl(api_id)
        
        if not swagger_json:
            print(f"API ID {api_id}에 대한 swagger JSON 추출 실패.")
            return False
        
        # 1. 요약 정보 추출 및 summary.txt에 저장
        summary_info = self.extractor.extract_summary_info(swagger_json)
        self.file_handler.append_to_summary_file(summary_info, self.output_dir, api_id)
        
        # 호스트 값 추출 (파일명 생성용)
        host = swagger_json.get('host', '')
        service_name = self.get_service_name_from_host(host)
        
        # 2. 경로 정보 추출 및 개별 파일로 저장
        path_info = self.extractor.extract_path_info(swagger_json)
        if path_info:
            output_file_path = os.path.join(self.output_dir, f"{service_name}.txt")
            self.file_handler.save_extracted_info(path_info, output_file_path)
        
        return True
    
    def process_api_ids(self, api_ids):
        """
        여러 API ID에 대한 처리를 수행합니다.
        
        Args:
            api_ids (list): 처리할 API ID 목록
            
        Returns:
            tuple: (성공 수, 실패 수)
        """
        total = len(api_ids)
        success = 0
        failed = 0
        
        # 각 API ID에 대해 처리
        for i, api_id in enumerate(api_ids, 1):
            print(f"\n진행 상황: {i}/{total} ({i/total*100:.1f}%)")
            
            # API ID 처리
            if self.process_api_id(api_id):
                success += 1
            else:
                failed += 1
            
            # 연속 요청으로 인한 서버 부하 방지를 위한 딜레이
            if i < total:  # 마지막 항목이 아니면 딜레이 추가
                print("다음 요청을 위해 잠시 대기 중...")
                time.sleep(1)  # 1초 대기
        
        return success, failed


def main():
    """
    메인 함수
    """
    # 명령줄 인수 처리
    if len(sys.argv) < 2:
        print("사용법: python main.py [API_ID 목록 파일 경로] [출력 디렉토리(선택)]")
        print("예: python main.py api_ids.txt output")
        return
    
    # API ID 목록 파일 경로
    api_ids_file = sys.argv[1]
    
    # 출력 디렉토리 (선택 인수)
    output_dir = "output"
    if len(sys.argv) > 2:
        output_dir = sys.argv[2]
    
    # 디렉토리 생성
    os.makedirs(output_dir, exist_ok=True)
    
    # summary.txt 파일이 있으면 초기화 (매번 새로 시작)
    summary_file_path = os.path.join(output_dir, "summary.txt")
    if os.path.exists(summary_file_path):
        with open(summary_file_path, 'w', encoding='utf-8') as f:
            f.write("")
    
    # 파일에서 API ID 목록 읽기
    file_handler = FileHandler()
    api_ids = file_handler.read_api_ids(api_ids_file)
    
    if not api_ids:
        print("처리할 API ID가 없습니다.")
        return
    
    # API 처리기 초기화
    processor = ApiProcessor(output_dir)
    
    # 모든 API ID 처리
    success, failed = processor.process_api_ids(api_ids)
    
    # 결과 요약
    print("\n===== 처리 완료 =====")
    print(f"총 API ID 수: {len(api_ids)}")
    print(f"성공: {success}")
    print(f"실패: {failed}")
    print(f"출력 디렉토리: {os.path.abspath(output_dir)}")
    print(f"요약 정보: {os.path.abspath(summary_file_path)}")


if __name__ == "__main__":
    main()