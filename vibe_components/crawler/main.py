from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import json
import time
import re
import os
import argparse
from datetime import datetime
import sys
from tqdm import tqdm
from parser import APIParser, DataExporter

def get_api_id(url):
    """URL에서 API ID 추출"""
    m = re.search(r'/data/(\d+)/openapi', url)
    return m.group(1) if m else f"api_{url.replace('https://', '').replace('/', '_')}"

def read_urls(file_path):
    """URL 목록 파일 읽기"""
    with open(file_path, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip() and not line.startswith('#')]

def setup_driver():
    """Selenium WebDriver 설정"""
    opts = Options()
    opts.add_argument("--headless")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--disable-software-rasterizer")
    opts.add_argument("--disable-features=VizDisplayCompositor")
    opts.add_argument("--disable-gl-drawing-for-tests")
    opts.add_argument("--disable-webgl")
    opts.add_argument("--disable-webgl2")
    opts.add_argument("--use-gl=swiftshader")
    opts.add_argument("--disable-usb-keyboard-detect")
    opts.add_argument("--disable-features=WebUSB")
    opts.add_argument("--log-level=3")
    opts.add_experimental_option('excludeSwitches', ['enable-logging'])
    opts.add_experimental_option('useAutomationExtension', False)
    opts.add_experimental_option('prefs', {
        'profile.default_content_setting_values.usb_guard': 2
    })
    return webdriver.Chrome(options=opts)

def crawl_api(url, output_dir="api_docs", formats=['json', 'xml', 'md'], custom_filename=None):
    """API 크롤링 및 저장 - Base URL 추출 기능 개선"""
    os.makedirs(output_dir, exist_ok=True)
    api_id = get_api_id(url) if not custom_filename else custom_filename
    
    driver = setup_driver()
    crawling_result = {
        'success': False,
        'data': None,
        'saved_files': [],
        'errors': [],
        'api_id': api_id,
        'url': url
    }
    
    try:
        print(f"🔍 크롤링 시작: {url}")
        driver.get(url)
        
        try:
            # 페이지 로딩 대기 - 여러 방법으로 시도
            wait_methods = [
                (By.CLASS_NAME, "swagger-ui"),
                (By.CLASS_NAME, "open-api-title"),
                (By.TAG_NAME, "body")
            ]
            
            page_loaded = False
            for method in wait_methods:
                try:
                    WebDriverWait(driver, 20).until(EC.presence_of_element_located(method))
                    page_loaded = True
                    print("✓ 페이지 로딩 완료")
                    break
                except:
                    continue
            
            if not page_loaded:
                print("⚠️  페이지 로딩 확인 실패, 계속 진행...")
            
            time.sleep(5)  # 추가 대기 시간
        except Exception as e:
            print(f"⚠️  페이지 로딩 대기 중 오류: {e}")
            time.sleep(3)
        
        # 파서 인스턴스 생성
        parser = APIParser(driver)
        
        # API 정보 추출
        print("📊 API 정보 추출 중...")
        api_info = parser.extract_api_info()
        api_info = parser.extract_meta_info(api_info)
        
        # Base URL 추출 (개선된 로직)
        print("🔗 Base URL 추출 중...")
        base_url = parser.extract_base_url()
        api_info['base_url'] = base_url
        
        # Schemes 추출
        api_info['schemes'] = parser.extract_schemes()
        
        # 엔드포인트 추출
        print("🔗 엔드포인트 추출 중...")
        endpoints = parser.extract_endpoints()
        
        # 결과 데이터 구성
        result = {
            'api_info': api_info,
            'endpoints': endpoints,
            'crawled_url': url,
            'crawled_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'api_id': api_id
        }
        
        crawling_result['data'] = result
        crawling_result['success'] = True
        
        # 데이터 저장 (JSON, XML)
        print("💾 데이터 저장 중...")
        saved_files, save_errors = DataExporter.save_crawling_result(result, output_dir, api_id, formats)
        
        crawling_result['saved_files'] = saved_files
        crawling_result['errors'] = save_errors
        
        # 저장된 파일 검증
        if saved_files:
            print("🔍 파일 유효성 검증 중...")
            validation_results = DataExporter.validate_saved_files(saved_files)
            
            valid_files = [f for f, r in validation_results.items() if r.get('valid', False)]
            invalid_files = [f for f, r in validation_results.items() if not r.get('valid', False)]
            
            if valid_files:
                print(f"✅ 검증 완료: {len(valid_files)}개 파일이 유효함")
                for file_name, result_info in validation_results.items():
                    if result_info.get('valid', False):
                        size_kb = result_info.get('size', 0) / 1024
                        print(f"   📄 {file_name} ({size_kb:.1f}KB)")
            
            if invalid_files:
                print(f"❌ 검증 실패: {len(invalid_files)}개 파일에 문제 발견")
                for file_name, result_info in validation_results.items():
                    if not result_info.get('valid', False):
                        print(f"   ❌ {file_name}: {result_info.get('error', '알 수 없는 오류')}")
        
        # 결과 요약
        if saved_files and not save_errors:
            print(f"🎉 크롤링 완료!")
            print(f"   📋 API: {result['api_info'].get('title', 'N/A')}")
            print(f"   🌐 Base URL: {result['api_info'].get('base_url', 'N/A')}")
            print(f"   🔗 엔드포인트: {len(result['endpoints'])}개")
            print(f"   📁 저장 파일: {len(saved_files)}개")
        elif saved_files and save_errors:
            print(f"⚠️  부분 성공:")
            print(f"   📋 API: {result['api_info'].get('title', 'N/A')}")
            print(f"   🌐 Base URL: {result['api_info'].get('base_url', 'N/A')}")
            print(f"   🔗 엔드포인트: {len(result['endpoints'])}개")
            print(f"   ✅ 성공: {len(saved_files)}개 파일")
            print(f"   ❌ 실패: {len(save_errors)}개 오류")
            for error in save_errors:
                print(f"      - {error}")
        else:
            print(f"❌ 저장 실패:")
            for error in save_errors:
                print(f"   - {error}")
            crawling_result['success'] = False
        
        return crawling_result
    
    except Exception as e:
        error_msg = f"크롤링 실패: {str(e)}"
        print(f"❌ {error_msg}")
        crawling_result['errors'].append(error_msg)
        return crawling_result
    finally:
        driver.quit()

