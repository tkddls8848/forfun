'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';

export default function BackendPage() {
  const [message, setMessage] = useState('로딩 중...');
  const [error, setError] = useState(null);

  useEffect(() => {
    // FastAPI 서버에 직접 요청
    fetch('http://localhost:8000/backend/hello')
      .then(response => {
        if (!response.ok) {
          throw new Error('서버 응답 오류');
        }
        return response.json();
      })
      .then(data => {
        setMessage(data.message);
      })
      .catch(err => {
        setError(err.message);
        setMessage('연결 실패');
      });
  }, []);

  return (
    <main className="flex min-h-screen flex-col items-center justify-between p-24">
      <div className="z-10 max-w-5xl w-full items-center justify-between font-mono text-sm">
        <h1 className="text-4xl font-bold mb-8">Backend 연동 페이지</h1>
        
        <div className="p-4 border rounded-md bg-white shadow-sm mb-6">
          <h2 className="text-xl font-semibold mb-2">FastAPI 서버 응답</h2>
          <p className="text-gray-700">{error ? `오류: ${error}` : message}</p>
        </div>
        
        <div className="mt-4">
          <Link href="/" className="text-blue-500 hover:underline">
            홈으로 돌아가기
          </Link>
        </div>
      </div>
    </main>
  );
}