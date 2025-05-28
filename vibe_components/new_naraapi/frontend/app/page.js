import Link from 'next/link';
import StatCard from '../components/StatCard';
import SearchBar from '../components/SearchBar';

// Example data - in a real app, this would come from an API
const featuredStats = [
  {
    id: 1,
    title: '인구 통계',
    value: '51.74백만',
    change: '+0.1%',
    description: '2025년 대한민국 인구 통계',
    link: '/statistics/population'
  },
  {
    id: 2,
    title: '경제 성장률',
    value: '3.2%',
    change: '+0.5%',
    description: '2025년 1분기 경제 성장률',
    link: '/statistics/economy'
  },
  {
    id: 3,
    title: '실업률',
    value: '3.4%',
    change: '-0.2%',
    description: '2025년 4월 실업률',
    link: '/statistics/employment'
  }
];

const featuredDatasets = [
  {
    id: 1,
    title: '코로나19 현황',
    description: '코로나19 확진자, 사망자, 백신접종 현황 등의 데이터',
    category: '보건',
    url: '/datasets/covid19'
  },
  {
    id: 2,
    title: '대기오염 측정 데이터',
    description: '전국 대기오염 측정소 데이터 (미세먼지, 초미세먼지, 오존 등)',
    category: '환경',
    url: '/datasets/air-pollution'
  },
  {
    id: 3,
    title: '부동산 실거래가',
    description: '전국 아파트 및 주택 실거래가 데이터',
    category: '부동산',
    url: '/datasets/real-estate'
  }
];

export default function Home() {
  return (
    <div>
      {/* Hero Section */}
      <section className="bg-primary-color text-black py-16">
        <div className="container mx-auto px-4 text-center">
          <h1 className="text-4xl font-bold mb-4">공공데이터 포털</h1>
          <p className="text-xl mb-8">한국 정부의 OpenAPI 기반 공공데이터를 쉽게 탐색하고 활용하세요.</p>
        </div>
      </section>
      {/* Search bar */}
      <section className="py-6 bg-secondary-color">
      <div className="container mx-auto px-4 text-center">
      <div className="flex justify-between items-center mb-8">
        <SearchBar />
        </div>
      </div>
      </section>
      {/* Featured Statistics */}
      <section className="py-6 bg-secondary-color">
        <div className="container mx-auto px-4">
          <div className="flex justify-between items-center mb-8">
            <h2 className="text-2xl font-bold">주요 통계</h2>
            <Link href="/statistics" className="text-primary-color hover:underline">
              모든 통계 보기 →
            </Link>
          </div>
          
          <div className="stat-grid">
            {featuredStats.map((stat) => (
              <StatCard
                key={stat.id}
                title={stat.title}
                value={stat.value}
                change={stat.change}
                description={stat.description}
                link={stat.link}
              />
            ))}
          </div>
        </div>
      </section>
      
      {/* Featured Datasets */}
      <section className="py-6">
        <div className="container mx-auto px-4">
          <div className="flex justify-between items-center mb-8">
            <h2 className="text-2xl font-bold">주요 데이터셋</h2>
            <Link href="/datasets" className="text-primary-color hover:underline">
              모든 데이터셋 보기 →
            </Link>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {featuredDatasets.map((dataset) => (
              <div key={dataset.id} className="card">
                <div className="mb-2">
                  <span className="inline-block bg-primary-color bg-opacity-10 text-primary-color text-xs px-2 py-1 rounded-full">
                    {dataset.category}
                  </span>
                </div>
                <h3 className="text-lg font-medium mb-2">{dataset.title}</h3>
                <p className="text-sm text-gray-600 mb-4">{dataset.description}</p>
                <Link href={dataset.url} className="text-primary-color hover:underline text-sm">
                  자세히 보기 →
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Featured publicapis */}
      <section className="py-6">
        <div className="container mx-auto px-4">
          <div className="flex justify-between items-center mb-8">
            <h2 className="text-2xl font-bold">공공 API 문서</h2>
            <Link href="/publicapis" className="text-primary-color hover:underline">
              모든 문서 보기 →
            </Link>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {featuredDatasets.map((dataset) => (
              <div key={dataset.id} className="card">
                <div className="mb-2">
                  <span className="inline-block bg-primary-color bg-opacity-10 text-primary-color text-xs px-2 py-1 rounded-full">
                    {dataset.category}
                  </span>
                </div>
                <h3 className="text-lg font-medium mb-2">{dataset.title}</h3>
                <p className="text-sm text-gray-600 mb-4">{dataset.description}</p>
                <Link href={dataset.url} className="text-primary-color hover:underline text-sm">
                  자세히 보기 →
                </Link>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Call to Action */}
      <section className="py-6 bg-light-gray">
        <div className="container mx-auto px-4 text-center">
          <h2 className="text-2xl font-bold mb-4">공공데이터로 새로운 가치를 창출하세요</h2>
          <p className="text-lg mb-8 max-w-3xl mx-auto">
            한국 정부의 다양한 공공데이터를 활용하여 혁신적인 서비스와 솔루션을 개발해보세요. 
            통계 자료부터 실시간 API까지, 필요한 데이터를 찾아보세요.
          </p>
          <Link href="/register" className="btn btn-primary">
            회원가입하고 시작하기
          </Link>
        </div>
      </section>
    </div>
  );
}