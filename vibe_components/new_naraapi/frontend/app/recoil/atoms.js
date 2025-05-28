'use client';

import { atom } from 'recoil';

// 쿼리 상태
export const queryState = atom({
  key: 'queryState',
  default: {
    query: '',
    endpoint: 'query_claude',
    model: 'gpt-4-0125-preview',
    temperature: 0.7,
    maxTokens: 500,
    isLoading: false,
    error: null,
    result: null,
  },
});

// UI 상태
export const uiState = atom({
  key: 'uiState',
  default: {
    isDarkMode: false,
    sidebarOpen: true,
  },
}); 