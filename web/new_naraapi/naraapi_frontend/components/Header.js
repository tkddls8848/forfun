import Link from 'next/link';

export default function Header() {
  return (
    <div className="container mx-auto py-4 px-4 flex items-center justify-between">
      <div className="flex items-center">
        <Link href="/" className="flex items-center">
          <span className="text-2xl font-bold text-primary-color">공공데이터 포털</span>
        </Link>
      </div>
      
      <div className="flex items-center space-x-4">
        <Link href="/dev/about" className="text-sm hover:text-primary-color">
          소개
        </Link>
        <Link href="/dev/contact" className="text-sm hover:text-primary-color">
          문의하기
        </Link>
        <Link href="/dev/login" className="btn btn-primary text-sm">
          로그인
        </Link>
      </div>
    </div>
  );
}