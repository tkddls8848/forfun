'use client';

import ProductItem from './ProductItem';

export default function ProductList() {
  const products = [
    {
      name: 'Power<br>E1080',
      subTitle: 'Unix Server',
      description: '하이브리드 클라우드 전반에 코어 운영 워크로드 및 AI 애플리케이션을 안전하고 효율적으로 확장하도록 설계되었습니다.',
      features: [
        '계층적 보호 제공',
        '효율성 향상',
        '손쉬운 AI 배포',
        '가용성 향상'
      ],
      imageUrl: '/images/photo/product/ibm/UnixServer/power9_e1080.png',
      linkUrl: 'https://www.ibm.com/kr-ko/products/power-e1080?mhsrc=ibmsearch_a&mhq=e1080'
    },
    {
      name: 'Power<br>E1050',
      subTitle: 'Unix Server',
      description: 'IBM Power E1050 미드레인지 서버는 안정적이고 안전하며 공간 효율적인 4U 랙에서 엔터프라이즈급 기능을 제공합니다.',
      features: [
        '보안 향상',
        '효율적인 확장',
        '가용성 극대화',
        '인사이트 간소화'
      ],
      imageUrl: '/images/photo/product/ibm/UnixServer/power9_e1050.png',
      linkUrl: 'https://www.ibm.com/kr-ko/products/power-e1050?mhsrc=ibmsearch_a&mhq=e1050'
    },
    {
      name: 'Power<br>S1024',
      subTitle: 'Unix Server',
      description: 'IBM Power S1024는 IBM Power9 기반 서버의 코어를 두 배로 늘려 보다 적은 수의 서버에서 워크로드를 통합할 수 있습니다.',
      features: [
        '애플리케이션 성능 향상',
        '인프라 비용 절감',
        '코어부터 클라우드까지 강력한 보안',
        '업계를 선도하는 RAS',
        'AI 추론',
        '유연한 소비 모델'
      ],
      imageUrl: '/images/photo/product/ibm/UnixServer/power10_s1024.png',
      linkUrl: 'https://www.ibm.com/kr-ko/products/power-s1024?mhsrc=ibmsearch_a&mhq=s1024'
    },
    {
      name: 'Power<br>S1022, S1022s',
      subTitle: 'Unix Server',
      description: 'IBM AIX, IBM i, Linux에서 실행하는 비즈니스 크리티컬 워크로드에 적합하게 설계된 2소켓, 2U 서버입니다.',
      features: [
        '앱 기능 확장',
        'IT 비용 절감',
        '보안 향상',
        '최적의 RAS 제공',
        'AI 추론 실행',
        '필요한 만큼만 결제'
      ],
      imageUrl: '/images/photo/product/ibm/UnixServer/power9_s1022.png',
      linkUrl: 'https://www.ibm.com/kr-ko/products/power-s1022?mhsrc=ibmsearch_a&mhq=S1022'
    },
    {
      name: 'Power<br>S1014',
      subTitle: 'Unix Server',
      description: '비즈니스 크리티컬 워크로드에 적합하게 설계된 1소켓, 4U IBM Power10 기반 서버입니다.',
      features: [
        '앱 기능 확장',
        'IT 비용 절감',
        '보안 향상',
        'AI 추론 실행'
      ],
      imageUrl: '/images/photo/product/ibm/UnixServer/power9_s1014.png',
      linkUrl: 'https://www.ibm.com/kr-ko/products/power-s1014?mhsrc=ibmsearch_a&mhq=s1014'
    }
  ];

  return (
    <div className="body">
      <div className="product_wrapper">
        {products.map((product, index) => (
          <ProductItem 
            key={index}
            name={product.name}
            subTitle={product.subTitle}
            description={product.description}
            features={product.features}
            imageUrl={product.imageUrl}
            linkUrl={product.linkUrl}
          />
        ))}
      </div>
    </div>
  );
}
