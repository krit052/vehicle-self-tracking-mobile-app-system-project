# MFU Vehicle Self-Tracking System

ระบบติดตามยานพาหนะภายในมหาวิทยาลัยแม่ฟ้าหลวง (MFU) ที่ใช้กล้อง CCTV ร่วมกับ AI อ่านป้ายทะเบียนรถ (License Plate Recognition) เพื่อตรวจจับการเข้า-ออกของยานพาหนะแบบเรียลไทม์ พร้อมแจ้งเตือนผ่านมือถือ และแสดงตำแหน่งจุดที่ตรวจพบล่าสุดบนแผนที่ในแอป

## ภาพรวมระบบ

โปรเจกต์แบ่งออกเป็น 3 ส่วนหลัก ทำงานร่วมกันผ่าน MongoDB Atlas:

| ส่วน | โฟลเดอร์ | เทคโนโลยี | หน้าที่ |
|---|---|---|---|
| **Backend API** | `backend/api/` | FastAPI, MongoDB (Motor/PyMongo), JWT, Firebase Admin | ยืนยันตัวตนผู้ใช้ (MFU OAuth), จัดการข้อมูลรถ/กล้อง, รับผลตรวจจับจาก AI worker, ส่ง push notification |
| **AI Worker** | `backend/ai_worker/` | PaddleOCR, YOLO, OpenCV | ดึงภาพจากกล้อง RTSP/CCTV, ตรวจจับและอ่านป้ายทะเบียน แล้วส่งผลไปที่ Backend |
| **Mobile App** | `frontend/` | Flutter | แอปสำหรับผู้ใช้ ดูตำแหน่งรถ, ประวัติการตรวจจับ, รับการแจ้งเตือน |

ข้อมูลกล้อง (CCTV catalog) เก็บเป็นไฟล์ CSV ใน `backend/cctv/` และซิงก์เข้า MongoDB เฉพาะกล้องที่ถูก "pin" ไว้ใช้งานจริง (ดูรายละเอียดการซิงก์ใน `backend/cctv/seed_camera.py`)

## โครงสร้างโปรเจกต์

```
vehicle-self-tracking-mobile-app/
├── backend/
│   ├── api/            # FastAPI app หลัก (main.py)
│   ├── ai_worker/       # ตัวตรวจจับป้ายทะเบียนจากกล้อง
│   ├── cctv/            # แคตตาล็อกกล้อง (CSV) + สคริปต์ seed
│   ├── db/              # การเชื่อมต่อฐานข้อมูล
│   ├── db_config/       # ไฟล์ credential (ไม่ commit ขึ้น git)
│   ├── test_backend/    # backend เวอร์ชันทดสอบ
│   └── Dockerfile
├── frontend/            # Flutter mobile app
├── docs/                # เอกสารประกอบ, PRD, agent workflow
├── docker-compose.yml
├── render.yaml          # ตั้งค่า deploy backend บน Render
└── SETUP.md             # คู่มือติดตั้งแบบละเอียด (ภาษาไทย)
```

## เริ่มต้นใช้งานอย่างเร็ว

ดูขั้นตอนติดตั้งแบบละเอียด (โปรแกรมที่ต้องลง, ตัวแปร `.env`, GPU/Docker) ได้ที่ **[SETUP.md](SETUP.md)** สรุปสั้น ๆ ดังนี้:

```bash
# 1. Clone โปรเจกต์
git clone https://github.com/6631501045-TBuaekem/vehicle-self-tracking-mobile-app.git
cd vehicle-self-tracking-mobile-app

# 2. ตั้งค่าไฟล์ .env ที่ root (ดูตัวอย่างค่าที่ต้องใส่ใน SETUP.md)

# 3. รัน Backend API
cd backend/api
pip install -r ../requirements.txt
uvicorn main:app --reload --port 8000
# เปิด http://localhost:8000/docs เพื่อดู Swagger

# 4. รัน AI Worker (terminal แยก)
cd backend/ai_worker
pip install -r requirements.txt
python main.py

# 5. รัน Flutter App (terminal แยก)
cd frontend
flutter pub get
flutter run
```

หรือรันทั้งหมดผ่าน Docker: `docker compose up --build` (ดูรายละเอียดใน SETUP.md ส่วน B)

## Deploy

Backend ตั้งค่าให้ deploy ผ่าน [Render](https://render.com) โดยใช้ `render.yaml` (Docker runtime, health check ที่ `/health`) — ตัวแปรแวดล้อมที่ต้องตั้งใน Render dashboard: `MONGODB_URL`, `MONGO_NAME`, `JWT_SECRET`, `INTERNAL_SECRET`, `CLOUDINARY_URL`, `FIREBASE_SERVICE_ACCOUNT`, `BREVO_API_KEY`, `EMAIL_FROM`, `ADMIN_ALLOWED_CIDRS`

## เอกสารเพิ่มเติม

- [SETUP.md](SETUP.md) — คู่มือติดตั้งแบบละเอียด
- [Vehicle_tracking_simple.md](Vehicle_tracking_simple.md) — สรุป flow การทำงานของระบบ
- [docs/](docs/) — PRD และเอกสาร workflow อื่น ๆ

## หมายเหตุ

โปรเจกต์แบ่งความรับผิดชอบเป็นสองฝั่ง: ทีมนี้ดูแล mobile app + backend (`frontend/`, `backend/api/`, `backend/db/`) ส่วน logic การตรวจจับป้ายทะเบียนด้วย AI (`backend/ai_worker/`) ดูแลโดยอีกทีม
