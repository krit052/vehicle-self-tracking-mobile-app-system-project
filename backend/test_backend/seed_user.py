"""
Seed a test user into local MongoDB.
Run: python seed_user.py
"""

from pathlib import Path
from dotenv import load_dotenv
import os

load_dotenv(dotenv_path=Path(__file__).parent.parent / ".env")

import bcrypt
from pymongo import MongoClient

client = MongoClient(os.environ["MONGODB_URL"])
db = client[os.environ["MONGO_NAME"]]
users = db["users"]

hashed = bcrypt.hashpw("1234".encode(), bcrypt.gensalt()).decode()

test_user = {
    "name": "test",
    "email": "test@lamduan.mfu.ac.th",
    "password": hashed,
}

result = users.update_one(
    {"email": test_user["email"]},
    {"$set": test_user},
    upsert=True,
)

if result.upserted_id:
    print(f"✅ Created user: {test_user['email']}")
else:
    print(f"✅ Updated user: {test_user['email']}")

print(f"   name     : {test_user['name']}")
print(f"   email    : {test_user['email']}")
print(f"   password : 1234  (stored as bcrypt hash)")
