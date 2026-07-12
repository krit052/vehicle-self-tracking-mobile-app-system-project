# โหลดรายชื่อกล้องจาก backend/cctv/RTSP-CCTV-new.csv
# เลือกกล้องที่จะรันด้วย ACTIVE_CAMERAS ใน .env (ชื่อตรงกับคอลัมน์ CAMERA NAME_NEW)

import csv
from pathlib import Path
from typing import Dict, List, NamedTuple

_HERE = Path(__file__).parent
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


def resolve_active_cameras(active_names: str, fallback_url: str = "") -> List[Camera]:
    """
    แปลงค่า ACTIVE_CAMERAS (คั่นด้วย comma) เป็นรายการกล้อง
    ถ้า ACTIVE_CAMERAS ว่าง จะถอยไปใช้ fallback_url (RTSP_URL / ไฟล์วิดีโอทดสอบ)
    """
    names = [n.strip() for n in active_names.split(",") if n.strip()]
    if not names:
        if not fallback_url:
            raise RuntimeError("Set ACTIVE_CAMERAS (or RTSP_URL for video-file testing) in .env")
        return [Camera(name="local", url=fallback_url, position="", ip="")]

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
