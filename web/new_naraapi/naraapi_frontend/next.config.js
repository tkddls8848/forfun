/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // swcMinify는 Next.js 13부터 기본값이므로 제거
  
  // 외부 공공 API 도메인에 대한 이미지 최적화 허용
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'data.go.kr',
        port: '',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: 'kostat.go.kr',
        port: '',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: 'mof.go.kr',
        port: '',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: 'molit.go.kr',
        port: '',
        pathname: '/**',
      },
      {
        protocol: 'https',
        hostname: 'www.kma.go.kr',
        port: '',
        pathname: '/**',
      },
    ],
    // 이미지 최적화 관련 설정
    formats: ['image/avif', 'image/webp'],
  },
  
  // API 설정은 제거됨 (Next.js 15에서 유효하지 않음)
  // api 옵션 대신, API 라우트 내에서 직접 처리해야 함
  
  // 외부 공공 API에 대한 CORS 프록시 설정
  async rewrites() {
    return [
      {
        // /api/backend/* 경로만 FastAPI로 리다이렉션하도록 변경
        source: '/api/:path*',
        destination: 'http://localhost:8000/:path*', // FastAPI 서버
      },
      {
        source: '/external-api/:path*',
        destination: 'https://api.data.go.kr/:path*',
      },
      {
        source: '/kostat-api/:path*',
        destination: 'https://kosis.kr/openapi/:path*',
      },
    ];
  },
  
  // 환경별 설정
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3000/api',
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000',
  },
  
  // 빌드 최적화 설정
  compiler: {
    // Remove console.log in production
    removeConsole: process.env.NODE_ENV === 'production',
  },
  
  // experimental 옵션들도 Next.js 15에서는 많이 변경됨
  experimental: {
    // 필요한 실험적 기능만 추가
  },
};

module.exports = nextConfig;