def batch_crawl(file_path, output_dir="api_docs", formats=['json', 'xml', 'md']):
    """배치 크롤링 - 개선된 버전"""
    urls = read_urls(file_path)
    os.makedirs(output_dir, exist_ok=True)
    
    summary = {
        "total": len(urls),
        "success": 0,
        "partial_success": 0,
        "failed": 0,
        "failed_urls": [],
        "success_details": [],
        "start_time": datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        "output_formats": formats,
        "output_directory": output_dir
    }
    
    print(f"🚀 배치 크롤링 시작")
    print(f"   📋 총 {len(urls)}개 URL")
    print(f"   📁 출력 디렉토리: {output_dir}")
    print(f"   💾 저장 형식: {', '.join(formats)}")
    print("=" * 50)
    
    for i, url in enumerate(tqdm(urls, desc="크롤링 진행"), 1):
        print(f"\n[{i}/{len(urls)}] 처리 중...")
        
        try:
            result = crawl_api(url, output_dir, formats)
            
            if result['success'] and result['saved_files'] and not result['errors']:
                # 완전 성공
                summary["success"] += 1
                success_detail = {
                    "url": url,
                    "api_id": result['api_id'],
                    "title": result['data']['api_info'].get('title', 'N/A'),
                    "base_url": result['data']['api_info'].get('base_url', 'N/A'),
                    "endpoints_count": len(result['data'].get('endpoints', [])),
                    "saved_files": [os.path.basename(f) for f in result['saved_files']],
                    "status": "완전 성공"
                }
                summary["success_details"].append(success_detail)
                
            elif result['success'] and result['saved_files'] and result['errors']:
                # 부분 성공
                summary["partial_success"] += 1
                success_detail = {
                    "url": url,
                    "api_id": result['api_id'],
                    "title": result['data']['api_info'].get('title', 'N/A'),
                    "base_url": result['data']['api_info'].get('base_url', 'N/A'),
                    "endpoints_count": len(result['data'].get('endpoints', [])),
                    "saved_files": [os.path.basename(f) for f in result['saved_files']],
                    "save_errors": result['errors'],
                    "status": "부분 성공"
                }
                summary["success_details"].append(success_detail)
                
            else:
                # 실패
                summary["failed"] += 1
                summary["failed_urls"].append({
                    "url": url,
                    "api_id": result.get('api_id', 'unknown'),
                    "reason": "; ".join(result['errors']) if result['errors'] else "알 수 없는 오류"
                })
                
        except Exception as e:
            summary["failed"] += 1
            summary["failed_urls"].append({
                "url": url,
                "api_id": get_api_id(url),
                "reason": f"예외 발생: {str(e)}"
            })
        
        # URL 간 대기 시간
        if i < len(urls):
            time.sleep(2)
    
    # 배치 크롤링 완료 처리
    summary["end_time"] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # 성공률 계산
    total_attempted = summary['total']
    if total_attempted > 0:
        success_rate = (summary['success'] + summary['partial_success']) / total_attempted * 100
        summary["success_rate"] = f"{success_rate:.1f}%"
        summary["complete_success_rate"] = f"{(summary['success'] / total_attempted * 100):.1f}%"
    else:
        summary["success_rate"] = "0%"
        summary["complete_success_rate"] = "0%"
    
    # 요약 정보 저장
    summary_file = os.path.join(output_dir, "crawling_summary.json")
    success, error = DataExporter.save_as_json(summary, summary_file)
    if not success:
        print(f"⚠️  요약 파일 저장 실패: {error}")
    
    # 실패한 URL 목록 저장 (재시도용)
    if summary["failed_urls"]:
        failed_urls_file = os.path.join(output_dir, "failed_urls.txt")
        try:
            with open(failed_urls_file, 'w', encoding='utf-8') as f:
                for item in summary["failed_urls"]:
                    f.write(f"{item['url']}\n")
            print(f"📄 실패 URL 목록 저장: {failed_urls_file}")
        except Exception as e:
            print(f"⚠️  실패 URL 목록 저장 실패: {e}")
    
    # 최종 결과 출력
    print("\n" + "=" * 50)
    print("🏁 배치 크롤링 완료!")
    print("=" * 50)
    print(f"📊 전체 결과:")
    print(f"   📋 총 처리: {summary['total']}개 URL")
    print(f"   ✅ 완전 성공: {summary['success']}개 ({summary['complete_success_rate']})")
    print(f"   ⚠️  부분 성공: {summary['partial_success']}개")
    print(f"   ❌ 실패: {summary['failed']}개")
    print(f"   📈 전체 성공률: {summary['success_rate']}")
    print(f"   💾 저장 형식: {', '.join(formats)}")
    print(f"   📁 결과 위치: {output_dir}")
    
    if success:
        print(f"   📋 요약 파일: crawling_summary.json")
    if summary["failed"] > 0:
        print(f"   📄 실패 목록: failed_urls.txt")

