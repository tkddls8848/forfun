 

// 통계 데이터
export const statisticsData = {
  // 경제 지표 데이터
  economicIndicators: [
    { year: 2024, gdp: 1893000, growth: 2.1, unemployment: 3.8, inflation: 3.5 },
    { year: 2023, gdp: 1854000, growth: 1.4, unemployment: 3.7, inflation: 3.5 },
    { year: 2022, gdp: 1828000, growth: 2.6, unemployment: 2.9, inflation: 5.1 },
    { year: 2021, gdp: 1781000, growth: 4.1, unemployment: 3.6, inflation: 2.5 },
    { year: 2020, gdp: 1710000, growth: -0.7, unemployment: 4.0, inflation: 0.5 },
  ],

  // 인구 데이터
  populationData: [
    { region: '서울특별시', population: 9411069, density: 15514, growthRate: -0.52 },
    { region: '부산광역시', population: 3359527, density: 4333, growthRate: -0.78 },
    { region: '대구광역시', population: 2385412, density: 2694, growthRate: -0.45 },
    { region: '인천광역시', population: 2948375, density: 2785, growthRate: 0.11 },
    { region: '광주광역시', population: 1441611, density: 2884, growthRate: -0.32 },
    { region: '대전광역시', population: 1452251, density: 2680, growthRate: -0.21 },
    { region: '울산광역시', population: 1121592, density: 1057, growthRate: -0.43 },
    { region: '세종특별자치시', population: 371895, density: 817, growthRate: 4.32 },
  ],

  // 부동산 데이터
  realEstateData: [
    { month: '2024-01', apartment: 1124, house: 856, office: 2340, commercial: 1890 },
    { month: '2024-02', apartment: 1135, house: 862, office: 2355, commercial: 1905 },
    { month: '2024-03', apartment: 1142, house: 868, office: 2362, commercial: 1915 },
    { month: '2024-04', apartment: 1150, house: 875, office: 2370, commercial: 1925 },
    { month: '2024-05', apartment: 1158, house: 881, office: 2378, commercial: 1935 },
  ],

  // 교통 데이터
  trafficData: [
    { type: '고속도로', location: '경부고속도로', time: '08:00', volume: 12560, speed: 85 },
    { type: '고속도로', location: '서해안고속도로', time: '08:00', volume: 8920, speed: 92 },
    { type: '고속도로', location: '남해고속도로', time: '08:00', volume: 7850, speed: 88 },
    { type: '시내도로', location: '강남대로', time: '08:00', volume: 3450, speed: 25 },
    { type: '시내도로', location: '올림픽대로', time: '08:00', volume: 4320, speed: 45 },
  ],

  // 기상 데이터
  weatherData: [
    { date: '2024-05-10', temp: 22, humidity: 65, precipitation: 0, windSpeed: 3.2 },
    { date: '2024-05-09', temp: 20, humidity: 70, precipitation: 2.5, windSpeed: 4.1 },
    { date: '2024-05-08', temp: 19, humidity: 75, precipitation: 5.0, windSpeed: 5.3 },
    { date: '2024-05-07', temp: 18, humidity: 68, precipitation: 0, windSpeed: 2.8 },
    { date: '2024-05-06', temp: 21, humidity: 62, precipitation: 0, windSpeed: 3.5 },
  ],
};

