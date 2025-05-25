import xml.etree.ElementTree as ET
from xml.dom import minidom
import json
import re
import os
from datetime import datetime
from selenium.webdriver.common.by import By

class APIParser:
    def __init__(self, driver):
        self.driver = driver
    
    def extract_api_info(self):
        """API 기본 정보 추출"""
        api_info = {}
        
        # API 정보 추출 - 실패 시 크롤링 중단
        for cls, key in [("open-api-title", "title"), ("cont", "description")]:
            try:
                api_info[key] = self.driver.find_element(By.CLASS_NAME, cls).text.strip()
            except Exception as e:
                print(f"API 정보 추출 실패 ({key}): {e}")
                raise Exception(f"필수 API 정보({key}) 추출 실패: {e}")
        
        return api_info
    
    def extract_meta_info(self, api_info):
        """메타 정보 추출"""
        try:
            for row in self.driver.find_elements(By.CSS_SELECTOR, ".dataset-table tr"):
                th, td = row.find_elements(By.TAG_NAME, "th"), row.find_elements(By.TAG_NAME, "td")
                if th and td:
                    api_info[th[0].text.strip()] = td[0].text.strip()
        except:
            pass
        
        return api_info
    
    def extract_base_url(self):
        """Base URL 추출 - 다양한 방법으로 시도"""
        base_url = ""
        
        # 방법 1: Swagger UI에서 base-url 클래스 찾기
        try:
            base_url_element = self.driver.find_element(By.CLASS_NAME, "base-url")
            base_url_text = base_url_element.text
            # [Base URL: xxx] 형태에서 URL 추출
            match = re.search(r'\[\s*Base URL:\s*([^\]]+)\s*\]', base_url_text)
            if match:
                base_url = match.group(1).strip()
                print(f"✓ Base URL 추출 성공 (방법 1): {base_url}")
                return base_url
        except Exception as e:
            print(f"Base URL 추출 방법 1 실패: {e}")
        
        # 방법 2: Swagger UI 정보 섹션에서 추출
        try:
            info_elements = self.driver.find_elements(By.CSS_SELECTOR, ".info .base-url")
            for element in info_elements:
                text = element.text.strip()
                if text and text.startswith('[') and text.endswith(']'):
                    # [Base URL: xxx] 형태에서 추출
                    url_match = re.search(r'Base URL:\s*([^\]]+)', text)
                    if url_match:
                        base_url = url_match.group(1).strip()
                        print(f"✓ Base URL 추출 성공 (방법 2): {base_url}")
                        return base_url
        except Exception as e:
            print(f"Base URL 추출 방법 2 실패: {e}")
        
        # 방법 3: pre 태그 내 base-url 찾기
        try:
            pre_elements = self.driver.find_elements(By.TAG_NAME, "pre")
            for pre in pre_elements:
                text = pre.text
                if "Base URL:" in text:
                    # [ Base URL: xxx ] 형태에서 추출
                    match = re.search(r'\[\s*Base URL:\s*([^\]]+)\s*\]', text)
                    if match:
                        base_url = match.group(1).strip()
                        print(f"✓ Base URL 추출 성공 (방법 3): {base_url}")
                        return base_url
        except Exception as e:
            print(f"Base URL 추출 방법 3 실패: {e}")
        
        # 방법 4: 페이지 소스에서 정규표현식으로 검색
        try:
            page_source = self.driver.page_source
            # 여러 패턴으로 Base URL 찾기
            patterns = [
                r'"basePath"\s*:\s*"([^"]+)"',
                r'"host"\s*:\s*"([^"]+)"',
                r'Base URL:\s*([^\]]+)',
                r'basePath["\']?\s*:\s*["\']([^"\']+)["\']',
                r'host["\']?\s*:\s*["\']([^"\']+)["\']'
            ]
            
            for pattern in patterns:
                matches = re.findall(pattern, page_source, re.IGNORECASE)
                if matches:
                    for match in matches:
                        if match and not match.startswith('[') and '/' in match:
                            base_url = match.strip()
                            print(f"✓ Base URL 추출 성공 (방법 4): {base_url}")
                            return base_url
        except Exception as e:
            print(f"Base URL 추출 방법 4 실패: {e}")
        
        # 방법 5: 데이터 테이블에서 API 관련 정보 찾기
        try:
            for row in self.driver.find_elements(By.CSS_SELECTOR, ".dataset-table tr"):
                th_elements = row.find_elements(By.TAG_NAME, "th")
                td_elements = row.find_elements(By.TAG_NAME, "td")
                
                if th_elements and td_elements:
                    th_text = th_elements[0].text.strip().lower()
                    td_text = td_elements[0].text.strip()
                    
                    if any(keyword in th_text for keyword in ['base', 'url', 'host', 'endpoint']):
                        if td_text and ('.' in td_text or '/' in td_text):
                            base_url = td_text
                            print(f"✓ Base URL 추출 성공 (방법 5): {base_url}")
                            return base_url
        except Exception as e:
            print(f"Base URL 추출 방법 5 실패: {e}")
        
        # 방법 6: OpenAPI JSON 스펙에서 추출
        try:
            # 페이지에서 JSON 형태의 OpenAPI 스펙 찾기
            scripts = self.driver.find_elements(By.TAG_NAME, "script")
            for script in scripts:
                script_content = script.get_attribute("innerHTML")
                if script_content and '"swagger"' in script_content:
                    # JSON에서 host와 basePath 찾기
                    host_match = re.search(r'"host"\s*:\s*"([^"]+)"', script_content)
                    base_path_match = re.search(r'"basePath"\s*:\s*"([^"]+)"', script_content)
                    
                    if host_match:
                        host = host_match.group(1)
                        base_path = base_path_match.group(1) if base_path_match else ""
                        base_url = f"{host}{base_path}"
                        print(f"✓ Base URL 추출 성공 (방법 6): {base_url}")
                        return base_url
        except Exception as e:
            print(f"Base URL 추출 방법 6 실패: {e}")
        
        print("⚠️  Base URL을 찾을 수 없음")
        return base_url
    
    def extract_schemes(self):
        """Schemes 추출"""
        try:
            return [opt.text for opt in self.driver.find_elements(By.CSS_SELECTOR, ".schemes select option")]
        except:
            return ["http", "https"]
    
    def extract_parameters(self, block):
        """파라미터 정보 추출"""
        parameters = []
        try:
            for row in block.find_elements(By.CSS_SELECTOR, ".parameters-container table tr")[1:]:
                cols = row.find_elements(By.TAG_NAME, "td")
                if len(cols) >= 2:
                    name_div = cols[0].find_element(By.CLASS_NAME, "parameter__name")
                    parameters.append({
                        'name': name_div.text,
                        'description': cols[1].find_element(By.CLASS_NAME, "markdown").text,
                        'required': "required" in name_div.get_attribute("class"),
                        'type': cols[0].find_element(By.CLASS_NAME, "parameter__type").text if cols[0].find_elements(By.CLASS_NAME, "parameter__type") else ""
                    })
        except:
            pass
        
        return parameters
    
    def extract_responses(self, block):
        """응답 정보 추출"""
        responses = []
        try:
            for row in block.find_elements(By.CLASS_NAME, "response"):
                responses.append({
                    'status_code': row.find_element(By.CLASS_NAME, "response-col_status").text,
                    'description': row.find_element(By.CLASS_NAME, "markdown").text if row.find_elements(By.CLASS_NAME, "markdown") else ""
                })
        except:
            pass
        
        return responses
    
    def extract_endpoints(self):
        """엔드포인트 정보 추출"""
        import time
        
        endpoints = []
        sections = self.driver.find_elements(By.CLASS_NAME, "opblock-tag-section")
        
        for section in sections:
            section_title = section.find_element(By.CLASS_NAME, "opblock-tag").text.strip() if section else "Unnamed"
            
            if "is-open" not in section.get_attribute("class"):
                try:
                    section.find_element(By.CLASS_NAME, "expand-operation").click()
                    time.sleep(0.5)
                except:
                    pass
            
            for block in section.find_elements(By.CLASS_NAME, "opblock"):
                if "is-open" not in block.get_attribute("class"):
                    try:
                        block.find_element(By.CLASS_NAME, "opblock-summary-control").click()
                        time.sleep(1.5)
                    except:
                        continue
                
                try:
                    ep = {
                        'method': block.find_element(By.CLASS_NAME, "opblock-summary-method").text,
                        'path': block.find_element(By.CLASS_NAME, "opblock-summary-path").text,
                        'description': block.find_element(By.CLASS_NAME, "opblock-summary-description").text,
                        'section': section_title,
                        'parameters': self.extract_parameters(block),
                        'responses': self.extract_responses(block)
                    }
                    
                    endpoints.append(ep)
                except:
                    pass
        
        return endpoints

