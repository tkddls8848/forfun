from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.common.by import By
from webdriver_manager.chrome import ChromeDriverManager
from bs4 import BeautifulSoup
import time

# 크롬 드라이버 설정
options = webdriver.ChromeOptions()
options.add_argument("--headless")  # 브라우저 창을 띄우지 않음 (필요시 주석 처리)
options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")

# WebDriver 실행
service = Service(ChromeDriverManager().install())
driver = webdriver.Chrome(service=service, options=options)

# 접속할 웹사이트 URL
url = "https://www.coupang.com/vp/products/6711584577?itemId=11357234579&vendorItemId=86285706868&pickType=COU_PICK&q=%EC%93%B0%EB%A6%AC%EC%84%B8%EB%B8%90+%EC%86%90%ED%86%B1%EA%B9%8E%EC%9D%B4&itemsCount=36&searchId=dacea52e3951947&rank=2&searchRank=2&isAddedCart="  # 원하는 사이트 주소로 변경

try:
    driver.get(url)  # 웹사이트 접속
    time.sleep(3)  # 페이지 로딩 대기

    # BeautifulSoup으로 HTML 파싱
    soup = BeautifulSoup(driver.page_source, "html.parser")
    # 파일로 저장
    with open("output.html", "w", encoding="utf-8") as file:
        file.write(soup.prettify())  # 보기 좋게 저장

    # HTML 계층 구조를 따라가면서 탐색
    body = soup.find("html", class_="product renewal")
    contents = body.find("section", id="contents") if body else None
    prod_atf = contents.find("div", class_="prod-atf") if contents else None
    prod_atf_main = prod_atf.find("div", class_="prod-atf-main") if prod_atf else None
    prod_image = prod_atf_main.find("div", class_="prod-image") if prod_atf_main else None

    # 하위 내용 추출
    if prod_image:
        # 텍스트 추출
        pass
    else:
        print("prod-image 태그를 찾을 수 없습니다.")

finally:
    driver.quit()  # WebDriver 종료
