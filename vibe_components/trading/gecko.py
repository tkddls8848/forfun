import requests
import time
import json
import pandas as pd
from datetime import datetime, timedelta
import logging
from typing import Dict, List, Optional
import os
import sys

class GeckoTerminalAPI:
    """GeckoTerminal API 클라이언트 클래스"""
    
    def __init__(self):
        self.base_url = "https://api.geckoterminal.com/api/v2"
        self.headers = {
            "Accept": "application/json;version=20230302",
            "User-Agent": "DEX-Data-Collector/1.0"
        }
        self.rate_limit_delay = 2.1  # 30 calls/minute = 2초 간격
        
        # 로깅 설정
        # Windows 콘솔 인코딩 설정
        if sys.platform == "win32":
            try:
                # Windows 콘솔을 UTF-8로 설정
                import codecs
                sys.stdout = codecs.getwriter('utf-8')(sys.stdout.detach())
                sys.stderr = codecs.getwriter('utf-8')(sys.stderr.detach())
            except:
                pass  # 설정 실패시 무시
        
        # 로그 핸들러 설정
        file_handler = logging.FileHandler('gecko_data.log', encoding='utf-8')
        console_handler = logging.StreamHandler(sys.stdout)
        
        # Windows에서 콘솔 출력 인코딩 설정
        if sys.platform == "win32":
            console_handler.setStream(sys.stdout)
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[file_handler, console_handler]
        )
        self.logger = logging.getLogger(__name__)

    def _make_request(self, endpoint: str, params: Dict = None) -> Optional[Dict]:
        """API 요청을 보내고 응답을 반환"""
        url = f"{self.base_url}{endpoint}"
        
        try:
            time.sleep(self.rate_limit_delay)  # Rate limiting
            response = requests.get(url, headers=self.headers, params=params)
            response.raise_for_status()
            
            self.logger.info(f"[성공] {endpoint}")
            return response.json()
            
        except requests.exceptions.RequestException as e:
            self.logger.error(f"[실패] API 요청 실패 {endpoint}: {e}")
            return None

    def get_networks(self) -> List[Dict]:
        """지원하는 네트워크 목록 조회"""
        self.logger.info("[네트워크] 네트워크 목록 조회 중...")
        
        networks = []
        page = 1
        
        while True:
            data = self._make_request("/networks", {"page": page})
            if not data or not data.get('data'):
                break
                
            networks.extend(data['data'])
            
            # 다음 페이지가 있는지 확인
            if len(data['data']) < 100:  # 기본 페이지 크기가 100이라 가정
                break
            page += 1
            
        self.logger.info(f"[데이터] 총 {len(networks)}개 네트워크 발견")
        return networks

    def get_dexes_by_network(self, network_id: str) -> List[Dict]:
        """특정 네트워크의 DEX 목록 조회"""
        self.logger.info(f"[DEX] {network_id} 네트워크의 DEX 조회 중...")
        
        dexes = []
        page = 1
        
        while True:
            data = self._make_request(f"/networks/{network_id}/dexes", {"page": page})
            if not data or not data.get('data'):
                break
                
            dexes.extend(data['data'])
            
            if len(data['data']) < 100:
                break
            page += 1
            
        self.logger.info(f"[DEX] {network_id}에서 {len(dexes)}개 DEX 발견")
        return dexes

    def get_top_pools(self, network_id: str, dex_id: str = None, limit_pages: int = 5) -> List[Dict]:
        """네트워크 또는 특정 DEX의 탑 풀 조회"""
        if dex_id:
            endpoint = f"/networks/{network_id}/dexes/{dex_id}/pools"
            self.logger.info(f"[풀] {network_id}/{dex_id}의 탑 풀 조회 중...")
        else:
            endpoint = f"/networks/{network_id}/pools"
            self.logger.info(f"[풀] {network_id} 네트워크의 탑 풀 조회 중...")
        
        pools = []
        
        for page in range(1, min(limit_pages + 1, 11)):  # 최대 10페이지
            params = {
                "page": page,
                "include": "base_token,quote_token,dex",
                "sort": "h24_volume_usd_desc"
            }
            
            data = self._make_request(endpoint, params)
            if not data or not data.get('data'):
                break
                
            pools.extend(data['data'])
            
            if len(data['data']) < 20:  # 더 이상 데이터가 없으면 중단
                break
                
        self.logger.info(f"[완료] {len(pools)}개 풀 수집 완료")
        return pools

    def get_pool_trades(self, network_id: str, pool_address: str, min_volume_usd: float = 1000) -> List[Dict]:
        """특정 풀의 거래 데이터 조회 (지난 24시간)"""
        self.logger.info(f"[거래] {network_id}/{pool_address[:8]}...의 거래 데이터 조회 중...")
        
        params = {
            "trade_volume_in_usd_greater_than": min_volume_usd
        }
        
        data = self._make_request(f"/networks/{network_id}/pools/{pool_address}/trades", params)
        
        if data and data.get('data'):
            trades = data['data']
            self.logger.info(f"[거래] {len(trades)}개 거래 발견 (최소 거래량: ${min_volume_usd:,.0f})")
            return trades
        
        return []

    def get_pool_ohlcv(self, network_id: str, pool_address: str, timeframe: str = "hour", 
                       aggregate: str = "1", limit: int = 100) -> Dict:
        """풀의 OHLCV 데이터 조회"""
        self.logger.info(f"[OHLCV] {network_id}/{pool_address[:8]}...의 OHLCV 데이터 조회 중...")
        
        params = {
            "aggregate": aggregate,
            "limit": limit,
            "currency": "usd"
        }
        
        data = self._make_request(f"/networks/{network_id}/pools/{pool_address}/ohlcv/{timeframe}", params)
        
        if data and data.get('data'):
            self.logger.info(f"[OHLCV] OHLCV 데이터 수집 완료")
            return data
        
        return {}

    def get_token_prices(self, network_id: str, token_addresses: List[str]) -> Dict:
        """여러 토큰의 현재 가격 조회"""
        # 최대 30개씩 배치로 처리
        batch_size = 30
        all_prices = {}
        
        for i in range(0, len(token_addresses), batch_size):
            batch = token_addresses[i:i + batch_size]
            addresses_str = ",".join(batch)
            
            self.logger.info(f"[가격] 토큰 가격 조회 중... ({i+1}-{min(i+batch_size, len(token_addresses))}/{len(token_addresses)})")
            
            params = {
                "include_24hr_vol": "true",
                "include_24hr_price_change": "true",
                "include_market_cap": "true"
            }
            
            data = self._make_request(f"/simple/networks/{network_id}/token_price/{addresses_str}", params)
            
            if data and data.get('data'):
                for item in data['data']:
                    if 'attributes' in item and 'token_prices' in item['attributes']:
                        all_prices.update(item['attributes']['token_prices'])
        
        self.logger.info(f"[가격] {len(all_prices)}개 토큰 가격 수집 완료")
        return all_prices

