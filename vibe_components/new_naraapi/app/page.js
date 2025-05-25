'use client';

import { useState, useEffect } from 'react';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import MainSlider from '@/components/MainSlider';
import TabNavigation from '@/components/TabNavigation';
import InsideTab from '@/components/InsideTab';
import ProductList from '@/components/ProductList';

export default function Home() {
  const [isScrolled, setIsScrolled] = useState(false);
  
  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 100);
    };
    
    window.addEventListener('scroll', handleScroll);
    return () => {
      window.removeEventListener('scroll', handleScroll);
    };
  }, []);

  return (
    <>
      <Header isScrolled={isScrolled} />

      <div id="container">
        <MainSlider />
        <TabNavigation />
        <InsideTab />
        <div className="content_standard">
          <div className="inner">
            <div className="title">
              <h2>IBM 제품<br />소개</h2>
            </div>
            <ProductList />
          </div>
        </div>
      </div>

      <Footer />
    </>
  );
}
