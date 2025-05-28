import Link from 'next/link';

export default function StatCard({ title, value, change, description, link, chartComponent }) {
  // Calculate if the change is positive, negative, or neutral
  const changeType = 
    !change ? 'neutral' : 
    parseFloat(change) > 0 ? 'positive' : 
    parseFloat(change) < 0 ? 'negative' : 'neutral';
  
  // Map change type to appropriate color and icon
  const changeStyles = {
    positive: {
      color: 'text-green-500',
      icon: (
        <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M12 7a1 1 0 110-2h5a1 1 0 011 1v5a1 1 0 11-2 0V8.414l-4.293 4.293a1 1 0 01-1.414 0L8 10.414l-4.293 4.293a1 1 0 01-1.414-1.414l5-5a1 1 0 011.414 0L11 10.586 14.586 7H12z" clipRule="evenodd" />
        </svg>
      )
    },
    negative: {
      color: 'text-red-500',
      icon: (
        <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
          <path fillRule="evenodd" d="M12 13a1 1 0 100 2h5a1 1 0 001-1v-5a1 1 0 10-2 0v2.586l-4.293-4.293a1 1 0 00-1.414 0L8 9.586 3.707 5.293a1 1 0 00-1.414 1.414l5 5a1 1 0 001.414 0L11 9.414 14.586 13H12z" clipRule="evenodd" />
        </svg>
      )
    },
    neutral: {
      color: 'text-gray-500',
      icon: null
    }
  };
  
  return (
    <div className="card">
      <div className="mb-4">
        <h3 className="text-lg font-medium">{title}</h3>
        {description && <p className="text-sm text-gray-500">{description}</p>}
      </div>
      
      <div className="flex items-end justify-between mb-4">
        <div className="flex flex-col">
          <span className="text-3xl font-bold">{value}</span>
          {change && (
            <div className={`flex items-center mt-1 ${changeStyles[changeType].color}`}>
              {changeStyles[changeType].icon}
              <span className="ml-1 text-sm">{change}</span>
            </div>
          )}
        </div>
      </div>
      
      {chartComponent && (
        <div className="mt-4">
          {chartComponent}
        </div>
      )}
      
      {link && (
        <div className="mt-4">
          <Link href={link} className="text-sm text-primary-color hover:underline">
            자세히 보기 →
          </Link>
        </div>
      )}
    </div>
  );
}