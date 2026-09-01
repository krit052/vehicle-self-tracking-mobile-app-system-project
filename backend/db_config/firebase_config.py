import json
import os

import firebase_admin
from firebase_admin import credentials

_KEY_PATH = os.path.join(os.path.dirname(__file__), "firebase-adminsdk-key-fbsvc-a8c8f167bd.json")
_KEY_JSON_ENV = os.environ.get("FIREBASE_ADMINSDK_JSON")

# บน cloud (Railway ฯลฯ) ไฟล์ key นี้จะไม่ถูก deploy ไปด้วย (อยู่ใน .gitignore)
# จึงอ่านจาก env var FIREBASE_ADMINSDK_JSON (เนื้อไฟล์ JSON ทั้งก้อน) แทน ถ้ามี
# ถ้าไม่มี (dev บนเครื่อง) ก็ fallback ไปอ่านไฟล์ในเครื่องตามเดิม
if _KEY_JSON_ENV:
    cred = credentials.Certificate(json.loads(_KEY_JSON_ENV))
else:
    cred = credentials.Certificate(_KEY_PATH)

firebase_admin.initialize_app(cred)