// app/publicapis/page.js
'use client';

import { useState } from 'react';
import { filterData, paginate, fetchData, debounce } from '@/utils/utils';
import { publicApiList } from '@/utils/data';
import Link from 'next/link';

export default function PublicApisPage() {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [currentPage, setCurrentPage] = useState(1);

  // 카테고리 필터링
  const categoryFiltered = selectedCategory === 'all' 
    ? publicApiList 
    : publicApiList.filter(api => api.category === selectedCategory);

  // 검색 필터링
  const searchFiltered = filterData(categoryFiltered, searchTerm, ['name', 'description', 'provider']);
  
  // 페이지네이션
  const paginatedApis = paginate(searchFiltered, currentPage, 6);

  // 디바운스된 검색 핸들러
  const debouncedSearch = debounce((value) => {
    setSearchTerm(value);
    setCurrentPage(1);
  }, 300);

  // 카테고리 목록
  const categories = [...new Set(publicApiList.map(api => api.category))];

  return (
    <div className="container mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-8">공공 API 목록</h1>
      
      {/* 검색 및 필터 */}
      <div className="mb-8 flex flex-col md:flex-row gap-4">
        <input
          type="text"
          placeholder="API 이름, 설명, 제공기관으로 검색..."
          className="flex-1 p-3 border rounded-lg"
          onChange={(e) => debouncedSearch(e.target.value)}
        />
        
        <select
          className="p-3 border rounded-lg"
          value={selectedCategory}
          onChange={(e) => {
            setSelectedCategory(e.target.value);
            setCurrentPage(1);
          }}
        >
          <option value="all">모든 카테고리</option>
          {categories.map(category => (
            <option key={category} value={category}>
              {category}
            </option>
          ))}
        </select>
      </div>

      {/* API 카드 그리드 */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
        {paginatedApis.data.map(api => (
          <div key={api.id} className="card hover:shadow-lg transition-shadow">
            <div className="flex justify-between items-start mb-3">
              <h3 className="text-xl font-semibold">{api.name}</h3>
              <span className="bg-blue-100 text-blue-800 text-xs font-medium px-2.5 py-0.5 rounded">
                {api.category}
              </span>
            </div>
            
            <p className="text-gray-600 mb-3">{api.description}</p>
            
            <div className="space-y-2 text-sm">
              <div>
                <span className="font-medium">제공기관:</span> {api.provider}
              </div>
              <div>
                <span className="font-medium">인증방식:</span> {api.authType}
              </div>
              <div>
                <span className="font-medium">사용제한:</span> {api.rateLimit}
              </div>
            </div>
            
            <div className="mt-4 flex gap-2">
              <a
                href={api.documentation}
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-primary text-sm"
              >
                문서 보기
              </a>
              <button className="btn btn-secondary text-sm">
                상세 정보
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* 페이지네이션 */}
      {paginatedApis.totalPages > 1 && (
        <div className="flex justify-center items-center gap-2">
          <button
            className="px-3 py-1 rounded bg-gray-200 disabled:opacity-50"
            disabled={currentPage === 1}
            onClick={() => setCurrentPage(prev => prev - 1)}
          >
            이전
          </button>
          
          <div className="flex gap-1">
            {Array.from({ length: paginatedApis.totalPages }, (_, i) => {
              const page = i + 1;
              const isActive = page === currentPage;
              const shouldShow = 
                page === 1 || 
                page === paginatedApis.totalPages || 
                Math.abs(page - currentPage) <= 1;
              
              if (!shouldShow && page !== 2 && page !== paginatedApis.totalPages - 1) {
                return null;
              }
              
              if (!shouldShow) {
                return <span key={page}>...</span>;
              }
              
              return (
                <button
                  key={page}
                  className={`px-3 py-1 rounded ${
                    isActive ? 'bg-blue-500 text-white' : 'bg-gray-200'
                  }`}
                  onClick={() => setCurrentPage(page)}
                >
                  {page}
                </button>
              );
            })}
          </div>
          
          <button
            className="px-3 py-1 rounded bg-gray-200 disabled:opacity-50"
            disabled={currentPage === paginatedApis.totalPages}
            onClick={() => setCurrentPage(prev => prev + 1)}
          >
            다음
          </button>
        </div>
      )}

      {/* 결과가 없을 때 */}
      {searchFiltered.length === 0 && (
        <div className="text-center py-12 text-gray-500">
          검색 결과가 없습니다.
        </div>
      )}
    </div>
  );
}