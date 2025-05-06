/** @type {import('next').NextConfig} */
const nextConfig = {
    reactStrictMode: true,
    swcMinify: true,
    
    // Node.js 22와의 호환성을 위한 설정
    experimental: {
      // Node.js 22에서 지원되는 최신 기능 활성화
      serverActions: true,
      serverComponentsExternalPackages: [],
    },
    
    // 외부 공공 API 도메인에 대한 이미지 최적화 허용
    images: {
      domains: [
        'www.data.go.kr',
        'www.kostat.go.kr',
        'www.mof.go.kr',
        'www.molit.go.kr',
        'www.kma.go.kr'
      ],
      // 이미지 최적화 관련 설정
      formats: ['image/avif', 'image/webp'],
    },
    
    // API 라우트 타임아웃 설정
    api: {
      responseLimit: '8mb',
      bodyParser: {
        sizeLimit: '1mb',
      },
    },
    
    // 외부 공공 API에 대한 CORS 프록시 설정
    async rewrites() {
      return [
        {
          // /api/backend/* 경로만 FastAPI로 리다이렉션하도록 변경
          // 이렇게 하면 app/backend/page.js와 충돌하지 않음
          source: '/api/backend/:path*',
          destination: 'http://localhost:8000/backend/:path*', // FastAPI 서버 주소
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
  };
  
  module.exports = nextConfig;