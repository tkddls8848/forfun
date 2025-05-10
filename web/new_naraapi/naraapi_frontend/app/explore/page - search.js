'use client';

import { Suspense } from 'react';
import { useState, useEffect } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';

// Search 컴포넌트를 별도로 분리
function SearchContent() {
  const searchParams = useSearchParams();
  const query = searchParams.get('q');
  const provider = searchParams.get('provider') || 'claude';
  const [results, setResults] = useState([]);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (query) {
      setLoading(true);
      setError(null);
      
      // endpoint 설정 확인
      const apiEndpoint = provider === 'claude' ? 'search_claude' : 'search_openapi';
      const url = `/api/search?q=${encodeURIComponent(query)}&endpoint=${apiEndpoint}`;
      
      // 디버깅: URL과 파라미터 출력
      console.log('Request URL:', url);
      console.log('Query:', query);
      console.log('Provider:', provider);
      console.log('Endpoint:', apiEndpoint);
      
      fetch(url)
        .then(response => {
          console.log('Response status:', response.status);
          console.log('Response headers:', response.headers);
          
          // 에러 응답의 경우 본문도 확인
          if (!response.ok) {
            return response.json().then(errorData => {
              console.error('Error response body:', errorData);
              throw new Error(`서버 응답 오류: ${response.status} - ${errorData.detail || '알 수 없는 오류'}`);
            });
          }
          return response.json();
        })
        .then(data => {
          console.log('Success response:', data);
          setResults(data.results);
          setLoading(false);
        })
        .catch(err => {
          console.error('Fetch error:', err);
          setError(err.message);
          setLoading(false);
        });
    }
  }, [query, provider]);
  
  return (
    <div className="w-full max-w-4xl">
      <h1 className="text-3xl font-bold mb-6">
        {provider === 'claude' ? 'Claude' : 'OpenAI'} 검색 결과
      </h1>
      
      {query && (
        <div className="mb-6">
          <h2 className="text-xl font-semibold mb-2">{`검색어: "${query}"`}</h2>
          <p className="text-gray-600">AI 모델: {provider === 'claude' ? 'Claude 3.7 Sonnet' : 'GPT-3.5 Turbo'}</p>
        </div>
      )}
      
      {loading && (
        <div className="text-center py-8">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
          <p className="mt-2">{provider === 'claude' ? 'Claude' : 'OpenAI'}가 답변을 생성하고 있습니다...</p>
        </div>
      )}
      
      {error && (
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          <p className="font-bold">오류 발생</p>
          <p>{error}</p>
        </div>
      )}
      
      {!loading && !error && results.length > 0 && (
        <div className="space-y-6">
          {results.map((result, index) => (
            <div key={index} className="bg-white rounded-lg shadow-md p-6">
              <div className="flex items-center mb-3">
                <span className="text-sm text-gray-500">
                  응답 모델: {result.model}
                </span>
              </div>
              <div className="prose prose-sm max-w-none">
                <p className="whitespace-pre-wrap">{result.content}</p>
              </div>
              
              {result.usage && (
                <div className="mt-4 text-sm text-gray-500">
                  <p>토큰 사용량: {result.usage.total_tokens} (입력: {result.usage.prompt_tokens}, 출력: {result.usage.completion_tokens})</p>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
      
      {!loading && !error && results.length === 0 && query && (
        <p className="text-gray-600">검색 결과가 없습니다.</p>
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
export default function SearchPage() {
  return (
    <main className="flex min-h-screen flex-col items-center p-8">
      <Suspense fallback={
        <div className="text-center py-8">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
          <p className="mt-2">페이지 로딩 중...</p>
        </div>
      }>
        <SearchContent />
      </Suspense>
    </main>
  );
}