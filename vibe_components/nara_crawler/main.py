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
from parser import NaraParser, DataExporter
import concurrent.futures
import threading
import queue
import psutil
import gc
from selenium.webdriver.chrome.service import Service
from selenium.common.exceptions import TimeoutException, WebDriverException

# 전역 변수
driver_pool = None

class OptimizedDriverPool:
    """최적화된 WebDriver 풀 관리 클래스"""
    def __init__(self, pool_size=10):
        self.pool_size = pool_size
        self.drivers = queue.Queue(maxsize=pool_size)
        self.lock = threading.Lock()
        self._initialize_pool()
    
    def _initialize_pool(self):
        """드라이버 풀 초기화"""
        for _ in range(self.pool_size):
            driver = self._create_driver()
            self.drivers.put(driver)
    
    def _create_driver(self):
        """최적화된 WebDriver 생성"""
        opts = Options()
        opts.add_argument("--headless")
        opts.add_argument("--no-sandbox")
        opts.add_argument("--disable-dev-shm-usage")
        opts.add_argument("--disable-gpu")
        opts.add_argument("--disable-extensions")
        opts.add_argument("--disable-plugins")
        opts.add_argument("--disable-background-timer-throttling")
        opts.add_argument("--disable-renderer-backgrounding")
        opts.add_argument("--disable-backgrounding-occluded-windows")
        opts.add_argument("--disable-features=TranslateUI")
        opts.add_argument("--disable-ipc-flooding-protection")
        opts.add_argument("--disable-images")
        opts.add_argument("--disable-css")
        opts.add_argument("--log-level=3")
        opts.add_argument("--no-default-browser-check")
        opts.add_argument("--no-first-run")
        opts.add_argument("--disable-default-apps")
        
        opts.add_experimental_option('excludeSwitches', ['enable-logging'])
        opts.add_experimental_option('useAutomationExtension', False)
        
        return webdriver.Chrome(options=opts)
    
    def get_driver(self):
        """사용 가능한 드라이버 반환"""
        try:
            return self.drivers.get(timeout=5)
        except queue.Empty:
            return self._create_driver()
    
    def return_driver(self, driver):
        """드라이버를 풀에 반환"""
        try:
            driver.get("about:blank")
            driver.delete_all_cookies()
            if self.drivers.qsize() < self.pool_size:
                self.drivers.put(driver)
            else:
                driver.quit()
        except:
            try:
                driver.quit()
            except:
                pass
    
    def close_all(self):
        """모든 드라이버 종료"""
        while not self.drivers.empty():
            try:
                driver = self.drivers.get_nowait()
                driver.quit()
            except:
                pass

class MemoryManager:
    """메모리 관리 클래스"""
    @staticmethod
    def get_memory_usage():
        """현재 메모리 사용량 반환"""
        process = psutil.Process()
        return process.memory_info().rss / 1024 / 1024  # MB 단위
    
    @staticmethod
    def check_memory_threshold(threshold_mb=1000):
        """메모리 사용량이 임계값을 초과하는지 확인"""
        return MemoryManager.get_memory_usage() > threshold_mb
    
    @staticmethod
    def cleanup():
        """메모리 정리"""
        gc.collect()

def get_api_id(url):
    """URL에서 API ID 추출"""
    m = re.search(r'/data/(\d+)/openapi', url)
    return m.group(1) if m else f"api_{url.replace('https://', '').replace('/', '_')}"

def crawl_url(url, output_dir, formats, driver_pool):
    """단일 URL 크롤링"""
    os.makedirs(output_dir, exist_ok=True)
    api_id = get_api_id(url)
    
    driver = driver_pool.get_driver()
    
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
        
        # 페이지 로딩 대기
        WebDriverWait(driver, 5).until(EC.presence_of_element_located((By.TAG_NAME, "body")))
        time.sleep(1)
        
        # Swagger JSON 추출
        parser = NaraParser(driver)
        swagger_json = parser.extract_swagger_json()
        
        if swagger_json:
            print("✅ Swagger JSON 추출 성공!")
            
            # API 정보 추출
            print("📊 API 정보 추출 중...")
            api_info = parser.extract_api_info(swagger_json)
            
            # Base URL 추출
            print("🔗 Base URL 추출 중...")
            base_url = parser.extract_base_url(swagger_json)
            api_info['base_url'] = base_url
            
            # Schemes 추출
            api_info['schemes'] = swagger_json.get('schemes', ['https'])
            
            # 엔드포인트 추출
            print("🔗 엔드포인트 추출 중...")
            endpoints = parser.extract_endpoints(swagger_json)
            
            # 테이블 정보 추출
            print("📋 테이블 정보 추출 중...")
            table_info = parser.extract_table_info()
            
            # 결과 데이터 구성
            result = {
                'api_info': api_info,
                'info': table_info,
                'endpoints': endpoints,
                'crawled_url': url,
                'crawled_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'api_id': api_id,
                'swagger_json': swagger_json
            }
            
            crawling_result['data'] = result
            crawling_result['success'] = True
            
            # 데이터 저장
            print("💾 데이터 저장 중...")
            saved_files, save_errors = DataExporter.save_crawling_result(result, output_dir, api_id, formats)
            
            crawling_result['saved_files'] = saved_files
            crawling_result['errors'] = save_errors
            
        else:
            print("❌ Swagger JSON 추출 실패")
            crawling_result['errors'].append("Swagger JSON을 찾을 수 없습니다.")
        
        # 메모리 정리
        MemoryManager.cleanup()
        
        return crawling_result['success']
    
    except Exception as e:
        error_msg = f"크롤링 실패: {str(e)}"
        print(f"❌ {error_msg}")
        crawling_result['errors'].append(error_msg)
        return False
    finally:
        driver_pool.return_driver(driver)

