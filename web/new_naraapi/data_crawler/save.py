import requests
import re
import json
import os
import sys
import time

def crawl_swagger_json(api_id):
    """
    data.go.kr 웹페이지에서 swaggerJson 변수를 추출합니다.
    
    Args:
        api_id (str): API ID 번호 (URL의 일부)
    
    Returns:
        dict: 추출된 swagger JSON 객체
    """
    # URL 구성
    url = f"https://www.data.go.kr/data/{api_id}/openapi.do"
    
    try:
        # 웹페이지 소스 코드 가져오기
        print(f"URL {url} 접속 중...")
        response = requests.get(url)
        response.raise_for_status()  # 오류 발생 시 예외 발생
        
        # 인코딩 설정
        response.encoding = 'utf-8'
        html_content = response.text
        
        # window.onload 함수 내에서 swaggerJson 변수 찾기
        # 백틱(`)으로 둘러싸인 JSON 문자열을 추출
        pattern = r'var\s+swaggerJson\s*=\s*`(.*?)`;'
        match = re.search(pattern, html_content, re.DOTALL)
        
        if match:
            # 백틱 안의 내용 추출
            json_str = match.group(1)
            
            # JSON 파싱
            swagger_json = json.loads(json_str)
            return swagger_json
        else:
            # 다른 형식으로 시도 (따옴표로 둘러싸인 경우)
            alternate_pattern = r'var\s+swaggerJson\s*=\s*({.*?});'
            match = re.search(alternate_pattern, html_content, re.DOTALL)
            
            if match:
                json_str = match.group(1)
                swagger_json = json.loads(json_str)
                return swagger_json
            
            raise Exception("웹페이지에서 swaggerJson 객체를 찾을 수 없습니다.")
    
    except requests.exceptions.RequestException as e:
        print(f"웹페이지 요청 오류: {e}")
        return None
    except json.JSONDecodeError as e:
        print(f"JSON 파싱 오류: {e}")
        print(f"JSON 문자열 일부: {json_str[:200]}...")  # 디버깅용 출력
        return None
    except Exception as e:
        print(f"오류 발생: {e}")
        return None

def extract_api_info(json_data, output_file_path):
    """
    API JSON 데이터에서 특정 정보를 추출하여 텍스트 파일로 저장합니다.
    
    Args:
        json_data (dict): JSON 데이터
        output_file_path (str): 결과를 저장할 텍스트 파일 경로
    """
    # 추출할 정보 저장 리스트
    extracted_info = []
    
    # info > title 추출
    if 'info' in json_data and 'title' in json_data['info']:
        extracted_info.append(f"Title: {json_data['info']['title']}")
    
    # host 추출
    if 'host' in json_data:
        extracted_info.append(f"Host: {json_data['host']}")
    
    # paths에서 정보 추출
    if 'paths' in json_data:
        paths = json_data['paths']
        
        # 각 경로 처리
        for path, path_data in paths.items():
            extracted_info.append(f"\nPath: {path}")
            
            # get > summary, description, operationId 추출
            if 'get' in path_data:
                get_data = path_data['get']
                
                # summary 추출
                if 'summary' in get_data:
                    extracted_info.append(f"Summary: {get_data['summary']}")
                
                # description 추출
                if 'description' in get_data:
                    extracted_info.append(f"Description: {get_data['description']}")
                
                # operationId 추출
                if 'operationId' in get_data:
                    extracted_info.append(f"Operation ID: {get_data['operationId']}")
            
            # path 레벨의 parameters 추출
            if 'parameters' in path_data:
                extracted_info.append("Parameters:")
                for param in path_data['parameters']:
                    # 파라미터 정보 형식화
                    param_details = []
                    for key, value in param.items():
                        # 중첩된 객체나 리스트 처리
                        if isinstance(value, (dict, list)):
                            value = json.dumps(value, ensure_ascii=False)
                        param_details.append(f"{key}: {value}")
                    extracted_info.append("  - " + ", ".join(param_details))
    
    # 추출한 정보를 텍스트 파일로 저장
    with open(output_file_path, 'w', encoding='utf-8') as file:
        file.write('\n'.join(extracted_info))
    
    print(f"추출 완료. 결과가 {output_file_path}에 저장되었습니다.")

def read_api_ids_from_file(file_path):
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

def process_api_id(api_id, output_dir="output"):
    """
    단일 API ID에 대한 처리를 수행합니다.
    
    Args:
        api_id (str): 처리할 API ID
        output_dir (str): 결과 파일을 저장할 디렉토리
    
    Returns:
        bool: 처리 성공 여부
    """
    print(f"\n===== API ID: {api_id} 처리 중 =====")
    
    # 출력 디렉토리 생성
    os.makedirs(output_dir, exist_ok=True)
    
    # 파일 경로 설정
    json_file_path = os.path.join(output_dir, f"swagger_{api_id}.json")
    output_file_path = os.path.join(output_dir, f"extracted_api_info_{api_id}.txt")
    
    # swagger JSON 추출
    swagger_json = crawl_swagger_json(api_id)
    
    if swagger_json:
        # JSON 파일로 저장
        with open(json_file_path, "w", encoding="utf-8") as f:
            json.dump(swagger_json, f, ensure_ascii=False, indent=2)
        print(f"{json_file_path} 파일로 원본 데이터가 저장되었습니다.")
        
        # 정보 추출 및 텍스트 파일로 저장
        extract_api_info(swagger_json, output_file_path)
        return True
    else:
        print(f"API ID {api_id}에 대한 swagger JSON 추출 실패.")
        return False

def main():
    # 명령줄 인수 처리
    if len(sys.argv) < 2:
        print("사용법: python script.py [API_ID 목록 파일 경로] [출력 디렉토리(선택)]")
        print("예: python script.py api_ids.txt output")
        return
    
    # API ID 목록 파일 경로
    api_ids_file = sys.argv[1]
    
    # 출력 디렉토리 (선택 인수)
    output_dir = "output"
    if len(sys.argv) > 2:
        output_dir = sys.argv[2]
    
    # 파일에서 API ID 목록 읽기
    api_ids = read_api_ids_from_file(api_ids_file)
    
    if not api_ids:
        print("처리할 API ID가 없습니다.")
        return
    
    # 결과 통계
    total = len(api_ids)
    success = 0
    failed = 0
    
    # 각 API ID에 대해 처리
    for i, api_id in enumerate(api_ids, 1):
        print(f"\n진행 상황: {i}/{total} ({i/total*100:.1f}%)")
        
        # API ID 처리
        if process_api_id(api_id, output_dir):
            success += 1
        else:
            failed += 1
        
        # 연속 요청으로 인한 서버 부하 방지를 위한 딜레이
        if i < total:  # 마지막 항목이 아니면 딜레이 추가
            print("다음 요청을 위해 잠시 대기 중...")
            time.sleep(1)  # 1초 대기
    
    # 결과 요약
    print("\n===== 처리 완료 =====")
    print(f"총 API ID 수: {total}")
    print(f"성공: {success}")
    print(f"실패: {failed}")
    print(f"출력 디렉토리: {os.path.abspath(output_dir)}")

if __name__ == "__main__":
    main()