// 데이터셋 메타데이터
export const datasetMetadata = [
  {
    id: 1,
    title: '인구 통계 데이터',
    description: '지역별 인구 현황 및 변동 추이',
    provider: '통계청',
    updateFrequency: '월간',
    lastUpdate: '2024-05-01',
    category: '인구/가구',
    format: 'CSV, JSON',
    license: '공공누리 1유형',
  },
  {
    id: 2,
    title: '부동산 가격 동향',
    description: '전국 부동산 매매/전세 가격 지수',
    provider: '한국부동산원',
    updateFrequency: '월간',
    lastUpdate: '2024-05-05',
    category: '부동산',
    format: 'CSV, JSON, XML',
    license: '공공누리 1유형',
  },
  {
    id: 3,
    title: '대기질 측정 데이터',
    description: '전국 측정소별 대기오염도 실시간 자료',
    provider: '한국환경공단',
    updateFrequency: '시간별',
    lastUpdate: '2024-05-10',
    category: '환경',
    format: 'JSON, XML',
    license: '공공누리 1유형',
  },
  {
    id: 4,
    title: '교통량 통계',
    description: '주요 도로별 교통량 및 속도 정보',
    provider: '국토교통부',
    updateFrequency: '시간별',
    lastUpdate: '2024-05-10',
    category: '교통',
    format: 'CSV, JSON',
    license: '공공누리 1유형',
  },
  {
    id: 5,
    title: '기상 관측 자료',
    description: '지역별 기온, 강수량, 풍속 등 기상 정보',
    provider: '기상청',
    updateFrequency: '시간별',
    lastUpdate: '2024-05-10',
    category: '기상',
    format: 'JSON, XML',
    license: '공공누리 1유형',
  },
];

// API 목록 데이터
export const publicApiList = [
  {
    id: 1,
    name: '공공데이터 포털 OpenAPI',
    provider: '행정안전부',
    description: '정부 및 공공기관이 보유한 데이터를 제공하는 API',
    category: '종합',
    endpoint: 'https://www.data.go.kr/api',
    authType: '인증키',
    rateLimit: '1000회/일',
    documentation: 'https://www.data.go.kr/docs',
  },
  {
    id: 2,
    name: 'KOSIS 통계정보 API',
    provider: '통계청',
    description: '국가통계포털의 통계자료를 제공하는 API',
    category: '통계',
    endpoint: 'https://kosis.kr/openapi',
    authType: '인증키',
    rateLimit: '10000회/일',
    documentation: 'https://kosis.kr/openapi/guide',
  },
  {
    id: 3,
    name: '부동산 거래 공개시스템 API',
    provider: '국토교통부',
    description: '아파트, 단독/다가구, 토지 등 부동산 실거래가 정보',
    category: '부동산',
    endpoint: 'http://openapi.molit.go.kr',
    authType: '인증키',
    rateLimit: '1000회/일',
    documentation: 'http://rtdown.molit.go.kr/rtms/rqs/pblcClInfoView.do',
  },
  {
    id: 4,
    name: '기상청 동네예보 API',
    provider: '기상청',
    description: '동네예보, 중기예보, 특보 등 기상 정보 제공',
    category: '기상',
    endpoint: 'http://apis.data.go.kr/1360000/VilageFcstInfoService_2.0',
    authType: '인증키',
    rateLimit: '10000회/일',
    documentation: 'https://www.data.go.kr/data/15084084/openapi.do',
  },
  {
    id: 5,
    name: '대기오염정보 조회 서비스',
    provider: '한국환경공단',
    description: '실시간 대기오염 정보 및 예보 제공',
    category: '환경',
    endpoint: 'http://apis.data.go.kr/B552584/ArpltnInforInqireSvc',
    authType: '인증키',
    rateLimit: '2000회/일',
    documentation: 'https://www.data.go.kr/data/15073861/openapi.do',
  },
];

// 사용자 프로필 데이터 (로그인 페이지용)
export const userProfiles = [
  {
    id: 1,
    username: 'admin',
    password: 'admin123', // 실제로는 암호화 필요
    name: '관리자',
    email: 'admin@example.com',
    role: 'admin',
    lastLogin: '2024-05-09T10:30:00',
  },
  {
    id: 2,
    username: 'user1',
    password: 'user123',
    name: '홍길동',
    email: 'hong@example.com',
    role: 'user',
    lastLogin: '2024-05-10T09:15:00',
  },
];

