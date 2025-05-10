import './globals.css';
import Header from '../components/Header';
import Navigation from '../components/Navigation';
import Footer from '../components/Footer';

export const metadata = {
  title: '공공데이터 포털',
  description: '한국 정부의 OpenAPI 기반 공공데이터 서비스',
};

export default function RootLayout({ children }) {
  return (
    <html lang="ko">
      <body className="bg-white text-black">
        <div className="flex flex-col min-h-screen">
          <header className="sticky top-0 z-10 bg-white shadow-md pt-2">
            <Header />
            <Navigation />
          </header>

          <main className="flex-grow">
            {children}
          </main>

          <Footer />
        </div>
      </body>
    </html>
  );
}