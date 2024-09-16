from binance import Client
from dotenv import load_dotenv
import pandas as pd
import os


def main(public_key, secret_key):
    client = Client(api_key=public_key, api_secret=secret_key, tld="com")

    for balance in client.get_account()['balances']:
        if float(balance['free']) != 0:
            print(balance)
    
    df = pd.DataFrame(client.get_all_tickers())
    print(df[df.symbol.str.endswith("USDT")])
    df_24 = client.get_ticker(symbol="BTCUSDT")
    for k, v in df_24.items():
        print(k, v)

if __name__ == "__main__":
    load_dotenv()
    public_key = os.getenv("api_key")
    secret_key = os.getenv("secret_key")
    main(public_key, secret_key)