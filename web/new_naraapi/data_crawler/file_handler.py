# file_handler.py
import os


class FileHandler:
    """
    파일 입출력을 처리하는 클래스
    """
    
    @staticmethod
    def read_api_ids(file_path):
        """
        텍스트 파일에서 API ID 목록을 읽습니다.
        
        Args:
            file_path (str): API ID 목록이 포함된 텍스트 파일 경로
            
        Returns:
            list: API ID 목록
        """
        api_ids = []
        
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                for line in file:
                    # 공백 제거 및 빈 줄 건너뛰기
                    api_id = line.strip()
                    if api_id:  # 빈 줄이 아니면 추가
                        api_ids.append(api_id)
            
            print(f"{file_path}에서 {len(api_ids)}개의 API ID를 읽었습니다.")
            return api_ids
        
        except Exception as e:
            print(f"파일 읽기 오류: {e}")
            return []
    
    @staticmethod
    def save_extracted_info(extracted_info, output_file_path):
        """
        추출된 정보를 텍스트 파일로 저장합니다.
        
        Args:
            extracted_info (list): 추출된 정보 문자열 목록
            output_file_path (str): 저장할 파일 경로
        """
        # 디렉토리가 없으면 생성
        os.makedirs(os.path.dirname(output_file_path) or '.', exist_ok=True)
        
        # 파일에 쓰기
        with open(output_file_path, 'w', encoding='utf-8') as file:
            file.write('\n'.join(extracted_info))
        
        print(f"추출 완료. 결과가 {output_file_path}에 저장되었습니다.")