class DEXDataCollector:
    """DEX 데이터 수집 및 저장 클래스"""
    
    def __init__(self):
        self.api = GeckoTerminalAPI()
        self.data_folder = "data"
        self.ensure_data_folder()
        
    def ensure_data_folder(self):
        """데이터 폴더 생성"""
        if not os.path.exists(self.data_folder):
            os.makedirs(self.data_folder)

    def collect_comprehensive_data(self, target_networks: List[str] = None, 
                                 max_pools_per_network: int = 50,
                                 min_trade_volume: float = 1000):
        """종합적인 DEX 데이터 수집"""
        
        print("[시작] DEX 데이터 수집 시작!")
        print("=" * 60)
        
        # 1. 네트워크 정보 수집
        networks = self.api.get_networks()
        if not networks:
            print("[오류] 네트워크 정보를 가져올 수 없습니다.")
            return
        
        # 타겟 네트워크 필터링
        if target_networks:
            networks = [n for n in networks if n['id'] in target_networks]
        
        all_data = {
            'networks': networks,
            'pools_data': [],
            'trades_data': [],
            'prices_data': {},
            'collection_timestamp': datetime.now().isoformat()
        }
        
        print(f"[데이터] {len(networks)}개 네트워크에서 데이터 수집 중...")
        
        for network in networks[:5]:  # 처음 5개 네트워크만 처리 (시간 절약)
            network_id = network['id']
            network_name = network['attributes']['name']
            
            print(f"\n[처리] {network_name} ({network_id}) 처리 중...")
            
            # 2. 탑 풀 조회
            pools = self.api.get_top_pools(network_id, limit_pages=3)
            if not pools:
                continue
                
            # 상위 풀들만 선택
            top_pools = pools[:max_pools_per_network]
            
            for i, pool in enumerate(top_pools[:10]):  # 처음 10개 풀만 상세 분석
                pool_address = pool['attributes']['address']
                pool_name = pool['attributes']['name']
                
                print(f"  [풀] [{i+1}/{len(top_pools)}] {pool_name[:30]}... 분석 중")
                
                # 풀 기본 정보 저장
                pool_data = {
                    'network_id': network_id,
                    'network_name': network_name,
                    'pool_address': pool_address,
                    'pool_name': pool_name,
                    'pool_info': pool['attributes']
                }
                all_data['pools_data'].append(pool_data)
                
                # 3. 거래 데이터 수집
                trades = self.api.get_pool_trades(network_id, pool_address, min_trade_volume)
                if trades:
                    for trade in trades:
                        trade_data = {
                            'network_id': network_id,
                            'pool_address': pool_address,
                            'pool_name': pool_name,
                            'trade_info': trade['attributes']
                        }
                        all_data['trades_data'].append(trade_data)
                
                # 4. OHLCV 데이터 수집
                ohlcv_data = self.api.get_pool_ohlcv(network_id, pool_address, "hour", "1", 24)
                if ohlcv_data:
                    pool_data['ohlcv_data'] = ohlcv_data
        
        # 5. 데이터 저장
        self.save_data(all_data)
        self.create_summary_report(all_data)
        
        print("\n[완료] 데이터 수집 완료!")
        print(f"[결과] 수집된 데이터:")
        print(f"   - 네트워크: {len(all_data['networks'])}개")
        print(f"   - 풀: {len(all_data['pools_data'])}개")
        print(f"   - 거래: {len(all_data['trades_data'])}개")

    def save_data(self, data: Dict):
        """데이터를 JSON과 CSV로 저장"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # JSON 저장
        json_file = f"{self.data_folder}/data_{timestamp}.json"
        with open(json_file, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        
        # 풀 데이터 CSV 저장
        if data['pools_data']:
            pools_df = pd.json_normalize(data['pools_data'])
            pools_df.to_csv(f"{self.data_folder}/pools_{timestamp}.csv", index=False, encoding='utf-8-sig')
        
        # 거래 데이터 CSV 저장
        if data['trades_data']:
            trades_df = pd.json_normalize(data['trades_data'])
            trades_df.to_csv(f"{self.data_folder}/trades_{timestamp}.csv", index=False, encoding='utf-8-sig')
        
        print(f"[저장] 데이터 저장 완료: {json_file}")

    def create_summary_report(self, data: Dict):
        """요약 리포트 생성"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        report_file = f"{self.data_folder}/summary_report_{timestamp}.txt"
        
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write("DEX 데이터 수집 요약 리포트\n")
            f.write("=" * 50 + "\n")
            f.write(f"수집 시간: {data['collection_timestamp']}\n\n")
            
            f.write(f"[네트워크] 네트워크 정보:\n")
            for network in data['networks']:
                f.write(f"  - {network['attributes']['name']} ({network['id']})\n")
            
            f.write(f"\n[풀] 풀 정보 ({len(data['pools_data'])}개):\n")
            for pool in data['pools_data'][:10]:  # 상위 10개만 표시
                f.write(f"  - {pool['pool_name']} ({pool['network_name']})\n")
                if 'pool_info' in pool:
                    volume = pool['pool_info'].get('volume_usd', {}).get('h24', 'N/A')
                    f.write(f"    24h 거래량: ${volume}\n")
            
            f.write(f"\n[거래] 거래 통계:\n")
            f.write(f"  - 총 거래 수: {len(data['trades_data'])}개\n")
            
            if data['trades_data']:
                total_volume = sum(float(trade['trade_info'].get('volume_in_usd', 0)) 
                                 for trade in data['trades_data'])
                f.write(f"  - 총 거래량: ${total_volume:,.2f}\n")
        
        print(f"[리포트] 요약 리포트 생성: {report_file}")

    def get_real_time_prices(self, networks_tokens: Dict[str, List[str]]):
        """실시간 토큰 가격 조회"""
        print("[가격] 실시간 가격 조회 중...")
        
        all_prices = {}
        
        for network_id, token_addresses in networks_tokens.items():
            print(f"[조회] {network_id} 네트워크 가격 조회...")
            prices = self.api.get_token_prices(network_id, token_addresses)
            all_prices[network_id] = prices
        
        # 가격 데이터 저장
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        prices_file = f"{self.data_folder}/prices_{timestamp}.json"
        
        with open(prices_file, 'w', encoding='utf-8') as f:
            json.dump(all_prices, f, indent=2, ensure_ascii=False)
        
        print(f"[저장] 가격 데이터 저장: {prices_file}")
        return all_prices


