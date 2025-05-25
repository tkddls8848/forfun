import Link from 'next/link';

export default function Footer() {
  return (
    <footer className="bg-secondary-color py-8 border-t border-light-gray">
      <div className="container mx-auto px-4">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-8">
          <div>
            <h3 className="text-lg font-semibold mb-4">공공데이터 포털</h3>
            <p className="text-sm text-gray-600">
              한국 정부의 OpenAPI 기반으로 공공데이터를 제공하는 플랫폼입니다. 다양한 통계 자료와 데이터셋을 탐색하고 활용하세요.
            </p>
          </div>

          <div>
            <h3 className="text-lg font-semibold mb-4">둘러보기</h3>
            <ul className="space-y-2">
              <li>
                <Link href="/dev/statistics" className="text-sm text-gray-600 hover:text-primary-color">
                  통계 분석
                </Link>
              </li>
              <li>
                <Link href="/dev/datasets" className="text-sm text-gray-600 hover:text-primary-color">
                  데이터 탐색
                </Link>
              </li>
              <li>
                <Link href="/dev/publicapis" className="text-sm text-gray-600 hover:text-primary-color">
                  공공 API 문서
                </Link>
              </li>
            </ul>
          </div>
          
          <div>
            <h3 className="text-lg font-semibold mb-4">지원</h3>
            <ul className="space-y-2">
              <li>
                <Link href="/dev/help" className="text-sm text-gray-600 hover:text-primary-color">
                  도움말
                </Link>
              </li>
              <li>
                <Link href="/dev/faq" className="text-sm text-gray-600 hover:text-primary-color">
                  자주 묻는 질문
                </Link>
              </li>
              <li>
                <Link href="/dev/contact" className="text-sm text-gray-600 hover:text-primary-color">
                  문의하기
                </Link>
              </li>
            </ul>
          </div>
          
          <div>
            <h3 className="text-lg font-semibold mb-4">소셜 미디어</h3>
            <div className="flex space-x-4">
              <a href="#" className="text-gray-600 hover:text-primary-color">
                <span className="sr-only">Facebook</span>
                {/* Facebook 아이콘 */}
              </a>
              <a href="#" className="text-gray-600 hover:text-primary-color">
                <span className="sr-only">Twitter</span>
                {/* Twitter 아이콘 */}
              </a>
              <a href="#" className="text-gray-600 hover:text-primary-color">
                <span className="sr-only">YouTube</span>
                {/* YouTube 아이콘 */}
              </a>
            </div>
          </div>
        </div>
        
        <div className="mt-8 pt-8 border-t border-gray-200">
          <p className="text-sm text-gray-600 text-center">
            © 2025 공공데이터 포털. Developed by PSI
          </p>
        </div>
      </div>
    </footer>
  );
}