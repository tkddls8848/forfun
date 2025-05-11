// app/statistics/page.js
'use client';

import { useState, useEffect } from 'react';
import DataVisualizer from '@/components/DataVisualizer';
import { statisticsData } from '@/utils/data';
import { formatNumber, formatCurrency } from '@/utils/utils';

export default function StatisticsPage() {
  const [selectedCategory, setSelectedCategory] = useState('economic');
  const [chartData, setChartData] = useState([]);
  const [summaryStats, setSummaryStats] = useState(null);

  // 카테고리별 데이터 처리
  useEffect(() => {
    switch (selectedCategory) {
      case 'economic':
        // 경제 지표 데이터 처리
        const economicChartData = statisticsData.economicIndicators.map(item => ({
          name: item.year.toString(),
          GDP: item.gdp,
          '성장률': item.growth,
          '실업률': item.unemployment,
          '인플레이션': item.inflation
        }));
        setChartData(economicChartData);
        
        // 경제 통계 요약
        const latestEconomic = statisticsData.economicIndicators[0];
        setSummaryStats({
          gdp: formatCurrency(latestEconomic.gdp * 1000000000),
          growth: `${latestEconomic.growth}%`,
          unemployment: `${latestEconomic.unemployment}%`,
          inflation: `${latestEconomic.inflation}%`
        });
        break;

      case 'population':
        // 인구 통계 데이터 처리
        const populationChartData = statisticsData.populationData.map(item => ({
          name: item.region.replace('특별시', '').replace('광역시', '').replace('특별자치시', ''),
          '인구수': item.population / 10000, // 만명 단위
          '인구밀도': item.density,
          '성장률': item.growthRate
        }));
        setChartData(populationChartData);
        
        // 인구 통계 요약
        const totalPopulation = statisticsData.populationData.reduce((sum, item) => sum + item.population, 0);
        const avgDensity = statisticsData.populationData.reduce((sum, item) => sum + item.density, 0) / statisticsData.populationData.length;
        setSummaryStats({
          totalPopulation: formatNumber(totalPopulation),
          avgDensity: formatNumber(Math.round(avgDensity)),
          highestGrowth: `${Math.max(...statisticsData.populationData.map(item => item.growthRate))}%`,
          regions: statisticsData.populationData.length
        });
        break;

      case 'realestate':
        // 부동산 데이터 처리
        const realEstateChartData = statisticsData.realEstateData.map(item => ({
          name: item.month.substring(5), // YYYY-MM에서 MM만 추출
          '아파트': item.apartment,
          '단독주택': item.house,
          '오피스': item.office,
          '상가': item.commercial
        }));
        setChartData(realEstateChartData);
        
        // 부동산 통계 요약
        const latestRealEstate = statisticsData.realEstateData[statisticsData.realEstateData.length - 1];
        setSummaryStats({
          avgApartment: formatNumber(Math.round(statisticsData.realEstateData.reduce((sum, item) => sum + item.apartment, 0) / statisticsData.realEstateData.length)),
          latestApartment: formatNumber(latestRealEstate.apartment),
          trend: latestRealEstate.apartment > statisticsData.realEstateData[0].apartment ? '상승' : '하락',
          dataPoints: statisticsData.realEstateData.length
        });
        break;

      default:
        setChartData([]);
        setSummaryStats(null);
    }
  }, [selectedCategory]);

  return (
    <div className="container mx-auto px-4 py-8 mt-4 pt-5">
      <h1 className="text-3xl font-bold mb-8">통계 정보</h1>
      
      {/* 카테고리 탭 */}
      <div className="border-b border-gray-200 mb-8">
        <nav className="-mb-px flex space-x-8">
          <button
            className={`py-2 px-1 border-b-2 font-medium text-sm ${
              selectedCategory === 'economic' 
                ? 'border-blue-500 text-blue-600' 
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
            onClick={() => setSelectedCategory('economic')}
          >
            경제 지표
          </button>
          <button
            className={`py-2 px-1 border-b-2 font-medium text-sm ${
              selectedCategory === 'population' 
                ? 'border-blue-500 text-blue-600' 
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
            onClick={() => setSelectedCategory('population')}
          >
            인구 통계
          </button>
          <button
            className={`py-2 px-1 border-b-2 font-medium text-sm ${
              selectedCategory === 'realestate' 
                ? 'border-blue-500 text-blue-600' 
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
            onClick={() => setSelectedCategory('realestate')}
          >
            부동산
          </button>
        </nav>
      </div>

      {/* 통계 요약 카드 */}
      {summaryStats && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
          {selectedCategory === 'economic' && (
            <>
              <div className="bg-blue-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">GDP (2024)</h3>
                <p className="text-2xl font-bold text-blue-600">{summaryStats.gdp}</p>
              </div>
              <div className="bg-green-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">경제성장률</h3>
                <p className="text-2xl font-bold text-green-600">{summaryStats.growth}</p>
              </div>
              <div className="bg-yellow-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">실업률</h3>
                <p className="text-2xl font-bold text-yellow-600">{summaryStats.unemployment}</p>
              </div>
              <div className="bg-red-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">인플레이션</h3>
                <p className="text-2xl font-bold text-red-600">{summaryStats.inflation}</p>
              </div>
            </>
          )}
          
          {selectedCategory === 'population' && (
            <>
              <div className="bg-blue-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">총 인구</h3>
                <p className="text-2xl font-bold text-blue-600">{summaryStats.totalPopulation}명</p>
              </div>
              <div className="bg-green-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">평균 인구밀도</h3>
                <p className="text-2xl font-bold text-green-600">{summaryStats.avgDensity}명/㎢</p>
              </div>
              <div className="bg-yellow-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">최고 성장률</h3>
                <p className="text-2xl font-bold text-yellow-600">{summaryStats.highestGrowth}</p>
              </div>
              <div className="bg-purple-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">지역 수</h3>
                <p className="text-2xl font-bold text-purple-600">{summaryStats.regions}개</p>
              </div>
            </>
          )}
          
          {selectedCategory === 'realestate' && (
            <>
              <div className="bg-blue-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">아파트 평균가</h3>
                <p className="text-2xl font-bold text-blue-600">{summaryStats.avgApartment}</p>
              </div>
              <div className="bg-green-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">최신 아파트가</h3>
                <p className="text-2xl font-bold text-green-600">{summaryStats.latestApartment}</p>
              </div>
              <div className="bg-yellow-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">가격 추세</h3>
                <p className="text-2xl font-bold text-yellow-600">{summaryStats.trend}</p>
              </div>
              <div className="bg-purple-50 rounded-lg p-4">
                <h3 className="text-sm font-medium text-gray-600">데이터 포인트</h3>
                <p className="text-2xl font-bold text-purple-600">{summaryStats.dataPoints}개월</p>
              </div>
            </>
          )}
        </div>
      )}

      {/* 차트 영역 */}
      <div className="bg-white rounded-lg shadow-lg p-6 mb-8">
        <h2 className="text-xl font-semibold mb-4">
          {selectedCategory === 'economic' && '경제 지표 추이'}
          {selectedCategory === 'population' && '지역별 인구 통계'}
          {selectedCategory === 'realestate' && '부동산 가격 동향'}
        </h2>
        
        {selectedCategory === 'economic' && (
          <div className="space-y-8">
            <div>
              <h3 className="text-lg font-medium mb-4">GDP 추이</h3>
              <DataVisualizer 
                data={chartData} 
                type="line" 
                xKey="name" 
                yKey="GDP" 
                height={350}
              />
            </div>
            <div>
              <h3 className="text-lg font-medium mb-4">경제 지표 비교</h3>
              <DataVisualizer 
                data={chartData} 
                type="bar" 
                xKey="name" 
                yKey="성장률" 
                height={350}
              />
            </div>
          </div>
        )}
        
        {selectedCategory === 'population' && (
          <div className="space-y-8">
            <div>
              <h3 className="text-lg font-medium mb-4">지역별 인구 분포</h3>
              <DataVisualizer 
                data={chartData} 
                type="bar" 
                xKey="name" 
                yKey="인구수" 
                height={350}
              />
            </div>
            <div>
              <h3 className="text-lg font-medium mb-4">인구 성장률</h3>
              <DataVisualizer 
                data={chartData} 
                type="line" 
                xKey="name" 
                yKey="성장률" 
                height={350}
              />
            </div>
            <div>
              <h3 className="text-lg font-medium mb-4">인구 비율</h3>
              <DataVisualizer 
                data={chartData} 
                type="pie" 
                xKey="name" 
                yKey="인구수" 
                height={350}
              />
            </div>
          </div>
        )}
        
        {selectedCategory === 'realestate' && (
          <div className="space-y-8">
            <div>
              <h3 className="text-lg font-medium mb-4">부동산 가격 추이</h3>
              <DataVisualizer 
                data={chartData} 
                type="line" 
                xKey="name" 
                yKey="아파트" 
                height={350}
              />
            </div>
            <div>
              <h3 className="text-lg font-medium mb-4">부동산 유형별 비교</h3>
              <DataVisualizer 
                data={chartData} 
                type="bar" 
                xKey="name" 
                yKey="아파트" 
                height={350}
              />
            </div>
          </div>
        )}
      </div>

      {/* 데이터 테이블 */}
      <div className="bg-white rounded-lg shadow-lg p-6">
        <h2 className="text-xl font-semibold mb-4">상세 데이터</h2>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                {selectedCategory === 'economic' && (
                  <>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">연도</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">GDP</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">성장률</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">실업률</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">인플레이션</th>
                  </>
                )}
                {selectedCategory === 'population' && (
                  <>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">지역</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">인구수</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">인구밀도</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">성장률</th>
                  </>
                )}
                {selectedCategory === 'realestate' && (
                  <>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">월</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">아파트</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">단독주택</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">오피스</th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">상가</th>
                  </>
                )}
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {selectedCategory === 'economic' && statisticsData.economicIndicators.map((item, index) => (
                <tr key={index} className={index % 2 === 0 ? 'bg-white' : 'bg-gray-50'}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{item.year}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatCurrency(item.gdp * 1000000000)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{item.growth}%</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{item.unemployment}%</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{item.inflation}%</td>
                </tr>
              ))}
              
              {selectedCategory === 'population' && statisticsData.populationData.map((item, index) => (
                <tr key={index} className={index % 2 === 0 ? 'bg-white' : 'bg-gray-50'}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{item.region}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatNumber(item.population)}명</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatNumber(item.density)}명/㎢</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <span className={item.growthRate > 0 ? 'text-green-600' : 'text-red-600'}>
                      {item.growthRate}%
                    </span>
                  </td>
                </tr>
              ))}
              
              {selectedCategory === 'realestate' && statisticsData.realEstateData.map((item, index) => (
                <tr key={index} className={index % 2 === 0 ? 'bg-white' : 'bg-gray-50'}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{item.month}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatNumber(item.apartment)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatNumber(item.house)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatNumber(item.office)}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{formatNumber(item.commercial)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}