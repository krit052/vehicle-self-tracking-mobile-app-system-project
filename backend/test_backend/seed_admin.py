"""
Seed the admin user into MongoDB.
Run: python seed_admin.py
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

admin_user = {
    "name": "admin",
    "email": "admin@lamduan.mfu.ac.th",
    "password": hashed,
    "role": "admin",
}

result = users.update_one(
    {"name": admin_user["name"]},
    {"$set": admin_user},
    upsert=True,
)

if result.upserted_id:
    print(f"✅ Created admin user: {admin_user['name']}")
else:
    print(f"✅ Updated admin user: {admin_user['name']}")

print(f"   name     : {admin_user['name']}")
print(f"   email    : {admin_user['email']}")
print(f"   role     : {admin_user['role']}")
print(f"   password : 1234  (stored as bcrypt hash)")
