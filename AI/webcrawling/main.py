from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
import time
import requests
from PIL import Image
from io import BytesIO
import os

# 크롬 드라이버 경로 설정
chrome_driver_path = 'D:/forfun/AI/webcrawling/chromedriver-win64/chromedriver.exe'  # 이곳에 chromedriver 경로를 설정하세요.

# 크롬 드라이버 설정
chrome_options = Options()
chrome_options.add_argument("--headless")  # 헤드리스 모드 (브라우저 창을 띄우지 않음)
service = Service(chrome_driver_path)
driver = webdriver.Chrome(service=service, options=chrome_options)

# 사이트 열기
url = "https://www.google.com/"
driver.get(url)

# 페이지 로딩 대기
time.sleep(3)

# 이미지 크롤링 (이미지 URL 찾기)
image_urls = []
images = driver.find_elements(By.TAG_NAME, 'img')

for img in images:
    img_url = img.get_attribute('src')
    if img_url:
        image_urls.append(img_url)

# 이미지 저장폴더더
if not os.path.exists('images'):
    os.makedirs('images')

# 이미지를 로컬에 저장
for index, img_url in enumerate(image_urls):
    try:
        response = requests.get(img_url)
        img = Image.open(BytesIO(response.content))
        if img.mode == "RGBA":
            img.save(f"./images/image_{index + 1}.png")
        elif img.mode == "RGB":
            img.save(f"./images/image_{index + 1}.jpg")
    except Exception as e:
        print(f"Error downloading image {img_url}: {e}")

# 크롬 드라이버 종료
driver.quit()

print(f"총 {len(image_urls)}개의 이미지를 다운로드 했습니다.")