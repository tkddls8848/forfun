# backend/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# CORS 설정 - 직접 요청을 허용하기 위해
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],  # Next.js 서버 주소
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/backend/hello")
async def hello():
    return {"message": "Hello from FastAPI Backend!"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)