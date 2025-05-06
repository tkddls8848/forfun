'use client';

import { useState } from 'react';
import Link from 'next/link';

export default function InsideTab() {
  const [activeMainTab, setActiveMainTab] = useState('ibm');
  const [activeSecondaryTab, setActiveSecondaryTab] = useState('unix');
  
  return (
    <div className="inside_tab">
      <div className="primary">
        <div className="inner">
          <ul>
            <li className={activeMainTab === 'ibm' ? 'active' : ''}>
              <Link href="#scroll" onClick={() => setActiveMainTab('ibm')}>
                IBM
              </Link>
            </li>
            <li className={activeMainTab === 'lenovo' ? 'active' : ''}>
              <Link href="#scroll" onClick={() => setActiveMainTab('lenovo')}>
                Lenovo
              </Link>
            </li>
            <li className={activeMainTab === 'dell' ? 'active' : ''}>
              <Link href="#scroll" onClick={() => setActiveMainTab('dell')}>
                Dell
              </Link>
            </li>
            <li className={activeMainTab === 'sw' ? 'active' : ''}>
              <Link href="#scroll" onClick={() => setActiveMainTab('sw')}>
                S/W
              </Link>
            </li>
          </ul>
        </div>
      </div>
      <div className="secondary">
        <div className="inner">
          <ul>
            <li className={activeSecondaryTab === 'unix' ? 'active' : ''}>
              <Link href="#scroll" onClick={() => setActiveSecondaryTab('unix')}>
                UNIX Server
              </Link>
            </li>
            <li className={activeSecondaryTab === 'mission' ? 'active' : ''}>
              <Link href="#scroll" onClick={() => setActiveSecondaryTab('mission')}>
                Mission Critical Server
              </Link>
            </li>
            <li className={activeSecondaryTab === 'storage' ? 'active' : ''}>
              <Link href="#scroll" onClick={() => setActiveSecondaryTab('storage')}>
                Storage
              </Link>
            </li>
          </ul>
        </div>
      </div>
    </div>
  );
}
