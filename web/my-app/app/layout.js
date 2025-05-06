import './globals.css';
import { Inter } from 'next/font/google';

const inter = Inter({ subsets: ['latin'] });

export const metadata = {
  title: '트라이얼정보통신 - Trial Info',
  description: '트라이얼정보통신 - IBM, Lenovo, Dell 등 IT 인프라 솔루션 및 서비스 제공',
};

export default function RootLayout({ children }) {
  return (
    <html lang="ko">
      <body className={inter.className}>
        {children}
      </body>
    </html>
  );
}
