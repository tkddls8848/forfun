/** @type {import('next').NextConfig} */
const nextConfig = {
  // 개발 환경에서의 이중 렌더링 문제를 일시적으로 해결하기 위해 false로 설정
  // 프로덕션에서는 true로 다시 변경하는 것을 권장합니다
  reactStrictMode: false,
  
  // Node.js 경고 무시
  webpack: (config, { isServer }) => {
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        util: false,
      };
    }
    return config;
  },
  
  // 나머지 설정은 동일하게 유지
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
    formats: ['image/avif', 'image/webp'],
    domains: ['images.unsplash.com'],
  },
  
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: 'http://localhost:8000/:path*',
      },
      {
        source: '/query/:path*',
        destination: 'http://localhost:8000/query/:path*',
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
  
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000',
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000',
  },
  
  compiler: {
    removeConsole: process.env.NODE_ENV === 'production',
  },
  
  experimental: {
    // 필요한 실험적 기능만 추가
  },
};

module.exports = nextConfig;