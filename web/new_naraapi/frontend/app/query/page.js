'use client';

import { useSearchParams, useRouter } from 'next/navigation';

export default function QueryPage() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const query = searchParams.get('q');
  const provider = searchParams.get('provider') || 'claude';
  
  return (
    <div className="container mx-auto px-4 py-8">
      <div className="max-w-4xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-2xl font-bold">
            {provider === 'claude' ? 'Claude' : 'OpenAI'} 검색 결과
          </h1>
          <button
            onClick={() => router.push('/')}
            className="flex items-center px-4 py-2 text-sm font-medium text-white bg-blue-500 border border-blue-600 rounded-md hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
            </svg>
            홈으로 돌아가기
          </button>
        </div>
        
        {query && (
          <div className="mb-6">
            <h2 className="text-xl font-semibold mb-2">검색어: "{query}"</h2>
          </div>
        )}
        
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="space-y-4">
            <div>
              <h2 className="text-lg font-semibold">검색어 (q):</h2>
              <p className="text-gray-700">{query}</p>
            </div>
            <div>
              <h2 className="text-lg font-semibold">프로바이더 (provider):</h2>
              <p className="text-gray-700">{provider}</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}