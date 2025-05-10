import { NextResponse } from 'next/server';

// Example data - in a real app, this would come from a database or external API
const datasets = {
  population: [
    { year: 2020, value: 51.78 },
    { year: 2021, value: 51.74 },
    { year: 2022, value: 51.70 },
    { year: 2023, value: 51.66 },
    { year: 2024, value: 51.62 },
    { year: 2025, value: 51.58 }
  ],
  economy: [
    { year: 2020, quarter: 1, gdpGrowth: -1.2 },
    { year: 2020, quarter: 2, gdpGrowth: -3.1 },
    { year: 2020, quarter: 3, gdpGrowth: -1.3 },
    { year: 2020, quarter: 4, gdpGrowth: 0.5 },
    { year: 2021, quarter: 1, gdpGrowth: 1.7 },
    { year: 2021, quarter: 2, gdpGrowth: 2.1 },
    { year: 2021, quarter: 3, gdpGrowth: 2.4 },
    { year: 2021, quarter: 4, gdpGrowth: 2.9 },
    { year: 2022, quarter: 1, gdpGrowth: 2.8 },
    { year: 2022, quarter: 2, gdpGrowth: 2.9 },
    { year: 2022, quarter: 3, gdpGrowth: 3.0 },
    { year: 2022, quarter: 4, gdpGrowth: 3.1 },
    { year: 2023, quarter: 1, gdpGrowth: 3.0 },
    { year: 2023, quarter: 2, gdpGrowth: 2.9 },
    { year: 2023, quarter: 3, gdpGrowth: 3.1 },
    { year: 2023, quarter: 4, gdpGrowth: 3.0 },
    { year: 2024, quarter: 1, gdpGrowth: 2.9 },
    { year: 2024, quarter: 2, gdpGrowth: 3.0 },
    { year: 2024, quarter: 3, gdpGrowth: 3.1 },
    { year: 2024, quarter: 4, gdpGrowth: 3.2 },
    { year: 2025, quarter: 1, gdpGrowth: 3.3 }
  ],
  employment: [
    { year: 2023, month: 1, unemploymentRate: 3.7 },
    { year: 2023, month: 2, unemploymentRate: 3.6 },
    { year: 2023, month: 3, unemploymentRate: 3.5 },
    { year: 2023, month: 4, unemploymentRate: 3.5 },
    { year: 2023, month: 5, unemploymentRate: 3.7 },
    { year: 2023, month: 6, unemploymentRate: 3.6 },
    { year: 2023, month: 7, unemploymentRate: 3.5 },
    { year: 2023, month: 8, unemploymentRate: 3.4 },
    { year: 2023, month: 9, unemploymentRate: 3.4 },
    { year: 2023, month: 10, unemploymentRate: 3.5 },
    { year: 2023, month: 11, unemploymentRate: 3.6 },
    { year: 2023, month: 12, unemploymentRate: 3.5 },
    { year: 2024, month: 1, unemploymentRate: 3.6 },
    { year: 2024, month: 2, unemploymentRate: 3.7 },
    { year: 2024, month: 3, unemploymentRate: 3.7 },
    { year: 2024, month: 4, unemploymentRate: 3.6 },
    { year: 2024, month: 5, unemploymentRate: 3.6 },
    { year: 2024, month: 6, unemploymentRate: 3.5 },
    { year: 2024, month: 7, unemploymentRate: 3.5 },
    { year: 2024, month: 8, unemploymentRate: 3.5 },
    { year: 2024, month: 9, unemploymentRate: 3.4 },
    { year: 2024, month: 10, unemploymentRate: 3.5 },
    { year: 2024, month: 11, unemploymentRate: 3.5 },
    { year: 2024, month: 12, unemploymentRate: 3.4 },
    { year: 2025, month: 1, unemploymentRate: 3.5 },
    { year: 2025, month: 2, unemploymentRate: 3.5 },
    { year: 2025, month: 3, unemploymentRate: 3.4 },
    { year: 2025, month: 4, unemploymentRate: 3.4 }
  ]
};

// This is a simple API handler function that responds to GET requests
export async function GET(request) {
  // Get the dataset type from the query parameters
  const searchParams = request.nextUrl.searchParams;
  const type = searchParams.get('type') || 'population';
  const limit = parseInt(searchParams.get('limit') || '100');
  const from = searchParams.get('from');
  const to = searchParams.get('to');
  
  // Get the requested dataset
  let data = datasets[type] || [];
  
  // Apply filters if specified
  if (from || to) {
    data = data.filter(item => {
      const itemYear = item.year;
      const fromYear = from ? parseInt(from) : 0;
      const toYear = to ? parseInt(to) : 9999;
      
      return itemYear >= fromYear && itemYear <= toYear;
    });
  }
  
  // Apply limit
  data = data.slice(0, limit);
  
  // Return the data with the appropriate headers
  return NextResponse.json({ 
    success: true,
    data,
    metadata: {
      type,
      count: data.length,
      source: '공공데이터 포털 API',
      lastUpdated: '2025-05-01'
    }
  }, {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'max-age=3600'
    }
  });
}

// This function handles POST requests - in a real app, this might create or update data
export async function POST(request) {
  try {
    // Parse the request body
    const body = await request.json();
    
    // Here you would typically validate and process the data
    // For this example, we'll just echo it back
    
    return NextResponse.json({
      success: true,
      message: '데이터가 성공적으로 처리되었습니다.',
      receivedData: body
    }, {
      status: 201,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  } catch (error) {
    return NextResponse.json({
      success: false,
      message: '데이터 처리 중 오류가 발생했습니다.',
      error: error.message
    }, {
      status: 400,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  }
}