'use client';

import { useState } from 'react';
import { 
  LineChart, Line, BarChart, Bar, 
  PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, 
  ResponsiveContainer 
} from 'recharts';

const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#A28EFF', '#FF6B6B'];

export default function DataVisualizer({ 
  data, 
  type = 'line', 
  xKey = 'name', 
  yKey = 'value',
  width = '100%', 
  height = 300,
  colors = COLORS
}) {
  const [chartType, setChartType] = useState(type);
  
  // Function to convert the data format if needed
  const formatData = (inputData) => {
    if (!Array.isArray(inputData)) {
      return [];
    }
    return inputData;
  };
  
  const formattedData = formatData(data);
  
  const renderChart = () => {
    switch (chartType) {
      case 'line':
        return (
          <ResponsiveContainer width={width} height={height}>
            <LineChart
              data={formattedData}
              margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
            >
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey={xKey} />
              <YAxis />
              <Tooltip />
              <Legend />
              <Line 
                type="monotone" 
                dataKey={yKey} 
                stroke={colors[0]} 
                activeDot={{ r: 8 }} 
              />
            </LineChart>
          </ResponsiveContainer>
        );
        
      case 'bar':
        return (
          <ResponsiveContainer width={width} height={height}>
            <BarChart
              data={formattedData}
              margin={{ top: 5, right: 30, left: 20, bottom: 5 }}
            >
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey={xKey} />
              <YAxis />
              <Tooltip />
              <Legend />
              <Bar dataKey={yKey} fill={colors[0]} />
            </BarChart>
          </ResponsiveContainer>
        );
        
      case 'pie':
        return (
          <ResponsiveContainer width={width} height={height}>
            <PieChart>
              <Pie
                data={formattedData}
                cx="50%"
                cy="50%"
                labelLine={false}
                outerRadius={80}
                fill="#8884d8"
                dataKey={yKey}
                nameKey={xKey}
                label={({ name, percent }) => `${name}: ${(percent * 100).toFixed(0)}%`}
              >
                {formattedData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={colors[index % colors.length]} />
                ))}
              </Pie>
              <Tooltip />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        );
        
      default:
        return <div>지원되지 않는 차트 타입입니다.</div>;
    }
  };
  
  return (
    <div className="data-visualizer">
      <div className="flex justify-end mb-4">
        <div className="btn-group">
          <button
            onClick={() => setChartType('line')}
            className={`btn btn-sm ${chartType === 'line' ? 'btn-primary' : 'btn-outline'}`}
          >
            라인
          </button>
          <button
            onClick={() => setChartType('bar')}
            className={`btn btn-sm ${chartType === 'bar' ? 'btn-primary' : 'btn-outline'}`}
          >
            바
          </button>
          <button
            onClick={() => setChartType('pie')}
            className={`btn btn-sm ${chartType === 'pie' ? 'btn-primary' : 'btn-outline'}`}
          >
            파이
          </button>
        </div>
      </div>
      
      {renderChart()}
    </div>
  );
}