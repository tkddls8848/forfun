'use client';

import Link from 'next/link';

// 단순 소개 페이지 컴포넌트
export default function IntroPage() {
  return (
    <main className="flex min-h-screen flex-col items-center p-8">
      <div className="w-full max-w-4xl text-center">
        <h1 className="text-4xl font-bold mb-6">
          AI 모델 검색 서비스
        </h1>

        <p className="text-lg text-gray-700 mb-8">
          다양한 AI 모델을 활용하여 정보를 검색하고 결과를 얻으세요.
          이 페이지는 서비스의 간단한 소개를 제공합니다.
        </p>

        <div className="space-y-4">
          <p className="text-md text-gray-600">
            본 서비스는 Claude 3.7 Sonnet 및 GPT-3.5 Turbo 모델을 지원합니다.
            (※ 현재 이 페이지는 검색 기능을 비활성화하고 있습니다.)
          </p>
          <p className="text-md text-gray-600">
            검색 기능을 사용하려면 적절한 페이지로 이동해주세요.
          </p>
        </div>

        <div className="mt-8">
          <Link href="/" className="text-blue-600 hover:underline text-lg">
            홈으로 돌아가기 (예시 링크)
          </Link>
        </div>
      </div>
    </main>
  );
}