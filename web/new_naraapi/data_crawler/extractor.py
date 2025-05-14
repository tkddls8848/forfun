# extractor.py
import json


class ApiInfoExtractor:
    """
    Swagger JSON 데이터에서 API 정보를 추출하는 클래스
    """
    
    def extract_summary_info(self, json_data):
        """
        API JSON 데이터에서 요약 정보(title, description, host)를 추출합니다.
        
        Args:
            json_data (dict): JSON 데이터
            
        Returns:
            list: 추출된 요약 정보 문자열 목록
        """
        # 추출할 정보 저장 리스트
        extracted_info = []
        
        # info > title 추출
        if 'info' in json_data and 'title' in json_data['info']:
            extracted_info.append(f"Title: {json_data['info']['title']}")
        
        # info > description 추출
        if 'info' in json_data and 'description' in json_data['info']:
            extracted_info.append(f"Description: {json_data['info']['description']}")
        
        # host 추출
        if 'host' in json_data:
            extracted_info.append(f"Host: {json_data['host']}")
        
        return extracted_info
    
    def extract_path_info(self, json_data):
        """
        API JSON 데이터에서 경로 정보를 추출합니다.
        
        Args:
            json_data (dict): JSON 데이터
            
        Returns:
            list: 추출된 경로 정보 문자열 목록
        """
        # 추출할 정보 저장 리스트
        extracted_info = []
        
        # paths에서 정보 추출
        if 'paths' in json_data:
            self._extract_paths_info(json_data['paths'], extracted_info)
        
        return extracted_info
    
    def _extract_paths_info(self, paths, extracted_info):
        """
        paths 객체에서 정보를 추출합니다.
        
        Args:
            paths (dict): paths 객체
            extracted_info (list): 추출된 정보를 저장할 리스트
        """
        # 각 경로 처리
        for path, path_data in paths.items():
            extracted_info.append(f"\nPath: {path}")
            
            # get > summary, description, operationId 추출
            if 'get' in path_data:
                self._extract_get_info(path_data['get'], extracted_info)
            
            # path 레벨의 parameters 추출
            if 'parameters' in path_data:
                self._extract_parameters(path_data['parameters'], extracted_info)
    
    def _extract_get_info(self, get_data, extracted_info):
        """
        get 객체에서 정보를 추출합니다.
        
        Args:
            get_data (dict): get 객체
            extracted_info (list): 추출된 정보를 저장할 리스트
        """
        # summary 추출
        if 'summary' in get_data:
            extracted_info.append(f"Summary: {get_data['summary']}")
        
        # description 추출
        if 'description' in get_data:
            extracted_info.append(f"Description: {get_data['description']}")
        
        # operationId 추출
        if 'operationId' in get_data:
            extracted_info.append(f"Operation ID: {get_data['operationId']}")
    
    def _extract_parameters(self, parameters, extracted_info):
        """
        parameters 배열에서 정보를 추출합니다.
        
        Args:
            parameters (list): parameters 배열
            extracted_info (list): 추출된 정보를 저장할 리스트
        """
        extracted_info.append("Parameters:")
        for param in parameters:
            # 파라미터 정보 형식화
            param_details = []
            for key, value in param.items():
                # 중첩된 객체나 리스트 처리
                if isinstance(value, (dict, list)):
                    value = json.dumps(value, ensure_ascii=False)
                param_details.append(f"{key}: {value}")
            extracted_info.append("  - " + ", ".join(param_details))