def main():
    parser = argparse.ArgumentParser(description='공공데이터포털 API 크롤러 (Base URL 추출 기능 개선)')
    parser.add_argument('url', nargs='?', help='API URL')
    parser.add_argument('-f', '--file', help='URL 목록 파일')
    parser.add_argument('-o', '--output', help='출력 파일 (단일 크롤링 시)')
    parser.add_argument('-d', '--dir', default='api_docs', help='출력 디렉토리')
    parser.add_argument('--format', 
                       choices=['json', 'xml', 'md', 'markdown', 'all'], 
                       default='all',
                       help='출력 형식 선택 (기본값: all)')
    
    args = parser.parse_args()
    
    if not args.url and not args.file:
        parser.print_help()
        sys.exit(1)
    
    # 출력 형식 설정
    if args.format == 'all':
        formats = ['json', 'xml', 'md']
    elif args.format in ['md', 'markdown']:
        formats = ['json', 'md']  # Markdown은 JSON을 먼저 생성한 후 변환
    else:
        formats = [args.format]
    
    if args.file:
        batch_crawl(args.file, args.dir, formats)
    else:
        # 단일 크롤링 시 사용자 지정 파일명 처리
        custom_filename = None
        if args.output:
            # 확장자 제거
            custom_filename = os.path.splitext(os.path.basename(args.output))[0]
        
        result = crawl_api(args.url, args.dir, formats, custom_filename)
        if not result['success'] or not result['saved_files']:
            print("❌ 크롤링 실패. 위의 오류 메시지를 확인하세요.")
            sys.exit(1)
        else:
            print("✅ 단일 크롤링 성공적으로 완료!")

if __name__ == "__main__":
    main()