class DataExporter:
    @staticmethod
    def save_as_json(data, file_path):
        """JSON 형태로 저장"""
        try:
            # 디렉토리가 없으면 생성
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            
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
                    
                    element = ET.SubElement(parent, clean_name)
                
                if isinstance(d, dict):
                    for key, value in d.items():
                        _dict_to_xml_element(value, element, key)
                elif isinstance(d, list):
                    for i, item in enumerate(d):
                        if isinstance(item, dict):
                            _dict_to_xml_element(item, element, f"item_{i}")
                        else:
                            item_elem = ET.SubElement(element, f"item_{i}")
                            item_elem.text = str(item) if item is not None else ""
                else:
                    element.text = str(d) if d is not None else ""
            
            root = ET.Element(root_name)
            _dict_to_xml_element(data, root)
            return root, None
        except Exception as e:
            return None, f"XML 변환 실패: {str(e)}"
    
    @staticmethod
    def save_as_xml(data, file_path):
        """XML 형태로 저장"""
        try:
            # 디렉토리가 없으면 생성
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            
            # 딕셔너리를 XML로 변환
            root, error = DataExporter.dict_to_xml(data)
            if error:
                return False, error
            
            # 예쁘게 포맷팅
            rough_string = ET.tostring(root, encoding='utf-8')
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
            if dir_path:  # 디렉토리 경로가 있는 경우만
                os.makedirs(dir_path, exist_ok=True)
            
            md_content = DataExporter.dict_to_markdown(data)
            
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(md_content)
            
            return True, None
        except Exception as e:
            return False, f"Markdown 저장 실패: {str(e)}"
    
    @staticmethod
    def dict_to_markdown(data):
        """딕셔너리를 Markdown 형식으로 변환 - Base URL 정보 포함"""
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
            
            # Base URL 정보 (강화)
            if api_info.get('base_url'):
                md_lines.append(f"**Base URL:** `{api_info['base_url']}`")
                md_lines.append("")
            
            if api_info.get('schemes') and isinstance(api_info['schemes'], list):
                schemes_str = ", ".join(str(s) for s in api_info['schemes'])
                md_lines.append(f"**지원 프로토콜:** {schemes_str}")
                md_lines.append("")
            
            # 메타 정보 테이블
            meta_info = {}
            for k, v in api_info.items():
                if k not in ['title', 'description', 'base_url', 'schemes'] and v:
                    meta_info[str(k)] = str(v)
            
            if meta_info:
                md_lines.append("### 상세 정보")
                md_lines.append("")
                md_lines.append("| 항목 | 값 |")
                md_lines.append("|------|-----|")
                
                for key, value in meta_info.items():
                    # 값이 너무 길면 줄바꿈 처리
                    if len(value) > 100:
                        value = value[:100] + "..."
                    # 테이블에서 파이프 문자 이스케이프
                    key = key.replace('|', '\\|')
                    value = value.replace('|', '\\|').replace('\n', ' ')
                    md_lines.append(f"| {key} | {value} |")
                
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
                            # 개별 엔드포인트 처리 실패 시 건너뛰기
                            print(f"⚠️  엔드포인트 처리 중 오류: {e}")
                            continue
            
            # 푸터
            md_lines.append("## 📝 생성 정보")
            md_lines.append("")
            md_lines.append("이 문서는 공공데이터포털 API 크롤러에 의해 자동 생성되었습니다.")
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
        """크롤링 결과를 지정된 형식으로 저장 - 제공기관별 디렉토리 구조"""
        saved_files = []
        save_errors = []
        
        # 출력 디렉토리 생성
        os.makedirs(output_dir, exist_ok=True)
        
        # 제공기관 정보 추출
        org_name = "unknown"
        if isinstance(data, dict) and 'api_info' in data:
            # 제공기관 정보 찾기 (다양한 키 이름 대응)
            org_keys = ['제공기관', 'provider', 'organization', 'org_name', '기관명']
            for key in org_keys:
                if key in data['api_info']:
                    org_name = data['api_info'][key]
                    break
        
        # 제공기관명에서 특수문자 제거 및 공백을 언더스코어로 변경
        org_name = re.sub(r'[^\w\s-]', '', org_name)
        org_name = re.sub(r'[\s]+', '_', org_name).strip()
        
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
            json_file = os.path.join(type_dirs['json'], f"{api_id}_api_docs.json")
            success, error = DataExporter.save_as_json(data, json_file)
            
            if success:
                saved_files.append(json_file)
                print(f"✓ JSON 저장 성공: {os.path.basename(json_file)}")
            else:
                save_errors.append(f"JSON: {error}")
                print(f"✗ JSON 저장 실패: {error}")
        
        # XML 저장 (JSON이 성공한 경우 또는 XML만 요청한 경우)
        if 'xml' in formats:
            xml_file = os.path.join(type_dirs['xml'], f"{api_id}_api_docs.xml")
            
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
            md_file = os.path.join(type_dirs['md'], f"{api_id}_api_docs.md")
            
            # JSON 파일을 찾아서 읽기
            json_file_path = None
            if 'json' in formats:
                # JSON 파일 경로 직접 생성
                json_file_path = os.path.join(type_dirs['json'], f"{api_id}_api_docs.json")
                
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
    def validate_saved_files(file_paths):
        """저장된 파일들의 유효성 검증"""
        validation_results = {}
        
        for file_path in file_paths:
            file_name = os.path.basename(file_path)
            
            if not os.path.exists(file_path):
                validation_results[file_name] = {"valid": False, "error": "파일이 존재하지 않음"}
                continue
            
            try:
                file_size = os.path.getsize(file_path)
                if file_size == 0:
                    validation_results[file_name] = {"valid": False, "error": "빈 파일"}
                    continue
                
                # 파일 형식별 유효성 검사
                if file_path.endswith('.json'):
                    with open(file_path, 'r', encoding='utf-8') as f:
                        json.load(f)  # JSON 파싱 테스트
                    validation_results[file_name] = {"valid": True, "size": file_size}
                    
                elif file_path.endswith('.xml'):
                    ET.parse(file_path)  # XML 파싱 테스트
                    validation_results[file_name] = {"valid": True, "size": file_size}
                    
                elif file_path.endswith('.md'):
                    # Markdown 파일은 텍스트 파일이므로 기본 검증만
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                        if len(content.strip()) > 0:
                            validation_results[file_name] = {"valid": True, "size": file_size}
                        else:
                            validation_results[file_name] = {"valid": False, "error": "빈 내용"}
                    
                else:
                    validation_results[file_name] = {"valid": True, "size": file_size}
                    
            except Exception as e:
                validation_results[file_name] = {"valid": False, "error": str(e)}
        
        return validation_results