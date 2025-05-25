'use client';

import { useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';

export default function Footer() {
  const [expandedSection, setExpandedSection] = useState(null);

  const toggleSection = (section) => {
    if (expandedSection === section) {
      setExpandedSection(null);
    } else {
      setExpandedSection(section);
    }
  };

  return (
    <footer>
      <div className="inner">
        <h5>
          <Link href="/">
            <Image src="/images/logo/logo_wt.svg" alt="White Logo" width={150} height={40} />
          </Link>
        </h5>
        <nav className="footer_nav">
          <ul>
            <li>
              <dl className={expandedSection === 'about' ? 'expanded' : ''}>
                <i onClick={() => toggleSection('about')}></i>
                <dt>About Us</dt>
                <dd><Link href="#scroll">회사개요</Link></dd>
                <dd><Link href="#scroll">회사연혁</Link></dd>
                <dd><Link href="#scroll">조직도</Link></dd>
              </dl>
              <dl className={expandedSection === 'product' ? 'expanded' : ''}>
                <i onClick={() => toggleSection('product')}></i>
                <dt>Product</dt>
                <dd><Link href="#scroll">IBM</Link></dd>
                <dd><Link href="#scroll">Lenovo</Link></dd>
                <dd><Link href="#scroll">Dell</Link></dd>
                <dd><Link href="#scroll">S/W</Link></dd>
              </dl>
            </li>
            <li>
              <dl className={expandedSection === 'infra' ? 'expanded' : ''}>
                <i onClick={() => toggleSection('infra')}></i>
                <dt>IT Infra</dt>
                <dd><Link href="#scroll">Consulting</Link></dd>
                <dd><Link href="#scroll">IT Infra 구축</Link></dd>
                <dd><Link href="#scroll">Maintenance</Link></dd>
              </dl>
              <dl className={expandedSection === 'career' ? 'expanded' : ''}>
                <i onClick={() => toggleSection('career')}></i>
                <dt>Career</dt>
                <dd><Link href="#scroll">Career</Link></dd>
              </dl>
            </li>
            <li>
              <dl className={expandedSection === 'contact' ? 'expanded' : ''}>
                <i onClick={() => toggleSection('contact')}></i>
                <dt>Contact Us</dt>
                <dd><Link href="#scroll">오시는 길</Link></dd>
                <dd><Link href="#scroll">문의하기</Link></dd>
              </dl>
            </li>
          </ul>
        </nav>
        <div>
          <h5>(주)트라이얼정보통신</h5>
          <ul>
            <li><Link href="#scroll">채용정보</Link></li>
            <li><Link href="#scroll">윤리강령</Link></li>
            <li><Link href="#scroll">개인정보취급방침</Link></li>
          </ul>
          <address>
            <p>
              <strong style={{ color: '#fff', fontSize: '16px', fontWeight: 400, lineHeight: '40px' }}>
                (주)트라이얼정보통신
              </strong>
            </p>
            <p>
              <span>(우) 07282 서울특별시 영등포구 선유로 13길 25, 1312 ~ 1314호</span>
              <span>(문래동6가, 에이스하이테크시티2차)</span>
            </p>
            <p>
              <span>TEL : 02-6972-1521</span>
              <span>FAX : 02-6972-1525</span>
              <span>E-mail : master@trialinfo.com</span>
            </p>
          </address>
          <p>
            <small>Copyrights 2025 logo. All rights reserved.</small>
          </p>
        </div>
      </div>
    </footer>
  );
}
