import firebase_admin
from firebase_admin import credentials
 

cred = credentials.Certificate("firebase-adminsdk-key-fbsvc-a8c8f167bd.json")
firebase_admin.initialize_app(cred)