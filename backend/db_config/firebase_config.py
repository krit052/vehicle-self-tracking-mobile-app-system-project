import os

import firebase_admin
from firebase_admin import credentials

_KEY_PATH = os.path.join(os.path.dirname(__file__), "firebase-adminsdk-key-fbsvc-a8c8f167bd.json")

cred = credentials.Certificate(_KEY_PATH)
firebase_admin.initialize_app(cred)