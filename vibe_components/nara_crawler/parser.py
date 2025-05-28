import json
import re
from selenium.webdriver.common.by import By
from xml.etree.ElementTree import Element, SubElement, tostring
from xml.dom import minidom
import os
from datetime import datetime
import requests

class NaraParser:
    """나라장터 API 파서 클래스"""
    
    def __init__(self, driver):
        self.driver = driver
    
    def extract_swagger_json(self):
        """Swagger JSON 추출"""
        try:
            # 1. JavaScript 변수에서 직접 추출 시도
            swagger_json = self.driver.execute_script("""
                if (typeof swaggerJson !== 'undefined') {
                    return swaggerJson;
                }
                return null;
            """)
            
            if swagger_json:
                return swagger_json
            
            # 2. script 태그에서 swaggerJson 변수 추출 시도
            scripts = self.driver.find_elements(By.TAG_NAME, "script")
            for script in scripts:
                script_content = script.get_attribute("innerHTML")
                if script_content:
                    # swaggerJson 변수에서 추출 (여러 패턴 시도)
                    patterns = [
                        r'var\s+swaggerJson\s*=\s*(\{.*?\});',  # 기본 패턴
                        r'swaggerJson\s*=\s*(\{.*?\});',        # var 없는 패턴
                        r'swaggerJson\s*:\s*(\{.*?\})',         # 객체 속성 패턴
                        r'swaggerJson\s*=\s*`(\{.*?\})`'        # 템플릿 리터럴 패턴
                    ]
                    
                    for pattern in patterns:
                        json_match = re.search(pattern, script_content, re.DOTALL)
                        if json_match:
                            try:
                                json_str = json_match.group(1)
                                # JSON 문자열 정리
                                json_str = json_str.replace('\n', '').replace('\r', '')
                                return json.loads(json_str)
                            except:
                                continue
            
            # 3. window.swaggerUi 변수에서 추출 시도
            swagger_json = self.driver.execute_script("""
                if (window.swaggerUi) {
                    return window.swaggerUi.spec;
                }
                return null;
            """)
            
            if swagger_json:
                return swagger_json
            
            # 4. script 태그에서 Swagger UI 초기화 코드 추출 시도
            for script in scripts:
                script_content = script.get_attribute("innerHTML")
                if script_content:
                    # Swagger UI 초기화 코드에서 추출
                    swagger_match = re.search(r'swaggerUi\s*=\s*new\s+SwaggerUIBundle\s*\(\s*{\s*url\s*:\s*[\'"]([^\'"]+)[\'"]', script_content)
                    if swagger_match:
                        swagger_url = swagger_match.group(1)
                        if swagger_url.startswith('/'):
                            current_url = self.driver.current_url
                            base_url = '/'.join(current_url.split('/')[:3])
                            swagger_url = base_url + swagger_url
                        
                        response = requests.get(swagger_url)
                        if response.status_code == 200:
                            return response.json()
                    
                    # 직접 JSON 객체 찾기
                    json_match = re.search(r'window\.swaggerUi\s*=\s*new\s+SwaggerUIBundle\s*\(\s*{\s*spec\s*:\s*(\{.*?\})\s*[,}]', script_content, re.DOTALL)
                    if json_match:
                        try:
                            return json.loads(json_match.group(1))
                        except:
                            pass
            
            # 5. XHR 요청에서 추출 시도
            logs = self.driver.get_log('performance')
            for log in logs:
                if 'Network.responseReceived' in str(log):
                    try:
                        message = json.loads(log['message'])
                        request_id = message['params']['requestId']
                        response = self.driver.execute_cdp_cmd('Network.getResponseBody', {'requestId': request_id})
                        if 'application/json' in response.get('headers', {}).get('content-type', ''):
                            try:
                                data = json.loads(response['body'])
                                if 'swagger' in data or 'openapi' in data:
                                    return data
                            except:
                                pass
                    except:
                        continue
            
            # 6. API 문서 페이지에서 직접 추출 시도
            try:
                api_info = {}
                info_table = self.driver.find_element(By.CSS_SELECTOR, "table.table-striped")
                if info_table:
                    rows = info_table.find_elements(By.TAG_NAME, "tr")
                    for row in rows:
                        cols = row.find_elements(By.TAG_NAME, "td")
                        if len(cols) >= 2:
                            key = cols[0].text.strip().lower()
                            value = cols[1].text.strip()
                            if key and value:
                                api_info[key] = value
                
                swagger_json = {
                    "swagger": "2.0",
                    "info": {
                        "title": api_info.get('제공기관', '') + '_' + api_info.get('서비스명', ''),
                        "description": api_info.get('서비스설명', ''),
                        "version": "1.0"
                    },
                    "host": "www.data.go.kr",
                    "basePath": "/data",
                    "schemes": ["https"],
                    "paths": {}
                }
                
                return swagger_json
                
            except Exception as e:
                print(f"API 문서 페이지에서 정보 추출 실패: {str(e)}")
            
            return None
            
        except Exception as e:
            print(f"Swagger JSON 추출 실패: {str(e)}")
            return None
    
    def extract_api_info(self, swagger_json):
        """API 기본 정보 추출"""
        api_info = {}
        
        if not swagger_json:
            return api_info
            
        # 기본 정보 추출
        info = swagger_json.get('info', {})
        api_info['title'] = info.get('title', '')
        api_info['description'] = info.get('description', '')
        api_info['version'] = info.get('version', '')
        
        # 확장 정보 추출
        if 'x-' in info:
            for key, value in info.items():
                if key.startswith('x-'):
                    api_info[key.replace('x-', '')] = value
        
        return api_info
    
    def extract_base_url(self, swagger_json):
        """Base URL 추출"""
        if not swagger_json:
            return ""
            
        schemes = swagger_json.get('schemes', ['https'])
        host = swagger_json.get('host', '')
        base_path = swagger_json.get('basePath', '')
        
        if host:
            scheme = schemes[0] if schemes else 'https'
            return f"{scheme}://{host}{base_path}"
        return ""
    
    def extract_endpoints(self, swagger_json):
        """엔드포인트 정보 추출"""
        endpoints = []
        
        if not swagger_json:
            return endpoints
            
        paths = swagger_json.get('paths', {})
        
        for path, methods in paths.items():
            for method, data in methods.items():
                if method in ['get', 'post', 'put', 'delete', 'patch']:
                    endpoint = {
                        'method': method.upper(),
                        'path': path,
                        'description': data.get('summary', '') or data.get('description', ''),
                        'parameters': self._extract_parameters(data.get('parameters', [])),
                        'responses': self._extract_responses(data.get('responses', {})),
                        'tags': data.get('tags', []),
                        'section': data.get('tags', ['Default'])[0] if data.get('tags') else 'Default'
                    }
                    endpoints.append(endpoint)
        
        return endpoints
    
    def _extract_parameters(self, params_list):
        """파라미터 정보 추출"""
        parameters = []
        
        for param in params_list:
            parameters.append({
                'name': param.get('name', ''),
                'description': param.get('description', ''),
                'required': param.get('required', False),
                'type': param.get('type', '') or (param.get('schema', {}).get('type', '') if 'schema' in param else '')
            })
        
        return parameters
    
    def _extract_responses(self, responses_dict):
        """응답 정보 추출"""
        responses = []
        
        for status_code, data in responses_dict.items():
            responses.append({
                'status_code': status_code,
                'description': data.get('description', '')
            })
        
        return responses

    def extract_table_info(self):
        """테이블 정보 추출"""
        try:
            table_info = {}
            print("🔍 테이블 검색 중...")
            
            # 모든 테이블 찾기
            tables = self.driver.find_elements(By.CSS_SELECTOR, "table.dataset-table")
            print(f"📊 발견된 테이블 수: {len(tables)}")
            
            for idx, table in enumerate(tables, 1):
                print(f"📋 테이블 {idx} 처리 중...")
                
                # 테이블 내용 추출
                rows = table.find_elements(By.TAG_NAME, "tr")
                
                for row in rows:
                    try:
                        # th와 td 태그 찾기
                        th = row.find_element(By.TAG_NAME, "th")
                        td = row.find_element(By.TAG_NAME, "td")
                        
                        key = th.text.strip()
                        value = td.text.strip()
                        
                        # 전화번호의 경우 JavaScript로 처리된 값을 가져오기
                        if "전화번호" in key:
                            try:
                                tel_no_div = td.find_element(By.ID, "telNoDiv")
                                value = tel_no_div.text.strip()
                            except:
                                pass
                        
                        # 링크가 있는 경우 링크 텍스트만 추출
                        if not value:
                            try:
                                link = td.find_element(By.TAG_NAME, "a")
                                value = link.text.strip()
                            except:
                                pass
                        
                        if key and value:
                            table_info[key] = value
                            print(f"  - {key}: {value}")
                    except Exception as e:
                        print(f"  ⚠️ 행 처리 중 오류: {str(e)}")
                        continue
            
            print(f"📊 총 {len(table_info)}개의 항목 추출 완료")
            return table_info
            
        except Exception as e:
            print(f"❌ 테이블 정보 추출 실패: {str(e)}")
            return {}

