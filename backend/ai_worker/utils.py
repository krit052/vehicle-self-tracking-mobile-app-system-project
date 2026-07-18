
#เก็บพวกฟังก์ชันที่ใช้บ่อยๆ เอาไว้ตรงนี้
from typing import Optional, Tuple

def euclidean(a: Tuple[float, float], b: Tuple[float, float]) -> float:
    return float(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5)

def bbox_bottom_center(det: dict) -> Optional[Tuple[float, float]]:
    try:
        x = float(det["x"])
        y = float(det["y"])
        h = float(det["height"])
        return x, y + h / 2.0
    except Exception:
        return None
