import requests

def google_search_api(query, api_key, cx):
    base_url = "https://www.googleapis.com/customsearch/v1"

    params = {
        'q': query,
        'key': api_key,
        'cx': cx,
    }

    response = requests.get(base_url, params=params)
    print(response)
    if response.status_code == 200:
        results = response.json().get('items', [])

        for result in results[:5]:  # 상위 5개 결과만 출력
            title = result.get('title', '제목 없음')
            link = result.get('link', 'URL 없음')
            print(f"제목: {title}")
            print(f"URL: {link}\n")
    else:
        print(f"Failed to retrieve search results. Status Code: {response.status_code}")

# API 키와 Custom Search Engine ID(cx) 설정
api_key = 'AIzaSyBSTRr7TlCOmvVrDaT-En6y03qDOrRyVVs'
cx = 'AIzaSyBSTRr7TlCOmvVrDaT-En6y03qDOrRyVVs'

# 검색어 설정
search_query = "오늘의 IT 인프라 뉴스"

# Google 검색 결과 가져오기
google_search_api(search_query, api_key, cx)