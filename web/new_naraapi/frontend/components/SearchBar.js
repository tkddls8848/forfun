'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export default function SearchBar() {
  const [query, setQuery] = useState('');
  const [provider, setProvider] = useState('claude');
  const router = useRouter();
  
  const handleSubmit = (e) => {
    e.preventDefault();
    if (!query.trim()) return;
    
    router.push(`/query?q=${encodeURIComponent(query)}&provider=${provider}`);
  };
  
  return (
    <form onSubmit={handleSubmit} className="relative w-full">
      <div className="flex items-center">
        <select
          value={provider}
          onChange={(e) => setProvider(e.target.value)}
          className="px-3 py-2 border border-gray-300 rounded-l-md bg-white focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="claude">Claude</option>
          <option value="openai">OpenAI</option>
        </select>

        <input
          type="text"
          placeholder="질문을 입력하세요..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="w-full px-4 py-2 border-l-0 border border-gray-300 rounded-r-md focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        <button
          type="submit"
          className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-500 hover:text-blue-500"
        >
          <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </button>
      </div>
    </form>
  );
}