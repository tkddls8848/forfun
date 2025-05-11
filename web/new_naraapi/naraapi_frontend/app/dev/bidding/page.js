// app/publicbidding/page.js
'use client';

import { useState } from 'react';
import { filterData, paginate, formatCurrency, debounce } from '@/utils/utils';
import { publicBiddingList } from '@/utils/data';

export default function PublicBiddingPage() {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [selectedStatus, setSelectedStatus] = useState('all');
  const [currentPage, setCurrentPage] = useState(1);

  // 카테고리 필터링
  let filteredBiddings = publicBiddingList;
  
  if (selectedCategory !== 'all') {
    filteredBiddings = filteredBiddings.filter(bid => bid.category === selectedCategory);
  }
  
  if (selectedStatus !== 'all') {
    filteredBiddings = filteredBiddings.filter(bid => bid.status === selectedStatus);
  }

  // 검색 필터링
  const searchFiltered = filterData(filteredBiddings, searchTerm, ['title', 'organization', 'bidNumber', 'location']);
  
  // 페이지네이션
  const paginatedBiddings = paginate(searchFiltered, currentPage, 6);

  // 디바운스된 검색 핸들러
  const debouncedSearch = debounce((value) => {
    setSearchTerm(value);
    setCurrentPage(1);
  }, 300);

  // 카테고리 목록
  const categories = [...new Set(publicBiddingList.map(bid => bid.category))];
  const statuses = [...new Set(publicBiddingList.map(bid => bid.status))];

  // 상태에 따른 배지 색상
  const getStatusBadgeColor = (status) => {
    switch (status) {
      case '진행중':
        return 'bg-green-100 text-green-800';
      case '마감임박':
        return 'bg-yellow-100 text-yellow-800';
      case '마감':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  // 날짜 포맷팅
  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString('ko-KR');
  };

  // D-day 계산
  const calculateDday = (endDate) => {
    const today = new Date();
    const end = new Date(endDate);
    const diffTime = end - today;
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    
    if (diffDays < 0) return '마감';
    if (diffDays === 0) return 'D-Day';
    return `D-${diffDays}`;
  };

  return (
    <div className="container mx-auto px-4 pt-20 pb-8">
      <h1 className="text-3xl font-bold mb-8">공공입찰 목록</h1>
      
      {/* 검색 및 필터 */}
      <div className="mb-8 flex flex-col md:flex-row gap-4">
        <input
          type="text"
          placeholder="공고명, 발주기관, 입찰번호, 지역으로 검색..."
          className="flex-1 p-3 border rounded-lg"
          onChange={(e) => debouncedSearch(e.target.value)}
        />
        
        <select
          className="p-3 border rounded-lg"
          value={selectedCategory}
          onChange={(e) => {
            setSelectedCategory(e.target.value);
            setCurrentPage(1);
          }}
        >
          <option value="all">모든 분야</option>
          {categories.map(category => (
            <option key={category} value={category}>
              {category}
            </option>
          ))}
        </select>
        
        <select
          className="p-3 border rounded-lg"
          value={selectedStatus}
          onChange={(e) => {
            setSelectedStatus(e.target.value);
            setCurrentPage(1);
          }}
        >
          <option value="all">모든 상태</option>
          {statuses.map(status => (
            <option key={status} value={status}>
              {status}
            </option>
          ))}
        </select>
      </div>

      {/* 입찰 카드 그리드 */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
        {paginatedBiddings.data.map(bid => (
          <div key={bid.id} className="card hover:shadow-lg transition-shadow">
            <div className="flex justify-between items-start mb-3">
              <div className="flex-1">
                <h3 className="text-lg font-semibold mb-1">{bid.title}</h3>
                <p className="text-sm text-gray-600">{bid.bidNumber}</p>
              </div>
              <div className="flex flex-col items-end gap-1">
                <span className={`text-xs font-medium px-2.5 py-0.5 rounded ${getStatusBadgeColor(bid.status)}`}>
                  {bid.status}
                </span>
                <span className="text-xs font-bold text-blue-600">
                  {calculateDday(bid.endDate)}
                </span>
              </div>
            </div>
            
            <div className="space-y-2 text-sm">
              <div>
                <span className="font-medium">발주기관:</span> {bid.organization}
              </div>
              <div>
                <span className="font-medium">예산금액:</span> {formatCurrency(bid.budget)}
              </div>
              <div>
                <span className="font-medium">입찰방식:</span> {bid.type}
              </div>
              <div>
                <span className="font-medium">공고기간:</span> {formatDate(bid.startDate)} ~ {formatDate(bid.endDate)}
              </div>
              <div>
                <span className="font-medium">참여업체:</span> {bid.participants}개사
              </div>
              <div>
                <span className="font-medium">지역:</span> {bid.location}
              </div>
            </div>
            
            <div className="mt-4 flex gap-2">
              <button className="btn btn-primary text-sm">
                공고상세
              </button>
              <button className="btn btn-secondary text-sm">
                관심등록
              </button>
              <button className="btn btn-secondary text-sm">
                참가신청
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* 페이지네이션 */}
      {paginatedBiddings.totalPages > 1 && (
        <div className="flex justify-center items-center gap-2">
          <button
            className="px-3 py-1 rounded bg-gray-200 disabled:opacity-50"
            disabled={currentPage === 1}
            onClick={() => setCurrentPage(prev => prev - 1)}
          >
            이전
          </button>
          
          <div className="flex gap-1">
            {Array.from({ length: paginatedBiddings.totalPages }, (_, i) => {
              const page = i + 1;
              const isActive = page === currentPage;
              const shouldShow = 
                page === 1 || 
                page === paginatedBiddings.totalPages || 
                Math.abs(page - currentPage) <= 1;
              
              if (!shouldShow && page !== 2 && page !== paginatedBiddings.totalPages - 1) {
                return null;
              }
              
              if (!shouldShow) {
                return <span key={page}>...</span>;
              }
              
              return (
                <button
                  key={page}
                  className={`px-3 py-1 rounded ${
                    isActive ? 'bg-blue-500 text-white' : 'bg-gray-200'
                  }`}
                  onClick={() => setCurrentPage(page)}
                >
                  {page}
                </button>
              );
            })}
          </div>
          
          <button
            className="px-3 py-1 rounded bg-gray-200 disabled:opacity-50"
            disabled={currentPage === paginatedBiddings.totalPages}
            onClick={() => setCurrentPage(prev => prev + 1)}
          >
            다음
          </button>
        </div>
      )}

      {/* 결과가 없을 때 */}
      {searchFiltered.length === 0 && (
        <div className="text-center py-12 text-gray-500">
          검색 결과가 없습니다.
        </div>
      )}
    </div>
  );
}