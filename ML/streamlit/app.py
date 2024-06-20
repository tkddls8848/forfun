import streamlit as st
import requests

if st.button("Send message"):
    response = requests.get("http://localhost:5000/test")

    if response.status_code == 200:
        st.success("success : " + response.text)
    else:
        st.warning("something wrong")