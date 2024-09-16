import fitz  # PyMuPDF
from transformers import pipeline

def extract_text_from_pdf(pdf_path):
    doc = fitz.open(pdf_path)
    text = ""
    for page in doc:
        text += page.get_text()
    return text

extract_text_from_pdf("./SR650V3.pdf")

model_name = "bert-base-uncased"
qa_pipeline = pipeline("question-answering", model=model_name, framework="pt")
