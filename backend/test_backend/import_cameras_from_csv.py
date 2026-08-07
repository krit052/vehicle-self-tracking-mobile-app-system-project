# -*- coding: utf-8 -*-
"""
Import กล้องจาก backend/cctv/RTSP-CCTV-new.csv เข้า MongoDB collection `cameras`
(ทาง A — ให้ MongoDB เป็นแหล่งข้อมูลกล้องเดียวของทั้งระบบ)

- upsert ด้วย name (idempotent รันซ้ำได้ ไม่เพิ่มตัวซ้ำ)
- rtsp_url / location_name(POSITION) / ip = อัปเดตจาก CSV ทุกครั้ง
- latitude/longitude/located/status/created_at = ตั้งเฉพาะตอน insert ครั้งแรก
  (พิกัด placeholder = ใจกลาง มฟล. รอ admin ไปปักจริงบนแผนที่ → located=False
   จะถูกซ่อนจากแผนที่ฝั่ง user จนกว่าจะปักพิกัด)

รัน:  ./venv/Scripts/python.exe import_cameras_from_csv.py
ลบที่ import: ./venv/Scripts/python.exe import_cameras_from_csv.py --undo
"""
import csv
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv
from pymongo import MongoClient

sys.stdout.reconfigure(encoding="utf-8")

_HERE = Path(__file__).parent
load_dotenv(_HERE.parent / ".env")
CSV_PATH = (_HERE.parent / "cctv" / "RTSP-CCTV-new.csv").resolve()

MFU_LAT, MFU_LON = 20.0459, 99.8934  # placeholder — admin ไปปักจริงทีหลัง

NAME_COL, RTSP_COL, ENABLE_COL, POSITION_COL, IP_COL = (
    "CAMERA NAME_NEW", "RTSP", "enable rtsp", "POSITION", "IP ADDRESS",
)

db = MongoClient(os.environ["MONGODB_URL"])[os.environ["MONGO_NAME"]]
cameras = db["cameras"]


def read_rows():
    for enc in ("utf-8-sig", "cp874"):
        try:
            with CSV_PATH.open("r", encoding=enc, newline="") as f:
                return list(csv.DictReader(f))
        except UnicodeDecodeError:
            continue
    raise RuntimeError(f"decode failed: {CSV_PATH}")


def do_import():
    now = datetime.now(timezone.utc)
    inserted = updated = skipped = 0
    for row in read_rows():
        name = (row.get(NAME_COL) or "").strip()
        rtsp = (row.get(RTSP_COL) or "").strip()
        enabled = (row.get(ENABLE_COL) or "").strip().lower() == "ok"
        if not name or not rtsp or not enabled:
            skipped += 1
            continue
        res = cameras.update_one(
            {"name": name},
            {
                "$set": {
                    "rtsp_url": rtsp,
                    "location_name": (row.get(POSITION_COL) or "").strip(),
                    "ip": (row.get(IP_COL) or "").strip(),
                    "source": "csv-import",
                },
                "$setOnInsert": {
                    "latitude": MFU_LAT,
                    "longitude": MFU_LON,
                    "located": False,
                    "status": "active",
                    "created_at": now,
                },
            },
            upsert=True,
        )
        if res.upserted_id is not None:
            inserted += 1
        else:
            updated += 1
    print(f"✅ import done — inserted:{inserted}  updated:{updated}  skipped:{skipped}")
    print(f"   total cameras now: {cameras.count_documents({})}")
    print(f"   located (บนแผนที่ user): {cameras.count_documents({'located': {'$ne': False}})}")


def do_undo():
    n = cameras.delete_many({"source": "csv-import"}).deleted_count
    print(f"↩️  ลบกล้องที่ import จาก CSV แล้ว: {n} ตัว")


if __name__ == "__main__":
    if "--undo" in sys.argv:
        do_undo()
    else:
        do_import()