// 질문/답변 데이터 (Contact 페이지용)
export const faqData = [
  {
    id: 1,
    category: '일반',
    question: '서비스 이용 요금은 어떻게 되나요?',
    answer: '기본적인 데이터 조회는 무료이며, 대용량 데이터 다운로드나 고급 API 기능 사용 시 요금이 부과될 수 있습니다.',
  },
  {
    id: 2,
    category: 'API',
    question: 'API 인증키는 어떻게 발급받나요?',
    answer: '회원가입 후 마이페이지에서 API 인증키를 발급받을 수 있습니다. 발급된 키는 안전하게 보관해주세요.',
  },
  {
    id: 3,
    category: '데이터',
    question: '데이터 업데이트 주기는 어떻게 되나요?',
    answer: '데이터셋마다 업데이트 주기가 다릅니다. 각 데이터셋의 상세 정보에서 업데이트 주기를 확인할 수 있습니다.',
  },
];

// 공지사항 데이터
export const noticeData = [
  {
    id: 1,
    title: '시스템 정기 점검 안내',
    content: '2024년 5월 15일 오전 2시부터 4시까지 시스템 정기 점검이 예정되어 있습니다.',
    date: '2024-05-10',
    author: '운영팀',
    important: true,
  },
  {
    id: 2,
    title: '새로운 데이터셋 추가',
    content: '교통카드 이용 통계 데이터셋이 새롭게 추가되었습니다. 많은 이용 부탁드립니다.',
    date: '2024-05-08',
    author: '데이터팀',
    important: false,
  },
  {
    id: 3,
    title: 'API 사용량 제한 변경',
    content: '2024년 6월 1일부터 무료 계정의 일일 API 호출 제한이 1,000회에서 2,000회로 상향 조정됩니다.',
    date: '2024-05-05',
    author: '기술팀',
    important: true,
  },
];

// 차트용 샘플 데이터
export const chartSampleData = {
  lineChart: {
    labels: ['1월', '2월', '3월', '4월', '5월', '6월'],
    datasets: [
      {
        label: '2023년',
        data: [65, 59, 80, 81, 56, 55],
        borderColor: 'rgb(75, 192, 192)',
        tension: 0.1,
      },
      {
        label: '2024년',
        data: [75, 69, 90, 91, 66, 65],
        borderColor: 'rgb(255, 99, 132)',
        tension: 0.1,
      },
    ],
  },
  
  barChart: {
    labels: ['서울', '부산', '대구', '인천', '광주', '대전'],
    datasets: [
      {
        label: '인구수 (만명)',
        data: [941, 336, 239, 295, 144, 145],
        backgroundColor: 'rgba(54, 162, 235, 0.5)',
      },
    ],
  },
  
  pieChart: {
    labels: ['주거용', '상업용', '공업용', '기타'],
    datasets: [
      {
        data: [45, 25, 20, 10],
        backgroundColor: [
          'rgba(255, 99, 132, 0.5)',
          'rgba(54, 162, 235, 0.5)',
          'rgba(255, 206, 86, 0.5)',
          'rgba(75, 192, 192, 0.5)',
        ],
      },
    ],
  },
};

