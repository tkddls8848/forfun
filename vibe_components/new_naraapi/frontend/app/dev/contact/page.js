'use client';

import Link from 'next/link';

// 단순 소개 페이지 컴포넌트 (연락처 추가)
export default function IntroPage() {
  return (
    <main className="flex min-h-screen flex-col items-center p-8">
      <div className="w-full max-w-4xl text-center">
        {/* 연락처 섹션 추가 */}
        <div className="mt-8 pt-8">
          <h2 className="text-2xl font-semibold mb-4">문의 사항</h2>
          <p className="text-md text-gray-700">
            서비스에 대해 궁금한 점이 있으시면 다음 주소로 연락주세요:
          </p>
          <p className="text-lg text-blue-600 hover:underline mt-2">
            <a href="mailto:your.email@example.com">your.email@example.com</a> {/* 여기에 실제 이메일 주소를 넣어주세요 */}
          </p>
          {/* 추가적인 연락처 정보가 있다면 여기에 추가 */}
          {/* <p className="text-md text-gray-700 mt-2">전화: 0XX-XXXX-XXXX</p> */}
        </div>

        <div className="mt-8">
          <Link href="/" className="text-blue-600 hover:underline text-lg">
            ← 홈으로 돌아가기 (예시 링크)
          </Link>
        </div>
      </div>
    </main>
  );
}