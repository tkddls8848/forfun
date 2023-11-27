from openai import OpenAI
from dotenv import load_dotenv
import argparse
import os

PROMPT = """
파일에 대한 코드 리뷰를 만들어줘, 스타일을 개선하기 위해 변경해야 할 사항을 표시해줘.
성능, 가독성, 유지보수 가능성을 고려한 코드로 점검해줘.
코드를 개선하기 위해 도입 할 수 있는, 괜찮은 라이브러리가 있으면 제안해줘.
건설적으로 대답해줘.
"""


def request_code_review (filecontent, model_type):
    message = [
        {"role": "system", "content": PROMPT},
        {"role": "user", "content": f"제공하는 파일의 코드 리뷰: {filecontent}"}
    ]
    response = client.chat.completions.create(
        model=model_type,
        messages=message
    )
    return response.choices[0].message.content


def request_code(filepath, model_type):
    with open(filepath, encoding="UTF-8") as file:
        content = file.read()
    generate_request_code_review = request_code_review(content, model_type)
    return generate_request_code_review


def main():
    parser = argparse.ArgumentParser(description="code review by chatGPT")
    parser.add_argument("file")
    parser.add_argument("--model", default="gpt-4")
    args = parser.parse_args()
    answer = request_code(args.file, args.model)
    print(answer)


if __name__ == "__main__":
    load_dotenv()
    api_key = os.getenv("OPENAI_API_KEY")
    client = OpenAI()
    main()
