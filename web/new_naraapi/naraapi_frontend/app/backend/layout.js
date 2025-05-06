// frontend/app/layout.js
export const metadata = {
  title: 'Next.js 14 + FastAPI 연동',
  description: 'Next.js와 FastAPI 연동 예제',
};

export default function RootLayout({ children }) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}