'use client';

import { useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';

export default function TabNavigation() {
  const [isOpen, setIsOpen] = useState(false);
  
  return (
    <>
      <div className="tab">
        <div className="t_about">
          <Link href="#scroll">
            <h3>
              회사소개
              <p>
                20년 이상의 전문 경력을 바탕으로 IT Service <br />
                전문대표기업으로 새롭게 태어났습니다!<br />
                정보통신산업의 든든한 기둥!<br />
                정보강국의 첨병이 되어 대한민국 종합정보통신의 <br />
                살아있는 역사를 바로 세워가겠습니다.
              </p>
            </h3>
          </Link>
        </div>
        <div className="t_infra">
          <Link href="#scroll">
            <h3>IT Infra Service</h3>
          </Link>
        </div>
        <div className="t_product active">
          <Link href="#scroll">
            <h3>Product</h3>
          </Link>
        </div>
      </div>

      <div className="m_tab">
        <div className="t_about">
          <Link href="#scroll">
            <h3>회사소개</h3>
          </Link>
        </div>
        <div className="t_infra">
          <Link href="#scroll">
            <h3>IT Infra Service</h3>
          </Link>
        </div>
        <div className="t_product active">
          <Link href="#scroll">
            <h3>Product</h3>
          </Link>
        </div>
        <i 
          className="drawer_tab" 
          style={{ transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)' }}
          onClick={() => setIsOpen(!isOpen)}
        >
          <Image src="/images/icon/nav/arrow_down.png" alt="Open Tab" width={20} height={12} />
        </i>
      </div>
    </>
  );
}
