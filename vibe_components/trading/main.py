import asyncio
import aiohttp
import time
import logging
from typing import Dict, Optional, Tuple
from dataclasses import dataclass
import json

# 로깅 설정
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class PriceData:
    exchange: str
    symbol: str
    bid: float  # 매수 호가
    ask: float  # 매도 호가
    timestamp: float

@dataclass
class ArbitrageOpportunity:
    buy_exchange: str
    sell_exchange: str
    symbol: str
    buy_price: float
    sell_price: float
    profit_rate: float
    timestamp: float

class ArbitrageBot:
    def __init__(self):
        self.session = None
        self.running = False
        
        # 설정값
        self.MIN_PROFIT_RATE = 0.005  # 최소 수익률 0.5%
        self.MAX_TRADE_AMOUNT = 1000  # 최대 거래금액 (USDT)
        self.TRADE_SYMBOLS = ['USDT', 'USDC']
        
        # API 엔드포인트
        self.UPBIT_TICKER_URL = "https://api.upbit.com/v1/ticker"
        self.BINANCE_TICKER_URL = "https://api.binance.com/api/v3/ticker/bookTicker"
        
        # 가격 데이터 저장
        self.price_data: Dict[str, Dict[str, PriceData]] = {}
        
    async def start(self):
        """봇 시작"""
        self.session = aiohttp.ClientSession()
        self.running = True
        logger.info("아비트라지 봇이 시작되었습니다.")
        
        try:
            await self.run_monitoring_loop()
        except KeyboardInterrupt:
            logger.info("봇이 중단되었습니다.")
        finally:
            await self.stop()
    
    async def stop(self):
        """봇 종료"""
        self.running = False
        if self.session:
            await self.session.close()
        logger.info("봇이 종료되었습니다.")
    
    async def get_upbit_prices(self) -> Dict[str, PriceData]:
        """업비트 가격 정보 조회"""
        try:
            # USDT/KRW, USDC/KRW 조회
            symbols = "KRW-USDT,KRW-USDC"
            url = f"{self.UPBIT_TICKER_URL}?markets={symbols}"
            
            async with self.session.get(url) as response:
                if response.status == 200:
                    data = await response.json()
                    prices = {}
                    
                    for item in data:
                        market = item['market']
                        symbol = market.split('-')[1]  # KRW-USDT -> USDT
                        
                        prices[symbol] = PriceData(
                            exchange='upbit',
                            symbol=symbol,
                            bid=float(item['trade_price']),  # 현재가를 bid/ask로 사용
                            ask=float(item['trade_price']),
                            timestamp=time.time()
                        )
                    
                    return prices
                else:
                    logger.error(f"업비트 API 오류: {response.status}")
                    return {}
        except Exception as e:
            logger.error(f"업비트 가격 조회 오류: {e}")
            return {}
    
    async def get_binance_prices(self) -> Dict[str, PriceData]:
        """바이낸스 가격 정보 조회"""
        try:
            # USDT/BUSD, USDC/BUSD 조회 (스테이블코인 쌍)
            symbols = ['USDTBUSD', 'USDCBUSD']
            prices = {}
            
            for symbol in symbols:
                url = f"{self.BINANCE_TICKER_URL}?symbol={symbol}"
                
                async with self.session.get(url) as response:
                    if response.status == 200:
                        data = await response.json()
                        base_symbol = symbol[:4]  # USDTBUSD -> USDT
                        
                        prices[base_symbol] = PriceData(
                            exchange='binance',
                            symbol=base_symbol,
                            bid=float(data['bidPrice']),
                            ask=float(data['askPrice']),
                            timestamp=time.time()
                        )
                    else:
                        logger.error(f"바이낸스 API 오류 ({symbol}): {response.status}")
            
            return prices
        except Exception as e:
            logger.error(f"바이낸스 가격 조회 오류: {e}")
            return {}
    
    def calculate_arbitrage_opportunity(self, upbit_price: PriceData, binance_price: PriceData) -> Optional[ArbitrageOpportunity]:
        """아비트라지 기회 계산"""
        # 업비트에서 사고 바이낸스에서 파는 경우
        profit_rate_1 = (binance_price.bid - upbit_price.ask) / upbit_price.ask
        
        # 바이낸스에서 사고 업비트에서 파는 경우  
        profit_rate_2 = (upbit_price.bid - binance_price.ask) / binance_price.ask
        
        # 더 수익성이 높은 방향 선택
        if profit_rate_1 > profit_rate_2 and profit_rate_1 > self.MIN_PROFIT_RATE:
            return ArbitrageOpportunity(
                buy_exchange='upbit',
                sell_exchange='binance',
                symbol=upbit_price.symbol,
                buy_price=upbit_price.ask,
                sell_price=binance_price.bid,
                profit_rate=profit_rate_1,
                timestamp=time.time()
            )
        elif profit_rate_2 > self.MIN_PROFIT_RATE:
            return ArbitrageOpportunity(
                buy_exchange='binance',
                sell_exchange='upbit',
                symbol=upbit_price.symbol,
                buy_price=binance_price.ask,
                sell_price=upbit_price.bid,
                profit_rate=profit_rate_2,
                timestamp=time.time()
            )
        
        return None
    
    async def execute_arbitrage(self, opportunity: ArbitrageOpportunity):
        """아비트라지 실행 (시뮬레이션)"""
        # 실제 거래 실행 코드는 주석 처리 (안전을 위해)
        # 실제 사용시에는 각 거래소의 API 키와 거래 함수를 구현해야 함
        
        logger.info("=" * 50)
        logger.info("🚨 아비트라지 기회 발견!")
        logger.info(f"코인: {opportunity.symbol}")
        logger.info(f"매수 거래소: {opportunity.buy_exchange} (가격: {opportunity.buy_price:.4f})")
        logger.info(f"매도 거래소: {opportunity.sell_exchange} (가격: {opportunity.sell_price:.4f})")
        logger.info(f"예상 수익률: {opportunity.profit_rate:.2%}")
        logger.info(f"예상 수익: {opportunity.profit_rate * self.MAX_TRADE_AMOUNT:.2f} USDT")
        
        # 실제 거래 실행은 여기에 구현
        # await self.place_buy_order(opportunity.buy_exchange, opportunity.symbol, self.MAX_TRADE_AMOUNT)
        # await self.place_sell_order(opportunity.sell_exchange, opportunity.symbol, self.MAX_TRADE_AMOUNT)
        
        logger.info("⚠️ 시뮬레이션 모드: 실제 거래는 실행되지 않음")
        logger.info("=" * 50)
    
    def log_price_info(self):
        """현재 가격 정보 로깅"""
        logger.info("-" * 30)
        for symbol in self.TRADE_SYMBOLS:
            if symbol in self.price_data.get('upbit', {}) and symbol in self.price_data.get('binance', {}):
                upbit_price = self.price_data['upbit'][symbol]
                binance_price = self.price_data['binance'][symbol]
                
                logger.info(f"{symbol} - 업비트: {upbit_price.bid:.4f}, 바이낸스: {binance_price.bid:.4f}")
    
    async def run_monitoring_loop(self):
        """메인 모니터링 루프"""
        while self.running:
            try:
                # 가격 정보 수집
                upbit_prices = await self.get_upbit_prices()
                binance_prices = await self.get_binance_prices()
                
                # 가격 데이터 저장
                self.price_data['upbit'] = upbit_prices
                self.price_data['binance'] = binance_prices
                
                # 가격 정보 로깅
                self.log_price_info()
                
                # 아비트라지 기회 탐색
                for symbol in self.TRADE_SYMBOLS:
                    if symbol in upbit_prices and symbol in binance_prices:
                        opportunity = self.calculate_arbitrage_opportunity(
                            upbit_prices[symbol], 
                            binance_prices[symbol]
                        )
                        
                        if opportunity:
                            await self.execute_arbitrage(opportunity)
                
                # 5초 대기
                await asyncio.sleep(5)
                
            except Exception as e:
                logger.error(f"모니터링 루프 오류: {e}")
                await asyncio.sleep(10)

# 실행 함수
async def main():
    """
    ⚠️ 주의사항:
    1. 이 코드는 교육/시뮬레이션 목적입니다
    2. 실제 거래 전에 충분한 테스트가 필요합니다
    3. API 키 설정과 거래 함수 구현이 필요합니다
    4. 거래소별 수수료, 출금 수수료를 고려해야 합니다
    5. 네트워크 지연, 슬리피지 등의 리스크가 있습니다
    """
    
    print("업비트-바이낸스 USDT/USDC 아비트라지 봇")
    print("⚠️ 시뮬레이션 모드로 실행됩니다")
    print("-" * 50)
    
    bot = ArbitrageBot()
    await bot.start()

if __name__ == "__main__":
    # 봇 실행
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n봇이 중단되었습니다.")

# 필요한 패키지 설치 명령어:
# pip install aiohttp asyncio