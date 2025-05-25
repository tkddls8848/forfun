'use client';

import { useState, useEffect } from 'react';
import Image from 'next/image';

export default function MainSlider() {
  const [activeSlide, setActiveSlide] = useState(0);
  const slides = [
    {
      title: '4차 산업혁명의 선두기업',
      image: '/images/photo/slide/slide_01.png'
    },
    {
      title: '뉴노멀시대의 선두기업',
      image: '/images/photo/slide/slide_02.png'
    }
  ];

  useEffect(() => {
    const interval = setInterval(() => {
      setActiveSlide((prev) => (prev + 1) % slides.length);
    }, 5000);
    
    return () => clearInterval(interval);
  }, [slides.length]);

  const goToPrevSlide = () => {
    setActiveSlide((prev) => (prev === 0 ? slides.length - 1 : prev - 1));
  };

  const goToNextSlide = () => {
    setActiveSlide((prev) => (prev + 1) % slides.length);
  };

  return (
    <section className="main_slide">
      <div className="slider">
        <div className="slide_btn">
          <div className="prev" onClick={goToPrevSlide}><a></a></div>
          <div className="next" onClick={goToNextSlide}><a></a></div>
        </div>
        <div className="slide_window">
          <div className="slide_track" style={{ left: 0 }}>
            {slides.map((slide, index) => (
              <div 
                key={index} 
                className="slide" 
                style={{ opacity: activeSlide === index ? 1 : 0 }}
              >
                <h2>{slide.title}</h2>
                <Image 
                  src={slide.image} 
                  alt={`Slide ${index + 1}`} 
                  width={1200} 
                  height={600} 
                  priority={index === 0}
                  style={{
                    width: '100%',
                    height: '100%',
                    objectFit: 'cover'
                  }}
                />
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
