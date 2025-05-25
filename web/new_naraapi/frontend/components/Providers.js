'use client';

import { RecoilRoot } from 'recoil';

export default function Providers({ children }) {
  return <RecoilRoot>{children}</RecoilRoot>;
} 