class DataExporter:
    """데이터 내보내기 클래스"""
    
    @staticmethod
    def save_as_json(data, file_path):
        """JSON 형태로 저장"""
        try:
            # 디렉토리가 없으면 생성
            dir_path = os.path.dirname(file_path)
            if dir_path:
                os.makedirs(dir_path, exist_ok=True)
            
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            return True, None
        except Exception as e:
            return False, f"JSON 저장 실패: {str(e)}"
    
    @staticmethod
    def dict_to_xml(data, root_name="api_documentation"):
        """딕셔너리를 XML로 변환"""
        try:
            def _dict_to_xml_element(d, parent, name=None):
                if name is None:
                    element = parent
                else:
                    # XML 태그명에서 특수문자 제거 및 유효성 검사
                    clean_name = re.sub(r'[^a-zA-Z0-9_-]', '_', str(name))
                    # 숫자로 시작하는 태그명 처리
                    if clean_name and clean_name[0].isdigit():
                        clean_name = f"item_{clean_name}"
                    # 빈 태그명 처리
                    if not clean_name:
                        clean_name = "unnamed_item"
                    
                    element = SubElement(parent, clean_name)
                
                if isinstance(d, dict):
                    for key, value in d.items():
                        _dict_to_xml_element(value, element, key)
                elif isinstance(d, list):
                    for i, item in enumerate(d):
                        if isinstance(item, dict):
                            _dict_to_xml_element(item, element, f"item_{i}")
                        else:
                            item_elem = SubElement(element, f"item_{i}")
                            item_elem.text = str(item) if item is not None else ""
                else:
                    element.text = str(d) if d is not None else ""
            
            root = Element(root_name)
            _dict_to_xml_element(data, root)
            return root, None
        except Exception as e:
            return None, f"XML 변환 실패: {str(e)}"
    
    @staticmethod
    def save_as_xml(data, file_path):
        """XML 형태로 저장"""
        try:
            # 디렉토리가 없으면 생성
            dir_path = os.path.dirname(file_path)
            if dir_path:
                os.makedirs(dir_path, exist_ok=True)
            
            # 딕셔너리를 XML로 변환
            root, error = DataExporter.dict_to_xml(data)
            if error:
                return False, error
            
            # 예쁘게 포맷팅
            rough_string = tostring(root, encoding='utf-8')
            reparsed = minidom.parseString(rough_string)
            pretty_xml = reparsed.toprettyxml(indent='  ', encoding='utf-8')
            
            with open(file_path, 'wb') as f:
                f.write(pretty_xml)
            
            return True, None
        except Exception as e:
            return False, f"XML 저장 실패: {str(e)}"
    
    @staticmethod
    def save_as_markdown(data, file_path):
        """Markdown 형태로 저장"""
        try:
            # 디렉토리가 없으면 생성
            dir_path = os.path.dirname(file_path)
            if dir_path:
                os.makedirs(dir_path, exist_ok=True)
            
            md_content = DataExporter.dict_to_markdown(data)
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(md_content)
            
            return True, None
        except Exception as e:
            return False, f"Markdown 저장 실패: {str(e)}"
    
    @staticmethod
    def dict_to_markdown(data):
        """딕셔너리를 Markdown 형식으로 변환"""
        try:
            md_lines = []
            api_info = data.get('api_info', {})
            endpoints = data.get('endpoints', [])
            
            # 제목
            title = api_info.get('title', 'API Documentation')
            md_lines.append(f"# {title}")
            md_lines.append("")
            
            # 크롤링 정보
            if data.get('crawled_time'):
                md_lines.append(f"**크롤링 시간:** {data['crawled_time']}")
            if data.get('crawled_url'):
                md_lines.append(f"**원본 URL:** {data['crawled_url']}")
            md_lines.append("")
            
            # API 기본 정보
            md_lines.append("## 📋 API 정보")
            md_lines.append("")
            
            if api_info.get('description'):
                description = str(api_info['description']).replace('\n', ' ').strip()
                md_lines.append(f"**설명:** {description}")
                md_lines.append("")
            
            # Base URL 정보
            if api_info.get('base_url'):
                md_lines.append(f"**Base URL:** `{api_info['base_url']}`")
                md_lines.append("")
            
            if api_info.get('schemes') and isinstance(api_info['schemes'], list):
                schemes_str = ", ".join(str(s) for s in api_info['schemes'])
                md_lines.append(f"**지원 프로토콜:** {schemes_str}")
                md_lines.append("")
            
            # 엔드포인트 정보
            if endpoints and isinstance(endpoints, list):
                md_lines.append(f"## 🔗 API 엔드포인트 ({len(endpoints)}개)")
                md_lines.append("")
                
                # Base URL이 있으면 완전한 URL 정보 추가
                base_url = api_info.get('base_url', '')
                if base_url:
                    md_lines.append(f"**Base URL:** `{base_url}`")
                    md_lines.append("")
                
                # 섹션별로 그룹화
                sections = {}
                for endpoint in endpoints:
                    if not isinstance(endpoint, dict):
                        continue
                    section = endpoint.get('section', 'Default')
                    if section not in sections:
                        sections[section] = []
                    sections[section].append(endpoint)
                
                for section_name, section_endpoints in sections.items():
                    if len(sections) > 1:  # 섹션이 여러 개인 경우만 섹션 제목 표시
                        md_lines.append(f"### {section_name}")
                        md_lines.append("")
                    
                    for endpoint in section_endpoints:
                        try:
                            # 엔드포인트 제목
                            method = str(endpoint.get('method', 'GET')).upper()
                            path = str(endpoint.get('path', ''))
                            description = str(endpoint.get('description', '')).replace('\n', ' ').strip()
                            
                            # 완전한 URL 생성 (Base URL이 있는 경우)
                            full_url = f"{base_url}{path}" if base_url and path else path
                            
                            md_lines.append(f"#### `{method}` {path}")
                            if base_url:
                                md_lines.append(f"**완전한 URL:** `{full_url}`")
                            md_lines.append("")
                            
                            if description:
                                md_lines.append(f"**설명:** {description}")
                                md_lines.append("")
                            
                            # 파라미터 정보
                            parameters = endpoint.get('parameters', [])
                            if parameters and isinstance(parameters, list):
                                md_lines.append("**파라미터:**")
                                md_lines.append("")
                                md_lines.append("| 이름 | 타입 | 필수 | 설명 |")
                                md_lines.append("|------|------|------|------|")
                                
                                for param in parameters:
                                    if not isinstance(param, dict):
                                        continue
                                    name = str(param.get('name', '')).replace('|', '\\|')
                                    param_type = str(param.get('type', '')).replace('|', '\\|')
                                    required = "✅" if param.get('required', False) else "❌"
                                    desc = str(param.get('description', '')).replace('\n', ' ').replace('|', '\\|')
                                    
                                    # 설명이 너무 길면 줄이기
                                    if len(desc) > 50:
                                        desc = desc[:50] + "..."
                                    
                                    md_lines.append(f"| `{name}` | {param_type} | {required} | {desc} |")
                                
                                md_lines.append("")
                            
                            # 응답 정보
                            responses = endpoint.get('responses', [])
                            if responses and isinstance(responses, list):
                                md_lines.append("**응답:**")
                                md_lines.append("")
                                md_lines.append("| 상태 코드 | 설명 |")
                                md_lines.append("|-----------|------|")
                                
                                for response in responses:
                                    if not isinstance(response, dict):
                                        continue
                                    status_code = str(response.get('status_code', '')).replace('|', '\\|')
                                    desc = str(response.get('description', '')).replace('\n', ' ').replace('|', '\\|')
                                    
                                    # 설명이 너무 길면 줄이기
                                    if len(desc) > 80:
                                        desc = desc[:80] + "..."
                                    
                                    md_lines.append(f"| `{status_code}` | {desc} |")
                                
                                md_lines.append("")
                            
                            md_lines.append("---")
                            md_lines.append("")
                        except Exception as e:
                            print(f"⚠️  엔드포인트 처리 중 오류: {e}")
                            continue
            
            # 푸터
            md_lines.append("## 📝 생성 정보")
            md_lines.append("")
            md_lines.append("이 문서는 나라장터 API 크롤러에 의해 자동 생성되었습니다.")
            if data.get('api_id'):
                md_lines.append(f"**API ID:** {data['api_id']}")
            if api_info.get('base_url'):
                md_lines.append(f"**Base URL:** {api_info['base_url']}")
            
            return "\n".join(md_lines)
            
        except Exception as e:
            print(f"⚠️  Markdown 변환 중 오류: {e}")
            return f"# Markdown 변환 오류\n\n변환 중 오류가 발생했습니다: {str(e)}"
    
    @staticmethod
    def save_crawling_result(data, output_dir, api_id, formats=['json', 'xml']):
        """크롤링 결과를 지정된 형식으로 저장"""
        saved_files = []
        save_errors = []
        
        # 출력 디렉토리 생성
        os.makedirs(output_dir, exist_ok=True)
        
        # 제공기관 정보 추출
        org_name = "unknown"
        if isinstance(data, dict) and 'info' in data:
            info = data['info']
            if '제공기관명' in info:
                org_name = info['제공기관명']
            elif '제공기관' in info:
                org_name = info['제공기관']
        
        # 제공기관명에서 특수문자 제거 및 공백을 언더스코어로 변경
        org_name = re.sub(r'[^\w\s-]', '', org_name)
        org_name = re.sub(r'[\s]+', '_', org_name).strip()
        
        # 수정일 추출
        modified_date = ""
        if isinstance(data, dict) and 'info' in data:
            info = data['info']
            if '수정일' in info:
                modified_date = info['수정일'].replace('-', '')
        
        # 파일명 생성
        file_base_name = f"{api_id}_{modified_date}" if modified_date else api_id
        
        # 제공기관 디렉토리 생성
        org_dir = os.path.join(output_dir, org_name)
        os.makedirs(org_dir, exist_ok=True)
        
        # 타입별 하위 디렉토리 생성
        type_dirs = {
            'json': os.path.join(org_dir, 'json'),
            'xml': os.path.join(org_dir, 'xml'),
            'md': os.path.join(org_dir, 'markdown')
        }
        
        for dir_path in type_dirs.values():
            os.makedirs(dir_path, exist_ok=True)
        
        # JSON 저장
        if 'json' in formats:
            json_file = os.path.join(type_dirs['json'], f"{file_base_name}.json")
            success, error = DataExporter.save_as_json(data, json_file)
            
            if success:
                saved_files.append(json_file)
                print(f"✓ JSON 저장 성공: {os.path.basename(json_file)}")
            else:
                save_errors.append(f"JSON: {error}")
                print(f"✗ JSON 저장 실패: {error}")
        
        # XML 저장
        if 'xml' in formats:
            xml_file = os.path.join(type_dirs['xml'], f"{file_base_name}.xml")
            
            # JSON 파일이 존재하면 그것을 읽어서 XML로 변환
            if 'json' in formats and saved_files and os.path.exists(saved_files[-1]):
                try:
                    with open(saved_files[-1], 'r', encoding='utf-8') as f:
                        json_data = json.load(f)
                    success, error = DataExporter.save_as_xml(json_data, xml_file)
                except Exception as e:
                    success, error = False, f"JSON 파일 읽기 실패: {str(e)}"
            else:
                # 직접 데이터를 XML로 저장
                success, error = DataExporter.save_as_xml(data, xml_file)
            
            if success:
                saved_files.append(xml_file)
                print(f"✓ XML 저장 성공: {os.path.basename(xml_file)}")
            else:
                save_errors.append(f"XML: {error}")
                print(f"✗ XML 저장 실패: {error}")
        
        # Markdown 저장
        if 'md' in formats or 'markdown' in formats:
            md_file = os.path.join(type_dirs['md'], f"{file_base_name}.md")
            
            # JSON 파일을 찾아서 읽기
            json_file_path = None
            if 'json' in formats:
                # JSON 파일 경로 직접 생성
                json_file_path = os.path.join(type_dirs['json'], f"{file_base_name}.json")
                
            # JSON 파일이 존재하면 그것을 읽어서 Markdown으로 변환
            if json_file_path and os.path.exists(json_file_path):
                try:
                    with open(json_file_path, 'r', encoding='utf-8') as f:
                        json_data = json.load(f)
                    success, error = DataExporter.save_as_markdown(json_data, md_file)
                except Exception as e:
                    success, error = False, f"JSON 파일 읽기 실패: {str(e)}"
            else:
                # 직접 데이터를 Markdown으로 저장
                success, error = DataExporter.save_as_markdown(data, md_file)
            
            if success:
                saved_files.append(md_file)
                print(f"✓ Markdown 저장 성공: {os.path.basename(md_file)}")
            else:
                save_errors.append(f"Markdown: {error}")
                print(f"✗ Markdown 저장 실패: {error}")
        
        # 저장 결과 요약
        if saved_files and not save_errors:
            print(f"📁 모든 형식 저장 완료 ({len(saved_files)}개 파일)")
            print(f"📂 저장 위치: {org_dir}")
        elif saved_files and save_errors:
            print(f"⚠️  일부 형식만 저장됨 (성공: {len(saved_files)}개, 실패: {len(save_errors)}개)")
            print(f"📂 저장 위치: {org_dir}")
        elif save_errors and not saved_files:
            print(f"❌ 모든 형식 저장 실패 ({len(save_errors)}개 오류)")
        
        return saved_files, save_errors
    
    @staticmethod
    def save_table_info(data, output_dir, api_id):
        """테이블 정보 저장"""
        try:
            # info 디렉토리 생성
            info_dir = os.path.join(output_dir, 'info')
            os.makedirs(info_dir, exist_ok=True)
            
            # 파일명 생성
            file_name = f"{api_id}_table_info.json"
            file_path = os.path.join(info_dir, file_name)
            
            # JSON으로 저장
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            
            return True, file_path
            
        except Exception as e:
            return False, f"테이블 정보 저장 실패: {str(e)}" 