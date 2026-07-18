#ย้าย simple tracker ออกมาเป็นไฟล์ใหม่ backend/ai_worker/tracker.py เพื่อให้โค้ดใน main.py สะอาดขึ้น
import time
from typing import Dict, List, Tuple
from utils import euclidean, bbox_bottom_center

class SimpleTrack:
    def __init__(self, track_id: int, cls: str, center: Tuple[float, float], bbox: dict):
        self.track_id = track_id
        self.cls = cls
        self.center = center
        self.bbox = bbox
        self.last_seen = time.time()
        self.was_near_motorcycle = False
        self.plate_text: str = "-"  # 💡 มีค่าตั้งต้นเป็น string ป้องกันการเจอบั๊กข้อมูลว่างเปล่า
        self.age: int = 1
        self.missed: int = 0

class SimpleTracker:
    def __init__(self, max_distance_px: float = 160, ttl_frames: int = 5):
        self.max_distance_px = max_distance_px
        self.ttl_frames = ttl_frames
        self.next_id = 1
        self.tracks: Dict[int, SimpleTrack] = {}

    def update(self, detections: List[dict]) -> List[SimpleTrack]:
        now = time.time()

        for t in self.tracks.values():
            t.missed += 1

        stale_ids = [tid for tid, t in self.tracks.items() if t.missed > self.ttl_frames]
        for tid in stale_ids:
            del self.tracks[tid]

        assigned_track_ids = set()
        output_tracks = []

        for det in detections:
            cls = det.get("class")
            center = bbox_bottom_center(det)
            if center is None:
                continue

            best_track_id = None
            best_distance = None

            for track_id, track in self.tracks.items():
                if track_id in assigned_track_ids or track.cls != cls:
                    continue

                dist = euclidean(center, track.center)
                if best_distance is None or dist < best_distance:
                    best_distance = dist
                    best_track_id = track_id

            if best_track_id is not None and best_distance is not None and best_distance <= self.max_distance_px:
                track = self.tracks[best_track_id]
                # 💡 รักษาข้อมูลป้ายทะเบียนเดิมเอาไว้ ไม่ให้หายไปกับการอัปเดตพิกัดเฟรมใหม่
                old_plate = track.plate_text
                track.center = center
                track.bbox = det
                track.last_seen = now
                track.missed = 0
                track.age += 1
                if old_plate and old_plate != "-":
                    track.plate_text = old_plate
                assigned_track_ids.add(best_track_id)
                output_tracks.append(track)
            else:
                track = SimpleTrack(
                    track_id=self.next_id,
                    cls=cls,
                    center=center,
                    bbox=det,
                )
                self.tracks[self.next_id] = track
                assigned_track_ids.add(self.next_id)
                output_tracks.append(track)
                self.next_id += 1

        return output_tracks