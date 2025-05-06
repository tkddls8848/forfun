'use client';

import { useState } from 'react';
import Link from 'next/link';

// Example data - in a real app, this would come from an API
const CATEGORIES = [
  '전체', '행정', '교육', '경제', '고용', '국토관리', '공공안전', '교통',
  '농축수산', '문화관광', '보건의료', '사회복지', '산업고용', '통신', '환경기상'
];

const DATASETS = [
  {
    id: 'ds001',
    title: '전국 평균 기온 데이터',
    description: '1970년부터 현재까지의 전국 평균 기온 데이터',
    category: '환경기상',
    organization: '기상청',
    format: 'CSV, JSON',
    updatedAt: '2025-04-15',
    downloads: 1245
  },
  {
    id: 'ds002',
    title: '전국 아파트 실거래가',
    description: '국토교통부 제공 전국 아파트 매매 실거래가 데이터',
    category: '국토관리',
    organization: '국토교통부',
    format: 'CSV, Excel',
    updatedAt: '2025-04-30',
    downloads: 3892
  },
  {
    id: 'ds003',
    title: '전국 대학교 현황',
    description: '전국 대학교 목록, 학과, 학생 수 등 현황 데이터',
    category: '교육',
    organization: '교육부',
    format: 'CSV, JSON',
    updatedAt: '2025-03-20',
    downloads: 876
  },
  {
    id: 'ds004',
    title: '국민건강보험 진료 통계',
    description: '질병 분류별 진료 현황 통계 데이터',
    category: '보건의료',
    organization: '건강보험심사평가원',
    format: 'CSV, Excel, JSON',
    updatedAt: '2025-04-10',
    downloads: 2145
  },
  {
    id: 'ds005',
    title: '전국 문화재 현황',
    description: '국보, 보물, 사적, 명승 등 문화재 정보',
    category: '문화관광',
    organization: '문화재청',
    format: 'CSV, JSON',
    updatedAt: '2025-03-05',
    downloads: 543
  },
  {
    id: 'ds006',
    title: '전국 교통사고 통계',
    description: '지역별, 원인별 교통사고 발생 현황 데이터',
    category: '교통',
    organization: '경찰청',
    format: 'CSV, Excel',
    updatedAt: '2025-04-25',
    downloads: 1678
  }
];

export default function ExplorePage() {
  const [selectedCategory, setSelectedCategory] = useState('전체');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState('updatedAt');
  const [sortOrder, setSortOrder] = useState('desc');
  
  // Filter and sort datasets
  const filteredDatasets = DATASETS.filter(dataset => {
    const matchesCategory = selectedCategory === '전체' || dataset.category === selectedCategory;
    const matchesSearch = dataset.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         dataset.description.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCategory && matchesSearch;
  }).sort((a, b) => {
    if (sortOrder === 'asc') {
      return a[sortBy] > b[sortBy] ? 1 : -1;
    } else {
      return a[sortBy] < b[sortBy] ? 1 : -1;
    }
  });
  
  const handleSort = (field) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      setSortOrder('desc');
    }
  };
  
  return (
    <div className="container mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-8">공공 API</h1>
      
      {/* Search and filter section */}
      <div className="mb-8">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
          <div className="relative">
            <input
              type="text"
              placeholder="데이터셋 검색..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full px-4 py-2 border border-light-gray rounded focus:outline-none focus:ring-2 focus:ring-primary-color"
            />
            <button 
              className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-500"
              aria-label="검색"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </button>
          </div>
          
          <div>
            <select
              value={selectedCategory}
              onChange={(e) => setSelectedCategory(e.target.value)}
              className="w-full px-4 py-2 border border-light-gray rounded focus:outline-none focus:ring-2 focus:ring-primary-color"
            >
              {CATEGORIES.map(category => (
                <option key={category} value={category}>
                  {category}
                </option>
              ))}
            </select>
          </div>
          
          <div>
            <select
              value={`${sortBy}-${sortOrder}`}
              onChange={(e) => {
                const [field, order] = e.target.value.split('-');
                setSortBy(field);
                setSortOrder(order);
              }}
              className="w-full px-4 py-2 border border-light-gray rounded focus:outline-none focus:ring-2 focus:ring-primary-color"
            >
              <option value="updatedAt-desc">최신순</option>
              <option value="updatedAt-asc">오래된순</option>
              <option value="downloads-desc">인기순</option>
              <option value="title-asc">이름순</option>
            </select>
          </div>
        </div>
      </div>
      
      {/* Results */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  데이터셋
                </th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  분류
                </th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  제공기관
                </th>
                <th 
                  scope="col" 
                  className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer"
                  onClick={() => handleSort('updatedAt')}
                >
                  <div className="flex items-center">
                    <span>업데이트</span>
                    {sortBy === 'updatedAt' && (
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 ml-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        {sortOrder === 'asc' ? (
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
                        ) : (
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                        )}
                      </svg>
                    )}
                  </div>
                </th>
                <th 
                  scope="col" 
                  className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider cursor-pointer"
                  onClick={() => handleSort('downloads')}
                >
                  <div className="flex items-center">
                    <span>다운로드</span>
                    {sortBy === 'downloads' && (
                      <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 ml-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        {sortOrder === 'asc' ? (
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
                        ) : (
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                        )}
                      </svg>
                    )}
                  </div>
                </th>
                <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  형식
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredDatasets.map(dataset => (
                <tr key={dataset.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4">
                    <div>
                      <Link href={`/datasets/${dataset.id}`} className="text-primary-color hover:underline font-medium">
                        {dataset.title}
                      </Link>
                      <p className="text-sm text-gray-500 mt-1">{dataset.description}</p>
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm">
                    <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-primary-color bg-opacity-10 text-primary-color">
                      {dataset.category}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {dataset.organization}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {dataset.updatedAt}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {dataset.downloads.toLocaleString()}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {dataset.format}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      
      {/* Pagination */}
      <div className="flex justify-between items-center mt-6">
        <div className="text-sm text-gray-500">
          총 <span className="font-medium">{filteredDatasets.length}</span>개의 데이터셋
        </div>
        <div className="flex space-x-2">
          <button className="px-3 py-1 border border-light-gray rounded text-sm disabled:opacity-50">
            이전
          </button>
          <button className="px-3 py-1 bg-primary-color text-white rounded text-sm">
            1
          </button>
          <button className="px-3 py-1 border border-light-gray rounded text-sm">
            다음
          </button>
        </div>
      </div>
    </div>
  );
}