def generate_urls(start_num, end_num):
    """시작번호와 끝번호 사이의 모든 URL 생성"""
    base_url = "https://www.data.go.kr/data/{}/openapi.do"
    return [base_url.format(num) for num in range(start_num, end_num + 1)]

def batch_crawl(urls, output_dir="output", formats=['json', 'xml', 'md'], max_workers=10):
    """범위 내의 모든 API 문서 크롤링"""
    total_urls = len(urls)
    
    print(f"\n🚀 배치 크롤링 시작")
    print(f"   📋 총 {total_urls}개 URL")
    print(f"   👥 동시 작업자: {max_workers}개")
    print(f"   📁 출력 디렉토리: {output_dir}")
    print(f"   💾 저장 형식: {', '.join(formats)}")
    
    # 드라이버 풀 초기화
    driver_pool = OptimizedDriverPool(pool_size=max_workers)
    
    # 결과 저장용 변수
    results = {
        'total': total_urls,
        'success': 0,
        'failed': 0,
        'failed_urls': [],
        'start_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }
    
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_url = {
                executor.submit(crawl_url, url, output_dir, formats, driver_pool): url 
                for url in urls
            }
            
            with tqdm(total=total_urls, desc="크롤링 진행") as pbar:
                for future in concurrent.futures.as_completed(future_to_url):
                    url = future_to_url[future]
                    
                    if MemoryManager.check_memory_threshold():
                        print("\n⚠️ 메모리 사용량이 높습니다. 정리 중...")
                        MemoryManager.cleanup()
                    
                    try:
                        result = future.result()
                        if result:
                            results['success'] += 1
                        else:
                            results['failed'] += 1
                            results['failed_urls'].append(url)
                    except Exception as e:
                        results['failed'] += 1
                        results['failed_urls'].append(url)
                        print(f"\n⚠️ 예외 발생: {url} - {str(e)}")
                    
                    pbar.update(1)
                    
                    if pbar.n % 10 == 0:
                        MemoryManager.cleanup()
    
    finally:
        driver_pool.close_all()
    
    # 결과 요약
    results['end_time'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    results['success_rate'] = f"{(results['success'] / total_urls * 100):.1f}%" if total_urls > 0 else "0%"
    
    # 결과 저장
    summary_file = os.path.join(output_dir, "crawling_summary.json")
    with open(summary_file, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    
    # 실패한 URL 목록 저장
    if results['failed_urls']:
        failed_urls_file = os.path.join(output_dir, "failed_urls.txt")
        with open(failed_urls_file, 'w', encoding='utf-8') as f:
            for url in results['failed_urls']:
                f.write(f"{url}\n")
    
    # 최종 결과 출력
    print("\n" + "=" * 50)
    print("🏁 배치 크롤링 완료!")
    print("=" * 50)
    print(f"📊 전체 결과:")
    print(f"   📋 총 처리: {results['total']}개 URL")
    print(f"   ✅ 성공: {results['success']}개 ({results['success_rate']})")
    print(f"   ❌ 실패: {results['failed']}개")
    print(f"   📁 결과 위치: {output_dir}")
    print(f"   📋 요약 파일: crawling_summary.json")
    if results['failed'] > 0:
        print(f"   📄 실패 목록: failed_urls.txt")

def main():
    """메인 함수"""
    parser = argparse.ArgumentParser(description='나라장터 API 크롤러')
    parser.add_argument('-s', '--start', type=int, required=True, help='시작 문서 번호')
    parser.add_argument('-e', '--end', type=int, required=True, help='끝 문서 번호')
    parser.add_argument('--output-dir', default='output', help='출력 디렉토리 (기본값: output)')
    parser.add_argument('--formats', nargs='+', default=['json', 'xml', 'md'],
                      choices=['json', 'xml', 'md'], help='저장할 파일 형식')
    parser.add_argument('--workers', type=int, default=10, help='동시 작업자 수 (기본값: 10)')
    parser.add_argument('--no-headless', action='store_true', help='헤드리스 모드 비활성화')
    parser.add_argument('--timeout', type=int, default=30, help='페이지 로드 타임아웃 (초)')
    
    args = parser.parse_args()
    
    # 입력값 검증
    if args.start > args.end:
        print("❌ 시작 번호가 끝 번호보다 클 수 없습니다.")
        sys.exit(1)
    
    if args.workers < 1 or args.workers > 30:
        print("⚠️ 동시 작업자 수는 1-30 사이로 설정해주세요.")
        args.workers = 10
    
    # 배치 크롤링 실행
    batch_crawl(
        generate_urls(args.start, args.end),
        args.output_dir,
        args.formats,
        args.workers
    )

if __name__ == '__main__':
    main() 