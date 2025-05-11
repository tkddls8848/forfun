'use client';

import { Suspense } from 'react';
import { useState, useEffect, useRef } from 'react';
import Link from 'next/link';

// Query 컴포넌트를 별도로 분리
function QueryContent() {
  const [results, setResults] = useState([]);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(false);
  const [queryData, setQueryData] = useState(null);
  
  // 중복 요청 방지를 위한 ref
  const abortControllerRef = useRef(null);
  const lastQueryRef = useRef(null);
  const isMountedRef = useRef(true);

  useEffect(() => {
    // sessionStorage에서 검색 데이터 가져오기
    const storedData = sessionStorage.getItem('queryData');
    if (storedData) {
      const data = JSON.parse(storedData);
      setQueryData(data);
      // 데이터 사용 후 sessionStorage 클리어
      sessionStorage.removeItem('queryData');
    }
  }, []);

  useEffect(() => {
    // cleanup 함수에서 컴포넌트 언마운트 추적
    return () => {
      isMountedRef.current = false;
      // 언마운트 시 진행 중인 요청 취소
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
      }
    };
  }, []);

  useEffect(() => {
    // queryData가 없거나 이전과 동일한 경우 실행하지 않음
    if (!queryData || lastQueryRef.current === `${queryData.query}-${queryData.provider}`) {
      return;
    }

    const { query, provider } = queryData;

    // 현재 쿼리 저장
    lastQueryRef.current = `${query}-${provider}`;

    // 이전 요청이 있다면 취소
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
    }

    // 새로운 AbortController 생성
    abortControllerRef.current = new AbortController();
    const signal = abortControllerRef.current.signal;

    setLoading(true);
    setError(null);
    
    const apiEndpoint = provider === 'claude' ? 'query_claude' : 'query_openapi';
    
    console.log('Sending POST request');
    console.log('Query:', query);
    console.log('Provider:', provider);
    console.log('Endpoint:', apiEndpoint);
    
    // POST 요청으로 변경
    fetch('/api/query', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        q: query,
        endpoint: apiEndpoint,
        model: 'gpt-3.5-turbo',  // 기본값 설정
        temperature: 0.7,        // 기본값 설정
        max_tokens: 500         // 기본값 설정
      }),
      signal
    })
      .then(response => {
        console.log('Response status:', response.status);
        
        if (!response.ok) {
          return response.json().then(errorData => {
            console.error('Error response body:', errorData);
            throw new Error(`서버 응답 오류: ${response.status} - ${errorData.detail || '알 수 없는 오류'}`);
          });
        }
        return response.json();
      })
      .then(data => {
        // 컴포넌트가 여전히 마운트되어 있는지 확인
        if (isMountedRef.current) {
          console.log('Success response:', data);
          setResults(data.results);
          setLoading(false);
        }
      })
      .catch(err => {
        if (err.name === 'AbortError') {
          console.log('Request was cancelled');
          return;
        }
        // 컴포넌트가 여전히 마운트되어 있는지 확인
        if (isMountedRef.current) {
          console.error('Fetch error:', err);
          setError(err.message);
          setLoading(false);
        }
      });

    // cleanup 함수
    return () => {
      // 컴포넌트 언마운트나 의존성 변경 시 요청 취소
      if (abortControllerRef.current) {
        abortControllerRef.current.abort();
      }
    };
  }, [queryData]);
  
  const query = queryData?.query;
  const provider = queryData?.provider;
  
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
      
      {!loading && !error && results?.length > 0 && (
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
      
      {!loading && !error && (!results || results.length === 0) && query && (
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
export default function QueryPage() {
  return (
    <main className="flex min-h-screen flex-col items-center p-8">
      <Suspense fallback={
        <div className="text-center py-8">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-gray-900"></div>
          <p className="mt-2">페이지 로딩 중...</p>
        </div>
      }>
        <QueryContent />
      </Suspense>
    </main>
  );
}