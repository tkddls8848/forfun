export async function fetchData(url, options = {}) {
  try {
    const response = await fetch(url, options);
    if (!response.ok) {
      const errorData = await response.json().catch(() => ({ detail: '알 수 없는 오류' }));
      throw new Error(`서버 응답 오류: ${response.status} - ${errorData.detail}`);
    }
    return response.json();
  } catch (error) {
    console.error('Fetch error:', error);
    throw error; // 오류를 다시 던져서 호출하는 쪽에서 처리할 수 있도록 함
  }
}