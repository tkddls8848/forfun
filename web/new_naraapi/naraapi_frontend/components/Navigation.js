'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

export default function Navigation() {
  const pathname = usePathname();
  
  const navItems = [
    { name: '홈', path: '/' },
    { name: '데이터 탐색', path: '/explore' },
    { name: '통계 분석', path: '/statistics' },
    { name: '공공 API', path: '/api-docs' }
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
                    isActive 
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