def main():
    """메인 실행 함수"""
    collector = DEXDataCollector()
    
    print("GeckoTerminal DEX 데이터 수집기")
    print("=" * 50)
    
    # 옵션 선택
    print("\n수집 옵션을 선택하세요:")
    print("1. 전체 DEX 데이터 수집 (풀, 거래, 가격)")
    print("2. 특정 네트워크만 수집")
    print("3. 실시간 토큰 가격만 조회")
    
    choice = input("\n선택 (1-3): ").strip()
    
    if choice == "1":
        # 전체 데이터 수집
        collector.collect_comprehensive_data(
            max_pools_per_network=20,
            min_trade_volume=500
        )
        
    elif choice == "2":
        # 특정 네트워크 선택
        target_networks = input("네트워크 ID를 입력하세요 (예: eth,bsc,polygon): ").strip().split(',')
        target_networks = [n.strip() for n in target_networks if n.strip()]
        
        collector.collect_comprehensive_data(
            target_networks=target_networks,
            max_pools_per_network=30,
            min_trade_volume=100
        )
        
    elif choice == "3":
        # 실시간 가격 조회
        print("\n토큰 주소를 입력하세요:")
        network_id = input("네트워크 ID (예: eth): ").strip()
        token_input = input("토큰 주소들 (쉼표로 구분): ").strip()
        
        if network_id and token_input:
            token_addresses = [addr.strip() for addr in token_input.split(',')]
            networks_tokens = {network_id: token_addresses}
            
            collector.get_real_time_prices(networks_tokens)
        else:
            print("[오류] 올바른 입력이 필요합니다.")
    
    else:
        print("[오류] 올바른 선택이 아닙니다.")

if __name__ == "__main__":
    main()