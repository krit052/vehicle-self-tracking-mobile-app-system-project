import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))

from db_config.mongo_config import client, db

client.admin.command("ping")
print("Connected.")

collection = db["test_collection"]

result = collection.insert_one({"name": "test_vehicle", "status": "active"})
print(f"Inserted: {result.inserted_id}")

doc = collection.find_one({"name": "test_vehicle"})
print(f"Found: {doc}")

collection.update_one({"name": "test_vehicle"}, {"$set": {"status": "inactive"}})
print("Updated.")

collection.delete_one({"name": "test_vehicle"})
print("Deleted.")

print("\nAll CRUD operations passed.")
