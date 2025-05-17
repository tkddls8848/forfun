import os

class DocumentLoader:
    """API 문서 파일을 로드하고 포맷팅하는 클래스"""
    
    def __init__(self, docs_dir):
        """초기화 함수
        
        Args:
            docs_dir (str): API 문서 파일이 저장된 디렉토리 경로
        """
        self.docs_dir = docs_dir
        
    def load_api_documents(self):
        """API 문서 파일들을 로드하여 리스트로 반환
        
        Returns:
            list: 문서 객체 리스트
        """
        documents = []
        
        for i, filename in enumerate(os.listdir(self.docs_dir)):
            if filename.endswith(".txt") or filename.endswith(".md"):
                with open(os.path.join(self.docs_dir, filename), 'r', encoding='utf-8') as file:
                    content = file.read()
                    documents.append({
                        "index": i + 1,
                        "source": filename,
                        "content": content
                    })
        
        return documents
    
    def format_documents_for_claude(self, documents):
        """Claude에 전달할 형식으로 문서 포맷팅
        
        Args:
            documents (list): 문서 객체 리스트
            
        Returns:
            str: Claude에 전달할 형식으로 포맷팅된 문서 문자열
        """
        formatted_docs = "<documents>"
        
        for doc in documents:
            formatted_docs += f"<document index=\"{doc['index']}\">\n"
            formatted_docs += f"<source>{doc['source']}</source>\n"
            formatted_docs += f"<document_content>{doc['content']}</document_content>\n"
            formatted_docs += "</document>\n"
        
        formatted_docs += "</documents>"
        return formatted_docs
    
    def prepare_context(self):
        """API 문서를 로드하고 Claude에 전달할 형식으로 포맷팅
        
        Returns:
            str: Claude에 전달할 형식의 문서 컨텍스트
        """
        documents = self.load_api_documents()
        return self.format_documents_for_claude(documents), len(documents)