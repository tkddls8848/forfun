from fastapi import FastAPI, File, UploadFile
import uvicorn
import fitz  # PyMuPDF
from transformers import pipeline

# PDF에서 텍스트를 추출하는 함수
def extract_text_from_pdf(pdf_path):
    doc = fitz.open(pdf_path)
    text = ""
    for page in doc:
        text += page.get_text()
    return text

# Llama3 모델 로드 (여기서는 예제 BERT 사용. 실제 Llama3 모델로 교체하십시오)
model_name = "bert-base-uncased"  # "llama3-model-name"
qa_pipeline = pipeline("question-answering", model=model_name, tokenizer=model_name, framework="pt")

# FastAPI 애플리케이션 정의
app = FastAPI()

# 업로드된 PDF의 텍스트를 저장할 변수
document_text = ""

@app.post("/upload_pdf/")
async def upload_pdf(file: UploadFile = File(...)):
    global document_text
    try:
        contents = await file.read()
        with open("temp.pdf", "wb") as temp_pdf:
            temp_pdf.write(contents)
        document_text = extract_text_from_pdf("temp.pdf")
        return {"message": "PDF uploaded and processed successfully"}
    except Exception as e:
        return {"error": str(e)}

@app.get("/ask/")
async def ask_question(question: str):
    if not document_text:
        return {"error": "No document uploaded"}
    answer = qa_pipeline(question=question, context=document_text)
    return {"answer": answer["answer"]}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)