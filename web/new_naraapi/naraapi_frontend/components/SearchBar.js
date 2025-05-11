'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export default function QueryBar() {
  const [query, setQuery] = useState('');
  const [provider, setProvider] = useState('claude'); // 기본값은 'claude'
  const router = useRouter();
  
  const handleQuery = (e) => {
    e.preventDefault();
    
    if (query.trim()) {
      // sessionStorage에 검색 데이터 저장
      sessionStorage.setItem('queryData', JSON.stringify({
        query: query,
        provider: provider
      }));
      
      // 검색 페이지로 이동
      router.push('/query');
    }
  };
  
  return (
    <form onSubmit={handleQuery} className="relative w-full">
      <div className="flex items-center">
        {/* AI 제공자 선택 드롭다운 */}
        <select
          value={provider}
          onChange={(e) => setProvider(e.target.value)}
          className="px-3 py-2 border border-light-gray rounded-l-md bg-white focus:outline-none focus:ring-2 focus:ring-primary-color"
        >
          <option value="claude">Claude</option>
          <option value="openai">OpenAI</option>
        </select>

        {/* 검색 입력 필드 */}
        <div className="relative flex-1">
          <input
            type="text"
            placeholder="데이터 또는 통계 검색..."
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="w-full px-4 py-2 border-l-0 border border-light-gray rounded-r-md focus:outline-none focus:ring-2 focus:ring-primary-color"
          />
          <button
            type="submit"
            className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-500 hover:text-primary-color"
            aria-label="검색"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </button>
        </div>
      </div>
    </form>
  );
}