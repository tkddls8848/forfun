'use client';

import { Suspense } from 'react';
import { useState, useEffect } from 'react';
import Link from 'next/link';
import DataVisualizer from '../../components/DataVisualizer';

// 고정된 더미 데이터
function generateDummyData() {
  return {
    economic: {
      data: [
        { year: '2020', growth: 2.1, unemployment: 3.8 },
        { year: '2021', growth: 3.5, unemployment: 3.6 },
        { year: '2022', growth: 2.8, unemployment: 3.4 },
        { year: '2023', growth: 3.2, unemployment: 3.2 },
        { year: '2024', growth: 3.8, unemployment: 3.0 },
        { year: '2025', growth: 4.2, unemployment: 2.8 },
      ],
      xKey: 'year',
      yKey: 'growth',
      title: '경제 성장률 추이'
    },
    population: {
      data: [
        { region: '서울', population: 9.5, ratio: 18.3 },
        { region: '경기', population: 13.5, ratio: 26.0 },
        { region: '부산', population: 3.3, ratio: 6.4 },
        { region: '인천', population: 2.9, ratio: 5.6 },
        { region: '대구', population: 2.4, ratio: 4.6 },
        { region: '기타', population: 20.1, ratio: 39.1 },
      ],
      xKey: 'region',
      yKey: 'population',
      title: '지역별 인구 분포'
    },
    covid: {
      data: [
        { month: '1월', confirmed: 1200, vaccinated: 85 },
        { month: '2월', confirmed: 980, vaccinated: 87 },
        { month: '3월', confirmed: 750, vaccinated: 89 },
        { month: '4월', confirmed: 520, vaccinated: 91 },
        { month: '5월', confirmed: 380, vaccinated: 93 },
        { month: '6월', confirmed: 210, vaccinated: 95 },
      ],
      xKey: 'month',
      yKey: 'confirmed',
      title: '월별 코로나 확진자 추이'
    },
    budget: {
      data: [
        { category: '교육', value: 25, change: 5.2 },
        { category: '의료', value: 20, change: 3.8 },
        { category: '교통', value: 18, change: -1.2 },
        { category: '환경', value: 15, change: 2.5 },
        { category: '문화', value: 12, change: 4.1 },
        { category: '기타', value: 10, change: 0.8 },
      ],
      xKey: 'category',
      yKey: 'value',
      title: '분야별 예산 배분'
    }
  };
}

// Statistics Content 컴포넌트
function StatisticsContent() {
  const [results, setResults] = useState([]);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);
  const allData = generateDummyData();
  
  // 페이지 로드 시 더미 데이터 설정
  useEffect(() => {
    setLoading(true);
    // API 호출 시뮬레이션
    setTimeout(() => {
      setResults([
        {
          content: "대한민국의 주요 통계 정보를 다양한 차트로 시각화하여 제공합니다. 경제 성장률, 인구 분포, 코로나19 현황, 예산 배분 등의 데이터를 확인할 수 있습니다.",
          model: "Claude 3.7 Sonnet",
          usage: {
            total_tokens: 150,
            prompt_tokens: 50,
            completion_tokens: 100
          }
        }
      ]);
      setLoading(false);
    }, 1000);
  }, []);
  
  return (
    <div className="w-full max-w-6xl">
      <h1 className="text-3xl font-bold mb-6">
        통계 데이터 시각화
      </h1>
      
      <div className="mb-6">
        <h2 className="text-xl font-semibold mb-2">주요 통계 차트</h2>
        <p className="text-gray-600">다양한 분야의 통계 데이터를 시각화하여 보여드립니다.</p>
      </div>
      
      {loading && (
        <div className="text-center py-8">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
          <p className="mt-2">데이터를 로딩하고 있습니다...</p>
        </div>
      )}
      
      {error && (
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          <p className="font-bold">오류 발생</p>
          <p>{error}</p>
        </div>
      )}
      
      {!loading && !error && (
        <div className="space-y-8">
          {/* 설명 섹션 */}
          {results.map((result, index) => (
            <div key={index} className="bg-white rounded-lg shadow-md p-6">
              <div className="prose prose-sm max-w-none">
                <p className="whitespace-pre-wrap">{result.content}</p>
              </div>
            </div>
          ))}
          
          {/* 경제 데이터 시각화 */}
          <div className="bg-white rounded-lg shadow-md p-6">
            <h3 className="text-lg font-semibold mb-4">{allData.economic.title}</h3>
            <DataVisualizer
              data={allData.economic.data}
              type="line"
              xKey={allData.economic.xKey}
              yKey={allData.economic.yKey}
              height={300}
            />
            
            <div className="mt-8">
              <h3 className="text-lg font-semibold mb-4">실업률 추이</h3>
              <DataVisualizer
                data={allData.economic.data}
                type="bar"
                xKey={allData.economic.xKey}
                yKey="unemployment"
                height={300}
              />
            </div>
          </div>
          
          {/* 인구 데이터 시각화 */}
          <div className="bg-white rounded-lg shadow-md p-6">
            <h3 className="text-lg font-semibold mb-4">{allData.population.title}</h3>
            <DataVisualizer
              data={allData.population.data}
              type="bar"
              xKey={allData.population.xKey}
              yKey={allData.population.yKey}
              height={300}
            />
            
            <div className="mt-8">
              <h3 className="text-lg font-semibold mb-4">인구 비율 분포</h3>
              <DataVisualizer
                data={allData.population.data}
                type="pie"
                xKey={allData.population.xKey}
                yKey="ratio"
                height={300}
              />
            </div>
          </div>
          
          {/* 코로나 데이터 시각화 */}
          <div className="bg-white rounded-lg shadow-md p-6">
            <h3 className="text-lg font-semibold mb-4">{allData.covid.title}</h3>
            <DataVisualizer
              data={allData.covid.data}
              type="line"
              xKey={allData.covid.xKey}
              yKey={allData.covid.yKey}
              height={300}
            />
            
            <div className="mt-8">
              <h3 className="text-lg font-semibold mb-4">백신 접종률 추이</h3>
              <DataVisualizer
                data={allData.covid.data}
                type="bar"
                xKey={allData.covid.xKey}
                yKey="vaccinated"
                height={300}
              />
            </div>
          </div>
          
          {/* 예산 데이터 시각화 */}
          <div className="bg-white rounded-lg shadow-md p-6">
            <h3 className="text-lg font-semibold mb-4">{allData.budget.title}</h3>
            <DataVisualizer
              data={allData.budget.data}
              type="pie"
              xKey={allData.budget.xKey}
              yKey={allData.budget.yKey}
              height={300}
            />
            
            <div className="mt-8">
              <h3 className="text-lg font-semibold mb-4">전년대비 변화율</h3>
              <DataVisualizer
                data={allData.budget.data}
                type="bar"
                xKey={allData.budget.xKey}
                yKey="change"
                height={300}
              />
            </div>
          </div>
        </div>
      )}
      
      <div className="mt-8">
        <Link href="/" className="text-blue-600 hover:underline">
          ← 홈으로 돌아가기
        </Link>
      </div>
    </div>
  );
}

// 메인 페이지 컴포넌트 - Suspense로 감싸기
export default function StatisticsPage() {
  return (
    <main className="flex min-h-screen flex-col items-center p-8">
      <Suspense fallback={
        <div className="text-center py-8">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
          <p className="mt-2">페이지 로딩 중...</p>
        </div>
      }>
        <StatisticsContent />
      </Suspense>
    </main>
  );
}