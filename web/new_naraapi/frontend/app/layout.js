import './globals.css';
import Header from './components/Header';
import Navigation from './components/Navigation';
import Footer from './components/Footer';
import Providers from './components/Providers';

export const metadata = {
  title: '공공데이터 포털',
  description: '한국 정부의 OpenAPI 기반 공공데이터 서비스',
};

export default function RootLayout({ children }) {
  return (
    <html lang="ko">
      <body className="bg-white text-black">
        <Providers>
          <div className="flex flex-col min-h-screen max-w-screen-2xl mx-auto px-4 md:px-6 lg:px-8">
            <header className="sticky top-0 z-10 bg-white shadow-md -mx-4 md:-mx-6 lg:-mx-8 px-4 md:px-6 lg:px-8 pt-2">
              <Header />
              <Navigation />
            </header>
            
            <main className="flex-grow py-6">
              {children}
            </main>
            
            <Footer />
          </div>
        </Providers>
      </body>
    </html>
  );
}