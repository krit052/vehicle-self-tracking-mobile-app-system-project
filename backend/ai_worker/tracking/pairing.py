#ย้าย logic การจับคู่คนกับรถออกมาเป็นไฟล์ใหม่ backend/ai_worker/tracking/pairing.py เพื่อให้โค้ดใน main.py สะอาดขึ้น
import time
from enum import Enum
from typing import Dict, List, Optional, Tuple
import tracking.tracker as trk
import utils as utl
import config as cfg

class PairState(Enum):
    RIDING = "riding"
    DISMOUNTED = "dismounted"

class PairRecord:
    def __init__(self, person_id: int, motorcycle_id: int):
        self.person_id = person_id
        self.motorcycle_id = motorcycle_id
        self.state = PairState.RIDING
        self.alert_sent = False
        self.last_dist_m = 0.0
        self.plate_text = "-"  # 💡 บันทึกป้ายทะเบียนฝังไว้ในคู่ ป้องกันการเป็นค่าว่างตอนรถหายไปจากจอ
        self.last_updated = time.time()

class PairStateManager:
    def __init__(self, ttl_seconds: float = 30.0):
        self.pairs: Dict[Tuple[int, int], PairRecord] = {}
        self.ttl_seconds = ttl_seconds

    def _evict_stale(self):
        now = time.time()
        stale = [k for k, v in self.pairs.items() if now - v.last_updated > self.ttl_seconds]
        for k in stale:
            print(f"[PairState] Evict stale pair person={k[0]} moto={k[1]}")
            del self.pairs[k]

    def update(
        self,
        people: List[trk.SimpleTrack],
        motorcycles: List[trk.SimpleTrack],
        # license_plate_text: str = "",
    ) -> List[dict]:
        self._evict_stale()
        now = time.time()
        alerts: List[dict] = []

        paired_person_ids = {k[0] for k in self.pairs}
        paired_moto_ids = {k[1] for k in self.pairs}

        # ── Step 1: อัปเดตข้อมูลคู่เดิมอย่างต่อเนื่อง (ไม่ใช้บรรทัด continue ตัดหน้าอีกต่อไป) ──
        for (pid, mid), pair in list(self.pairs.items()):
            person = next((p for p in people if p.track_id == pid), None)
            moto = next((m for m in motorcycles if m.track_id == mid), None)

            is_person_visible = person is not None and person.missed == 0
            is_moto_visible = moto is not None and moto.missed == 0

            # สืบทอดข้อมูลป้ายทะเบียนล่าสุดเข้าไปเก็บใน Pair ความทรงจำระยะยาว
            if pair.plate_text == "-" and moto and getattr(moto, 'plate_text', "-") != "-":
                # ถ้า AI อ่านป้ายได้และจับคู่ให้รถคันนี้แล้ว ให้อัปเดตเข้า Pair
                pair.plate_text = moto.plate_text
            # elif license_plate_text and is_moto_visible:
            #     pair.plate_text = license_plate_text

            if is_person_visible and is_moto_visible:
                pair.last_updated = now
                dist_m = utl.euclidean(person.center, moto.center) / cfg.PIXELS_PER_METER
                pair.last_dist_m = dist_m

                if pair.state == PairState.RIDING:
                    if dist_m > cfg.NEAR_DISTANCE_M:
                        pair.state = PairState.DISMOUNTED
                        print(f"[PairState] ({pid},{mid}) RIDING → DISMOUNTED dist={dist_m:.2f}m")
                elif pair.state == PairState.DISMOUNTED:
                    if dist_m <= cfg.NEAR_DISTANCE_M:
                        pair.state = PairState.RIDING
                        pair.alert_sent = False
                        print(f"[PairState] ({pid},{mid}) DISMOUNTED → RIDING (returned)")
            else:
                # 💡 หากคนหรือรถหายไปชั่วคราว ให้คงระยะและสถานะล่าสุดไว้เพื่อประเมินผล Alert
                if is_person_visible or is_moto_visible:
                    pair.last_updated = now

            # 🎯 ตรรกะประมวลผล ALERT ที่แยกตัวเป็นอิสระ ป้องกันการโดนหลุดข้ามค้าง
            if pair.state == PairState.DISMOUNTED and pair.last_dist_m >= cfg.ALERT_DISTANCE_M:
                if not pair.alert_sent:
                    pair.alert_sent = True
                    alerts.append({
                        "status": f"ALERT: person moved {cfg.ALERT_DISTANCE_M}m+ from motorcycle",
                        "distance_m": round(pair.last_dist_m, 2),
                        "person_track_id": pid,
                        "motorcycle_track_id": mid,
                        "license_plate_text": pair.plate_text,
                    })

        # ── Step 2: จับคู่ใหม่ให้วัตถุที่ยังว่างอยู่ ──
        unpaired_people = [p for p in people if p.track_id not in paired_person_ids]
        unpaired_motos = [m for m in motorcycles if m.track_id not in paired_moto_ids]

        used_moto_ids = set()
        for person in unpaired_people:
            nearest_moto: Optional[trk.SimpleTrack] = None
            nearest_dist_m = float("inf")

            for moto in unpaired_motos:
                if moto.track_id in used_moto_ids:
                    continue
                dist_m = utl.euclidean(person.center, moto.center) / cfg.PIXELS_PER_METER
                if dist_m < nearest_dist_m:
                    nearest_dist_m = dist_m
                    nearest_moto = moto

            if nearest_moto is not None and nearest_dist_m <= cfg.NEAR_DISTANCE_M:
                key = (person.track_id, nearest_moto.track_id)
                record = PairRecord(person.track_id, nearest_moto.track_id)
                if nearest_moto.plate_text != "-":
                    record.plate_text = nearest_moto.plate_text
                self.pairs[key] = record
                used_moto_ids.add(nearest_moto.track_id)
                print(f"[PairState] New pair person={person.track_id} moto={nearest_moto.track_id} dist={nearest_dist_m:.2f}m → RIDING")

        return alerts