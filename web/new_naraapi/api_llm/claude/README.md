# 나라장터 API 연동 프로그램

이 프로그램은 사용자의 자연어 질의를 기반으로 조달청 나라장터 API URL을 생성하고 호출하는 Python 애플리케이션입니다.

## 구조

프로젝트는 다음과 같은 파일로 구성되어 있습니다:

- `main.py`: 프로그램 진입점
- `app.py`: 주 애플리케이션 클래스
- `document_loader.py`: API 문서를 로드하고 포맷팅하는 클래스
- `claude_client.py`: Claude API와 상호작용하는 클래스
- `url_processor.py`: URL 추출 및 처리 클래스
- `api_client.py`: API 호출 및 결과 처리 클래스

## 설치 방법

1. 필요한 패키지 설치:
```bash
pip install anthropic requests python-dotenv
```

2. 환경 변수 설정:
`.env` 파일을 생성하고 다음 내용을 추가합니다:
```
ANTHROPIC_API_KEY=your_api_key_here
```

3. API 문서 준비:
`api_docs` 디렉토리를 생성하고 API 문서 파일(.txt 또는 .md)을 해당 디렉토리에 넣습니다.

## 사용 방법

1. 프로그램 실행:
```bash
python main.py
```

2. 자연어로 질의 입력:
예) "입찰 공고 정보를 가져오고 싶어요"

3. 프로그램이 Claude AI를 통해 적절한 API URL을 생성합니다.

4. 생성된 URL을 사용하여 API를 호출하고 결과를 확인할 수 있습니다.

5. 결과를 파일로 저장할 수 있습니다.

## 클래스 설명

### App
- `__init__(api_key, docs_dir)`: 초기화 함수
- `initialize()`: 프로그램 환경 초기화
- `process_user_query(query)`: 사용자 질의 처리
- `handle_api_result(api_result)`: API 호출 결과 처리
- `run()`: 메인 프로그램 실행

### DocumentLoader
- `load_api_documents()`: API 문서 파일 로드
- `format_documents_for_claude(documents)`: Claude 포맷으로 변환
- `prepare_context()`: 문서 컨텍스트 준비

### ClaudeClient
- `query_claude(context, user_query)`: Claude API 호출

### UrlProcessor
- `extract_url_from_result(result)`: Claude 응답에서 URL 추출

### ApiClient
- `call_api(url)`: API 호출
- `save_result_to_file(api_result, filename)`: 결과를 파일로 저장

## 코드 흐름

1. 사용자가 자연어 질의를 입력
2. DocumentLoader가 API 문서를 로드
3. ClaudeClient가 문서와 질의를 기반으로 응답 생성
4. UrlProcessor가 응답에서 URL 추출
5. ApiClient가 URL을 호출하고 결과 반환
6. 결과를 화면에 표시하고 선택적으로 파일로 저장