// 공공입찰 데이터 (utils/data.js에 추가)
export const publicBiddingList = [
  {
    id: 1,
    title: '00시청 청사 리모델링 공사',
    bidNumber: '2024-서울-0123',
    organization: '서울특별시 00구청',
    category: '공사',
    type: '일반경쟁입찰',
    budget: 2500000000,
    startDate: '2024-05-01',
    endDate: '2024-05-15',
    status: '진행중',
    description: '00시청 본관 3층~5층 리모델링 공사 및 내부 인테리어 공사',
    location: '서울특별시',
    participants: 8,
  },
  {
    id: 2,
    title: '정보시스템 유지보수 용역',
    bidNumber: '2024-경기-0456',
    organization: '경기도 00시청',
    category: '용역',
    type: '제한경쟁입찰',
    budget: 450000000,
    startDate: '2024-05-03',
    endDate: '2024-05-17',
    status: '진행중',
    description: '행정정보시스템 및 홈페이지 유지보수 용역 (12개월)',
    location: '경기도',
    participants: 5,
  },
  {
    id: 3,
    title: '사무용품 구매 입찰',
    bidNumber: '2024-부산-0789',
    organization: '부산광역시 교육청',
    category: '물품',
    type: '일반경쟁입찰',
    budget: 180000000,
    startDate: '2024-05-05',
    endDate: '2024-05-12',
    status: '마감임박',
    description: '2024년도 하반기 사무용품 일괄 구매',
    location: '부산광역시',
    participants: 12,
  },
  {
    id: 4,
    title: '도로 포장 보수공사',
    bidNumber: '2024-대구-0321',
    organization: '대구광역시 도로사업소',
    category: '공사',
    type: '일반경쟁입찰',
    budget: 850000000,
    startDate: '2024-04-28',
    endDate: '2024-05-10',
    status: '마감',
    description: '주요 간선도로 포장 보수 및 도로시설물 정비 공사',
    location: '대구광역시',
    participants: 6,
  },
  {
    id: 5,
    title: '학교급식 식재료 납품',
    bidNumber: '2024-인천-0654',
    organization: '인천광역시 교육청',
    category: '물품',
    type: '제한경쟁입찰',
    budget: 2100000000,
    startDate: '2024-05-02',
    endDate: '2024-05-16',
    status: '진행중',
    description: '2024년 2학기 학교급식 식재료 납품업체 선정',
    location: '인천광역시',
    participants: 15,
  },
  {
    id: 6,
    title: '공원 조경관리 용역',
    bidNumber: '2024-광주-0987',
    organization: '광주광역시 공원녹지과',
    category: '용역',
    type: '일반경쟁입찰',
    budget: 620000000,
    startDate: '2024-05-06',
    endDate: '2024-05-20',
    status: '진행중',
    description: '시민공원 및 어린이공원 연간 조경관리 용역',
    location: '광주광역시',
    participants: 4,
  },
  {
    id: 7,
    title: '소방장비 구매 입찰',
    bidNumber: '2024-대전-0159',
    organization: '대전광역시 소방본부',
    category: '물품',
    type: '일반경쟁입찰',
    budget: 520000000,
    startDate: '2024-05-04',
    endDate: '2024-05-18',
    status: '진행중',
    description: '소방호스, 방화복, 공기호흡기 등 소방장비 구매',
    location: '대전광역시',
    participants: 7,
  },
  {
    id: 8,
    title: '하수관로 정비공사',
    bidNumber: '2024-울산-0753',
    organization: '울산광역시 상하수도사업본부',
    category: '공사',
    type: '제한경쟁입찰',
    budget: 3200000000,
    startDate: '2024-05-01',
    endDate: '2024-05-15',
    status: '진행중',
    description: '노후 하수관로 교체 및 보수 공사',
    location: '울산광역시',
    participants: 5,
  },
  {
    id: 9,
    title: '문화예술 공연 기획 용역',
    bidNumber: '2024-세종-0852',
    organization: '세종특별자치시 문화체육관광과',
    category: '용역',
    type: '일반경쟁입찰',
    budget: 380000000,
    startDate: '2024-05-07',
    endDate: '2024-05-21',
    status: '진행중',
    description: '2024년 하반기 시민 문화예술 공연 기획 및 운영',
    location: '세종특별자치시',
    participants: 3,
  },
  {
    id: 10,
    title: 'CCTV 설치 공사',
    bidNumber: '2024-제주-0456',
    organization: '제주특별자치도 자치경찰단',
    category: '공사',
    type: '일반경쟁입찰',
    budget: 890000000,
    startDate: '2024-05-02',
    endDate: '2024-05-16',
    status: '진행중',
    description: '주요 교차로 및 학교 주변 CCTV 신규 설치',
    location: '제주특별자치도',
    participants: 6,
  },
];