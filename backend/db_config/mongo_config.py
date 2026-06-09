import os
from pathlib import Path
from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv(dotenv_path=Path(__file__).resolve().parents[1] / ".env")

client = MongoClient(os.environ["MONGODB_URL"])
db = client[os.environ["MONGO_NAME"]]

try:
    client.admin.command("ping")
    print(f"✅ Connected to MongoDB: {os.environ['MONGO_NAME']}")
except Exception as e:
    print(f"❌ MongoDB connection failed: {e}")
    raise
