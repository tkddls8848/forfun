'use client';

import { useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';

export default function Header({ isScrolled }) {
  const [isNavOpen, setIsNavOpen] = useState(false);

  return (
    <header className={isScrolled ? 'scrolled' : ''}>
      <i className="wt_bg" style={{ display: 'block' }}></i>
      <div className="inner">
        <h1>
          <Link href="/" style={{ background: 'transparent' }}>
            <Image src="/images/logo/logo.png" alt="Logo" width={150} height={40} />
            <Image src="/images/logo/logo_wt.png" alt="White Logo" width={150} height={40} />
          </Link>
        </h1>
        <nav className={isNavOpen ? 'open' : ''}>
          <ul>
            <li><Link href="#scroll">About Us</Link></li>
            <li><Link href="#scroll">Product</Link></li>
            <li><Link href="#scroll">IT Infra</Link></li>
            <li><Link href="#scroll">Career</Link></li>
            <li><Link href="#scroll">Contact Us</Link></li>
          </ul>
          <i className="btn_close" onClick={() => setIsNavOpen(false)}>
            <Image src="/images/icon/nav/close.png" alt="Close" width={24} height={24} />
          </i>
        </nav>
        <i className="btn_ham" onClick={() => setIsNavOpen(true)}>
          <Image src="/images/icon/nav/hamburger.png" alt="Menu" width={24} height={24} />
          <Image src="/images/icon/nav/hamburger_wt.png" alt="White Menu" width={24} height={24} />
        </i>
      </div>
      <div className="popup_wrapper" id="page_is_not_ready">
        <div className="popup">
          <p>
            <strong>페이지가 준비중에 있습니다.</strong>
          </p>
          <a href="#close">확인</a>
        </div>
        <a className="popup_bg" href="#close"></a>
      </div>
    </header>
  );
}
