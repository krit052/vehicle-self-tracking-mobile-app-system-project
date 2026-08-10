# โหลดรายชื่อกล้องที่จะรัน ตามลำดับ:
#   1) ACTIVE_CAMERAS ใน .env มีชื่อ → อ่านจาก backend/cctv/RTSP-CCTV-new.csv (โหมดกำหนดเอง/เทสต์)
#   2) ACTIVE_CAMERAS ว่าง → รัน "กล้องที่ปักหมุดในแอป admin" (located=True) จาก MongoDB อัตโนมัติ
#   3) ต่อ Mongo ไม่ได้/ไม่มีข้อมูล → ถอยไปใช้ RTSP_URL (ไฟล์วิดีโอทดสอบ)

import csv
import os
from pathlib import Path
from typing import Dict, List, NamedTuple

from dotenv import load_dotenv

_HERE = Path(__file__).parent
# โหลด .env ให้ใช้ MONGODB_URL/MONGO_NAME ได้ แม้เรียก cameras.py แบบ standalone
load_dotenv(_HERE / ".env")
CSV_PATH = (_HERE / ".." / "cctv" / "RTSP-CCTV-new.csv").resolve()

NAME_COL = "CAMERA NAME_NEW"
RTSP_COL = "RTSP"
ENABLE_COL = "enable rtsp"
POSITION_COL = "POSITION"
IP_COL = "IP ADDRESS"


class Camera(NamedTuple):
    name: str
    url: str
    position: str
    ip: str


def _read_rows(path: Path) -> List[dict]:
    for encoding in ("utf-8-sig", "cp874"):
        try:
            with path.open("r", encoding=encoding, newline="") as f:
                return list(csv.DictReader(f))
        except UnicodeDecodeError:
            continue
    raise RuntimeError(f"Could not decode {path} as utf-8 or cp874")


def load_camera_catalog(path: Path = CSV_PATH) -> Dict[str, Camera]:
    """อ่าน CSV แล้วคืน dict ของกล้องที่ enable rtsp = ok, key = CAMERA NAME_NEW"""
    if not path.exists():
        raise RuntimeError(f"Camera CSV not found: {path}")

    catalog: Dict[str, Camera] = {}
    for row in _read_rows(path):
        name = (row.get(NAME_COL) or "").strip()
        url = (row.get(RTSP_COL) or "").strip()
        enabled = (row.get(ENABLE_COL) or "").strip().lower() == "ok"
        if not name or not url or not enabled:
            continue
        catalog[name] = Camera(
            name=name,
            url=url,
            position=(row.get(POSITION_COL) or "").strip(),
            ip=(row.get(IP_COL) or "").strip(),
        )
    return catalog


def _load_pinned_cameras_from_mongo() -> List[Camera]:
    """ดึงกล้องที่ admin 'ปักหมุดแล้ว' (located != False) จาก MongoDB
    ใช้ตอน ACTIVE_CAMERAS ว่าง → ai_worker รันตามที่ปักในแอป admin อัตโนมัติ
    ต้องมี MONGODB_URL / MONGO_NAME ใน .env (มีอยู่แล้ว) — คืน [] ถ้าต่อไม่ได้/ไม่มีข้อมูล"""
    mongo_url = os.environ.get("MONGODB_URL", "").strip()
    mongo_name = os.environ.get("MONGO_NAME", "").strip()
    if not mongo_url or not mongo_name:
        return []
    try:
        from pymongo import MongoClient

        client = MongoClient(mongo_url, serverSelectionTimeoutMS=5000)
        try:
            docs = client[mongo_name]["cameras"].find({"located": {"$ne": False}})
            cameras: List[Camera] = []
            for d in docs:
                name = (d.get("name") or "").strip()
                url = (d.get("rtsp_url") or "").strip()
                if not name or not url:
                    continue
                cameras.append(
                    Camera(
                        name=name,
                        url=url,
                        position=(d.get("location_name") or "").strip(),
                        ip=(d.get("ip") or "").strip(),
                    )
                )
            return cameras
        finally:
            client.close()
    except Exception as e:
        print(f"[cameras] อ่านกล้องที่ปักหมุดจาก Mongo ไม่ได้ ({e!r}) — ถอยไปใช้ RTSP_URL")
        return []


def resolve_active_cameras(active_names: str, fallback_url: str = "") -> List[Camera]:
    """
    เลือกกล้องที่จะรัน ตามลำดับ:
      1) ACTIVE_CAMERAS มีชื่อ → อ่านจาก CSV ตามชื่อ (โหมดกำหนดเอง/เทสต์)
      2) ACTIVE_CAMERAS ว่าง → รัน "กล้องที่ปักหมุดในแอป admin" (located=True) จาก Mongo อัตโนมัติ
      3) Mongo ไม่มี/ต่อไม่ได้ → ถอยไปใช้ fallback_url (RTSP_URL / ไฟล์วิดีโอทดสอบ)
    """
    names = [n.strip() for n in active_names.split(",") if n.strip()]

    if names:
        catalog = load_camera_catalog()
        cameras: List[Camera] = []
        missing: List[str] = []
        for name in names:
            camera = catalog.get(name)
            if camera is None:
                missing.append(name)
            else:
                cameras.append(camera)
        if missing:
            raise RuntimeError(
                f"ACTIVE_CAMERAS not found in {CSV_PATH.name}: {', '.join(missing)}\n"
                f"Available: {', '.join(sorted(catalog))}"
            )
        return cameras

    # ACTIVE_CAMERAS ว่าง → โหมด auto: รันตามกล้องที่ปักหมุดในแอป admin
    pinned = _load_pinned_cameras_from_mongo()
    if pinned:
        return pinned

    if fallback_url:
        return [Camera(name="local", url=fallback_url, position="", ip="")]

    raise RuntimeError(
        "ไม่มีกล้องให้รัน: ตั้ง ACTIVE_CAMERAS ใน .env, "
        "หรือปักหมุดกล้องในแอป admin, หรือใส่ RTSP_URL (ทดสอบไฟล์วิดีโอ)"
    )
