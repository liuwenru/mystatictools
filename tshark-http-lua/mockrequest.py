import ssl
import requests
#from requests.adapters import HTTPAdapter

# 该文件主要用于测试python访问带有https和http网站时能否正常抓包解密操作，对于python程序需要export SSLKEYLOGFILE=/root/python-tls.keys 开启记录https协商的密钥信息

#ctx = ssl.create_default_context()
#ctx.keylog_filename = "/root/python-tls.keys"


# class KeyLogAdapter(HTTPAdapter):
#     def init_poolmanager(self, *args, **kwargs):
#         context = ssl.create_default_context()
#         context.keylog_filename = "/tmp/python-tls.keys"
#         kwargs["ssl_context"] = context
#         return super().init_poolmanager(*args, **kwargs)


session = requests.Session()
#session.mount("https://", KeyLogAdapter())

#response = session.get(
#    "https://oa.epoint.com.cn/epointoa9/frame/pages/login/login",
#    headers={"Accept-Encoding": "identity"},
#)
response = session.get(
    "https://fdoc.epoint.com.cn:3366/",
    headers={"Accept-Encoding": "identity"},
)
print(response.status_code)
