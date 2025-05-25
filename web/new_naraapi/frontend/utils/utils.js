// utils/utils.js

// API 호출 관련 유틸리티
export const fetchData = async (url, options = {}) => {
    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        },
      });
  
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
  
      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Fetch error:', error);
      throw error;
    }
  };
  
  // 날짜 포맷팅 유틸리티
  export const formatDate = (dateString) => {
    if (!dateString) return '-';
    const date = new Date(dateString);
    return date.toLocaleDateString('ko-KR', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
    });
  };
  
  // 숫자 포맷팅 유틸리티 (천 단위 콤마)
  export const formatNumber = (number) => {
    if (number === null || number === undefined) return '-';
    return new Intl.NumberFormat('ko-KR').format(number);
  };
  
  // 통화 포맷팅 유틸리티
  export const formatCurrency = (amount, currency = 'KRW') => {
    if (amount === null || amount === undefined) return '-';
    return new Intl.NumberFormat('ko-KR', {
      style: 'currency',
      currency: currency,
    }).format(amount);
  };
  
  // 퍼센트 포맷팅
  export const formatPercent = (num) => {
    if (num === null || num === undefined) return '-';
    return `${num.toFixed(1)}%`;
  };
  
  // 차트 데이터 변환 유틸리티
  export const transformChartData = (data, xKey, yKey) => {
    return data.map(item => ({
      x: item[xKey],
      y: item[yKey],
    }));
  };
  
  // 데이터 필터링 유틸리티
  export const filterData = (data, searchTerm, fields) => {
    if (!searchTerm) return data;
    
    const searchLower = searchTerm.toLowerCase();
    return data.filter(item => 
      fields.some(field => 
        String(item[field]).toLowerCase().includes(searchLower)
      )
    );
  };
  
  // 페이지네이션 유틸리티
  export const paginate = (data, page, itemsPerPage) => {
    const startIndex = (page - 1) * itemsPerPage;
    const endIndex = startIndex + itemsPerPage;
    const totalPages = Math.ceil(data.length / itemsPerPage);
    
    return {
      data: data.slice(startIndex, endIndex),
      pagination: {
        currentPage: page,
        totalPages,
        totalItems: data.length,
        itemsPerPage
      }
    };
  };
  
  // 통계 계산 유틸리티
  export const calculateStats = (data, valueKey) => {
    if (!data || data.length === 0) return null;
    
    const values = data.map(item => item[valueKey]).filter(val => val !== null && val !== undefined);
    
    if (values.length === 0) return null;
    
    const sum = values.reduce((acc, val) => acc + val, 0);
    const avg = sum / values.length;
    const max = Math.max(...values);
    const min = Math.min(...values);
    
    return {
      sum,
      average: avg,
      max,
      min,
      count: values.length,
    };
  };
  
  // 로컬 스토리지 유틸리티
  export const storage = {
    get: (key) => {
      if (typeof window === 'undefined') return null;
      try {
        const item = window.localStorage.getItem(key);
        return item ? JSON.parse(item) : null;
      } catch (error) {
        console.error('Error reading from localStorage:', error);
        return null;
      }
    },
    
    set: (key, value) => {
      if (typeof window === 'undefined') return;
      try {
        window.localStorage.setItem(key, JSON.stringify(value));
      } catch (error) {
        console.error('Error writing to localStorage:', error);
      }
    },
    
    remove: (key) => {
      if (typeof window === 'undefined') return;
      try {
        window.localStorage.removeItem(key);
      } catch (error) {
        console.error('Error removing from localStorage:', error);
      }
    },
  };
  
  // 디바운스 유틸리티
  export const debounce = (func, wait) => {
    let timeout;
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout);
        func(...args);
      };
      clearTimeout(timeout);
      timeout = setTimeout(later, wait);
    };
  };
  
  // 에러 처리 유틸리티
  export const handleApiError = (error) => {
    if (error.response) {
      // 서버가 2xx 범위를 벗어나는 상태 코드로 응답했을 때
      console.error('Error data:', error.response.data);
      console.error('Error status:', error.response.status);
      return {
        message: error.response.data.message || '서버 오류가 발생했습니다.',
        status: error.response.status,
      };
    } else if (error.request) {
      // 요청이 이루어졌으나 응답을 받지 못했을 때
      console.error('Error request:', error.request);
      return {
        message: '서버와 연결할 수 없습니다.',
        status: null,
      };
    } else {
      // 요청 설정 중에 오류가 발생했을 때
      console.error('Error message:', error.message);
      return {
        message: error.message || '알 수 없는 오류가 발생했습니다.',
        status: null,
      };
    }
  };
  
  // CSV 다운로드 유틸리티
  export const downloadCSV = (data, filename = 'data.csv') => {
    const rows = [];
    const headers = Object.keys(data[0]);
    rows.push(headers.join(','));
    
    data.forEach(item => {
      const values = headers.map(header => {
        const value = item[header];
        return typeof value === 'string' && value.includes(',') 
          ? `"${value}"` 
          : value;
      });
      rows.push(values.join(','));
    });
    
    const csvContent = rows.join('\n');
    const blob = new Blob(['\ufeff' + csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = filename;
    link.click();
  };