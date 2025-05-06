'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export default function SearchBar() {
  const [query, setQuery] = useState('');
  const router = useRouter();
  
  const handleSearch = (e) => {
    e.preventDefault();
    
    if (query.trim()) {
      router.push(`/search?q=${encodeURIComponent(query)}`);
    }
  };
  
  return (
    <form onSubmit={handleSearch} className="relative w-full">
      <input
        type="text"
        placeholder="데이터 또는 통계 검색..."
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        className="w-full px-4 py-2 border border-light-gray rounded-full focus:outline-none focus:ring-2 focus:ring-primary-color"
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
    </form>
  );
}