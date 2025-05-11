'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

export default function Navigation() {
  const pathname = usePathname();
  
  const navItems = [
    { name: '홈', path: '/' },
    { name: '공공 입찰(naraapi)', path: '/dev/bidding' },
    { name: '통계 분석', path: '/dev/statistics', isDev: true },
    { name: '데이터 탐색', path: '/dev/datasets', isDev: true },
    { name: '공공 API 문서', path: '/dev/publicapis', isDev: true }
  ];
  
  return (
    <nav className="bg-secondary-color border-b border-light-gray">
      <div className="container mx-auto px-4">
        <ul className="flex space-x-8">
          {navItems.map((item) => {
            const isActive = pathname === item.path || 
              (item.path !== '/' && pathname?.startsWith(item.path));
            
            return (
              <li key={item.path}>
                <Link 
                  href={item.path}
                  className={`inline-block py-4 border-b-2 ${
                    item.isDev
                      ? isActive
                        ? 'border-gray-600 text-gray-300 font-medium'
                        : 'border-transparent text-gray-200 hover:text-gray-500 hover:border-gray-300'
                      : isActive
                        ? 'border-primary-color text-primary-color font-medium'
                        : 'border-transparent hover:text-primary-color'
                  }`}
                >
                  {item.name}
                </Link>
              </li>
            );
          })}
        </ul>
      </div>
    </nav>
  );
}