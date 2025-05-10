// 간단한 로그인 페이지 컴포넌트 (화면만 구현)
import Link from 'next/link';

export default function LoginPage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-8 bg-gray-100">
      <div className="w-full max-w-md bg-white rounded-lg shadow-md p-8">
        <h1 className="text-3xl font-bold text-center mb-6">로그인</h1>

        {/* 에러 메시지 영역 (기능 없이 레이아웃만 유지하거나 삭제) */}
        {/* <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4 text-sm">
          로그인 실패 또는 오류 메시지 표시 영역
        </div> */}

        <form className="space-y-6"> {/* onSubmit 제거 */}
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
              이메일 주소
            </label>
            <input
              type="email"
              id="email"
              className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
              placeholder="example@example.com"
              // value, onChange, required 속성 제거
            />
          </div>

          <div>
            <label htmlFor="password" className="block text-sm font-medium text-gray-700 mb-1">
              비밀번호
            </label>
            <input
              type="password"
              id="password"
              className="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
              placeholder="••••••••"
              // value, onChange, required 속성 제거
            />
          </div>

          <button
            type="submit" // type="submit"은 폼 안에 있으니 유지해도 무방 (실제 제출 기능은 없지만)
            className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
          >
            로그인
          </button>
        </form>

        {/* 필요한 경우 다른 링크 추가 (예: 회원가입, 비밀번호 찾기) */}
        <div className="mt-6 text-center">
          <Link href="/signup" className="text-sm text-blue-600 hover:underline">
            계정이 없으신가요? 회원가입
          </Link>
        </div>
        {/* 홈으로 돌아가는 링크 */}
        <div className="mt-4 text-center">
           <Link href="/" className="text-sm text-gray-600 hover:underline">
             ← 홈으로 돌아가기
           </Link>
        </div>
      </div>
    </main>
  );
}