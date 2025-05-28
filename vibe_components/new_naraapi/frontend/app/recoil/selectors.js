'use client';

import { selector } from 'recoil';
import { queryState } from './atoms';

// 쿼리 결과 포맷팅
export const formattedQueryResult = selector({
  key: 'formattedQueryResult',
  get: ({ get }) => {
    const query = get(queryState);
    if (!query.result) return null;

    // 결과 포맷팅 로직
    return {
      ...query.result,
      timestamp: new Date().toISOString(),
    };
  },
});

// 쿼리 상태 요약
export const querySummary = selector({
  key: 'querySummary',
  get: ({ get }) => {
    const query = get(queryState);
    return {
      isProcessing: query.isLoading,
      hasError: !!query.error,
      hasResult: !!query.result,
      endpoint: query.endpoint,
      model: query.model,
    };
  },
}); 