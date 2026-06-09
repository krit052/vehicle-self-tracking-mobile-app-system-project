import pathlib

import firebase_admin
from firebase_admin import credentials

ROOT_DIR = pathlib.Path(__file__).resolve().parent
cred_path = ROOT_DIR / "firebase-adminsdk-key-fbsvc-a8c8f167bd.json"
cred = credentials.Certificate(str(cred_path))
firebase_admin.initialize_app(cred)
