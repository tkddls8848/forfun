'use client';

import { useState } from 'react';
import Link from 'next/link';

// Example data - in a real app, this would come from an API
const CATEGORIES = [
  '전체', '행정', '교육', '경제', '고용', '국토관리', '공공안전', '교통',
  '농축수산', '문화관광', '보건의료', '사회복지', '산업고용', '통신', '환경기상'
];

const APIS = [
  {
    id: 'api001',
    title: '기상청 날씨 API',
    description: '전국 날씨 정보를 실시간으로 제공하는 REST API',
    category: '환경기상',
    organization: '기상청',
    version: 'v2.0',
    protocol: 'REST',
    authType: 'API Key',
    status: '운영중',
    calls: 156780,
    updatedAt: '2025-04-15'
  },
  {
    id: 'api002',
    title: '부동산 실거래가 조회 API',
    description: '아파트, 연립/다세대, 단독주택 등의 실거래가 정보 조회',
    category: '국토관리',
    organization: '국토교통부',
    version: 'v1.0',
    protocol: 'REST',
    authType: 'API Key',
    status: '운영중',
    calls: 289456,
    updatedAt: '2025-04-30'
  },
  {
    id: 'api003',
    title: '학교정보 공개 API',
    description: '전국 초중고 및 대학교 정보 조회 서비스',
    category: '교육',
    organization: '교육부',
    version: 'v3.2',
    protocol: 'REST/SOAP',
    authType: 'OAuth 2.0',
    status: '운영중',
    calls: 45672,
    updatedAt: '2025-03-20'
  },
  {
    id: 'api004',
    title: '건강보험 진료정보 API',
    description: '건강보험 진료기록 및 의료기관 정보 제공',
    category: '보건의료',
    organization: '건강보험심사평가원',
    version: 'v2.1',
    protocol: 'REST',
    authType: 'API Key',
    status: '점검중',
    calls: 98234,
    updatedAt: '2025-04-10'
  },
  {
    id: 'api005',
    title: '문화재 정보 API',
    description: '국보, 보물 등 문화재 상세정보 및 위치정보 제공',
    category: '문화관광',
    organization: '문화재청',
    version: 'v1.5',
    protocol: 'REST',
    authType: '없음',
    status: '운영중',
    calls: 12543,
    updatedAt: '2025-03-05'
  },
  {
    id: 'api006',
    title: '교통정보 공개 API',
    description: '실시간 교통상황 및 대중교통 정보 제공',
    category: '교통',
    organization: '한국교통안전공단',
    version: 'v4.0',
    protocol: 'REST/GraphQL',
    authType: 'API Key',
    status: '운영중',
    calls: 345678,
    updatedAt: '2025-04-25'
  }
];

export default function PublicApisPage() {
  const [selectedCategory, setSelectedCategory] = useState('전체');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState('calls');
  const [sortOrder, setSortOrder] = useState('desc');
  const [filterStatus, setFilterStatus] = useState('전체');
  
  // Filter and sort APIs
  const filteredApis = APIS.filter(api => {
    const matchesCategory = selectedCategory === '전체' || api.category === selectedCategory;
    const matchesSearch = api.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         api.description.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesStatus = filterStatus === '전체' || api.status === filterStatus;
    return matchesCategory && matchesSearch && matchesStatus;
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
      <h1 className="text-3xl font-bold mb-8">공공 API 목록</h1>
      
      {/* Search and filter section */}
      <div className="mb-8">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-4">
          <div className="relative">
            <input
              type="text"
              placeholder="API 검색..."
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
              value={filterStatus}
              onChange={(e) => setFilterStatus(e.target.value)}
              className="w-full px-4 py-2 border border-light-gray rounded focus:outline-none focus:ring-2 focus:ring-primary-color"
            >
              <option value="전체">상태: 전체</option>
              <option value="운영중">운영중</option>
              <option value="점검중">점검중</option>
              <option value="중단">중단</option>
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
              <option value="calls-desc">인기순</option>
              <option value="updatedAt-desc">최신순</option>
              <option value="updatedAt-asc">오래된순</option>
              <option value="title-asc">이름순</option>
            </select>
          </div>
        </div>
      </div>
      
      {/* API Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {filteredApis.map(api => (
          <div key={api.id} className="bg-white rounded-lg shadow hover:shadow-lg transition-shadow">
            <div className="p-6">
              <div className="flex justify-between items-start mb-2">
                <h3 className="text-lg font-semibold text-gray-900">
                  <Link href={`/publicapis/${api.id}`} className="hover:text-primary-color">
                    {api.title}
                  </Link>
                </h3>
                <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${
                  api.status === '운영중' ? 'bg-green-100 text-green-800' :
                  api.status === '점검중' ? 'bg-yellow-100 text-yellow-800' :
                  'bg-red-100 text-red-800'
                }`}>
                  {api.status}
                </span>
              </div>
              
              <p className="text-sm text-gray-600 mb-4">{api.description}</p>
              
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-500">제공기관</span>
                  <span className="font-medium">{api.organization}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">버전</span>
                  <span className="font-medium">{api.version}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">프로토콜</span>
                  <span className="font-medium">{api.protocol}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">인증방식</span>
                  <span className="font-medium">{api.authType}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">월간 호출수</span>
                  <span className="font-medium">{api.calls.toLocaleString()}</span>
                </div>
              </div>
              
              <div className="mt-4 pt-4 border-t border-gray-200 flex justify-between items-center">
                <span className="text-xs text-gray-500">
                  업데이트: {api.updatedAt}
                </span>
                <Link 
                  href={`/publicapis/${api.id}`} 
                  className="text-primary-color hover:underline text-sm font-medium"
                >
                  API 문서 보기
                </Link>
              </div>
            </div>
          </div>
        ))}
      </div>
      
      {/* Summary and Pagination */}
      <div className="mt-8 flex justify-between items-center">
        <div className="text-sm text-gray-500">
          총 <span className="font-medium">{filteredApis.length}</span>개의 API
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