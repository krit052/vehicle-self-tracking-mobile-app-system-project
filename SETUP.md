# คู่มือติดตั้งโปรเจกต์ — MFU Vehicle Tracking System

> คู่มือนี้ก่อนเริ่มใช้งาน 

---

## โปรแกรมที่ต้องติดตั้งก่อน

| โปรแกรม | ดาวน์โหลด | หมายเหตุ |
|---|---|---|
| Python 3.12.10 | python.org | ติ๊ก "Add to PATH" ตอนติดตั้ง |
| Flutter 3.x | flutter.dev | ทำตาม Windows install guide |
| MongoDB 7.0.34  | mongodb.com/try/download/community |
| Docker Desktop | docker.com/products/docker-desktop | สำหรับรันแบบ Docker เท่านั้น |
|CUDA version|
| Git | git-scm.com | สำหรับ clone โปรเจกต์ |
| MongoDB Atlas | สำหรับเก็บ table ต่างๆ รูปภาพเก็บเป็น url ของ cloudianry  
| Cloudianary | เก็บรุปภาพต่างๆ snap shot
| Firebase FCM| ส่งแจ้งเตือนไปยังมือถือ

วิธีลบ python ver เก่า: cmd: where path ลบ file ตามที่มันขึ้น, edit environment variable > user path ลบ path ที่เป็น python ออกให้หมด

ติดตั้ง python 3.12.10 =>> winget install -e --id Python.Python.3.12 
ติดตั้ง MongoDB 7.0.34 ==>> https://www.mongodb.com/try/download/community
สร้างโปรเจคใน Mongo Atlas แล้วชวนทีมเข้ามา //

ใน Mongo Compass กด + แล้วใส่ mongodb+srv://6631501045_db_user:5IJeciYTtb2GwtwL@vehicle-self-tracking.axgoaf1.mongodb.net/

สร้างโปรเจคใน firebase console แล้วชวนทีมเข้ามา //
สร้างโปรเจคใน cloudinary แล้วชวนทีมเข้ามา //

ติดตั้ง Paddle Paddle =>> python3 -m pip install paddlepaddle-gpu==3.3.0 -i https://www.paddlepaddle.org.cn/packages/stable/cu126/

> AMD / ไม่มี GPU: python3 -m pip install paddlepaddle==3.3.0 -i https://www.paddlepaddle.org.cn/packages/stable/cpu/
เปิด `ai_worker/detector.py` แล้วเปลี่ยน `use_gpu=True` → `use_gpu=False`

ทดสอบว่า paddle ใช้ได้ไหม รัน verify_paddle.py

ติดตั้ง Docker =>> https://docs.docker.com/desktop/setup/install/windows-install/

เช็คว่าติดตั้งครบหรือยัง:
```bash
python --version
flutter --version
docker --version
git --version
```


---

## 1. ดาวน์โหลดโปรเจกต์

```bash
git clone <your-repo-url>
cd vehicle-tracking-system
```

---

## 2. ตั้งค่า .env

เปิดไฟล์ `.env` ที่ root ของโปรเจกต์ แล้วใส่ค่าของคุณ:

```env
MONGO_USER=66xxxxxx_db_user   # user ตัวเองใน Database Users ของตัวเอง ใน atlas
MONGO_PASSWORD=dawdawdawdawdad  # รหัสเอามาจาก Database users ของตัวเอง ใน atlas ถ้าไม่รู้ให้เจนรหัสใหม่
MONGO_NAME=vehicle-self-tracking
MONGODB_URL=mongodb+srv://66xxxxxx_db_user:dawdawdawdawdad@vehicle-self-tracking.axgoaf1.mongodb.net/

# App secrets
JWT_SECRET=any-random-string-here
INTERNAL_SECRET=another-random-string-here

# MFU OAuth
LAMDUAN_CLIENT_ID=your-mfu-oauth-client-id
LAMDUAN_CLIENT_SECRET=your-mfu-oauth-client-secret

# Camera
CAMERA_RTSP_URL=rtsp://username:password@camera-ip/stream
CAMERA_ID=paste-the-objectid-from-seed_camera.py-here
BACKEND_URL=http://localhost:8000
# VIDEO_SOURCE=footage.mp4   ← ใส่ตอน develop เพื่อใช้ไฟล์แทน RTSP, ลบออกตอน deploy จริง

# Cloudinary (รูปภาพ)
CLOUDINARY_URL=cloudinary://596868621737339:<xLufQYj-Go_Krta_I6Ady_WVpTU>@dbhgmwsfg
```

> `CAMERA_ID` — ไว้ก่อน จะได้ค่านี้ตอน seed camera

---

## 3. ใส่ไฟล์ YOLO Model

วางไฟล์ model ที่เทรนแล้วไว้ใน `ai_worker/`:

```
ai_worker/
└── yolov11s_mfu.pt   ← วางไว้ตรงนี้
```


---






## A — Manual (ตอนพัฒนา) ยังไม่ต้องยุ่งไฟล์ docker ที่ step B

### A1. Start MongoDB

```bash
# MongoDB รันเป็น Windows service หลังจากติดตั้งแล้ว
เชื่อม mongodb+srv://6631501045_db_user:5IJeciYTtb2GwtwL@vehicle-self-tracking.axgoaf1.mongodb.net/
```

### A2. Backend

```bash
cd backend
pip install -r requirements.txt
# python seed_camera.py
```

Copy ค่า `CAMERA_ID` ใส่ `.env` แล้วรัน:

```bash
uvicorn main:app --reload --port 8000
```

เปิด `http://localhost:8000/docs` เพื่อเช็ค

แล้วติดตั้งส่วนที่เหลือและรัน:
```bash
cd backend/ai_worker
pip install -r requirements.txt
# python main.py
```

### A3. Flutter App

```bash
cd frontend
flutter pub get
flutter run
```

---

## การใช้งานประจำวัน (Manual)

เปิด 3 terminal:

| Terminal | คำสั่ง |
|---|---|
| 1 — MongoDB | `net start MongoDB` (รันเป็น service อยู่แล้ว) |
| 2 — Backend | `python seed_camera.py uvicorn main:app --reload --port 8000` |
| 3 — AI Worker | `python main.py` |

> `seed_camera.py` รันก่อนเริ่มใช้งาน

Flutter: `cd frontend && flutter run` (terminal แยกหรือรันจาก IDE)

---






******************************************************************************************************************************









## B — Docker [ยังไม่ต้องทำ](ตอนพัฒนาเสร็จหมดแล้วและส่งต่อโปรเจกต์ให้คนอื่น)

> Docker ใช้ CUDA 11.8 ภายใน container เสมอ ไม่ว่า driver ของเครื่องจะเป็น version อะไรก็ตาม
> เพราะฉะนั้นไม่ต้องกังวลเรื่อง CUDA version ของ host เลย

### B1. เปิดใช้งาน WSL2 (Windows, ทำครั้งเดียว)

เปิด PowerShell แบบ Administrator:
```powershell
wsl --install
wsl --set-default-version 2
```
Restart เครื่องหลังจากนี้

---

### B2. ติดตั้ง GPU Support (ทำครั้งเดียว)

#### การ์ด NVIDIA (GTX / RTX)

เปิด **WSL2 terminal** (ค้นหา "Ubuntu" ใน Start menu):
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

ทดสอบว่า GPU ทำงานได้ใน Docker:
```bash
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```
จะต้องเห็นชื่อการ์ดจอของคุณแสดงขึ้นมา

---

#### การ์ด AMD หรือไม่มี GPU

ข้ามขั้นตอน toolkit ด้านบนทั้งหมด แล้วทำสองอย่างนี้แทน:

**1. ลบ GPU block ออกจาก `docker-compose.yml`** — ลบบรรทัดเหล่านี้ใต้ `ai_worker`:
```yaml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

**2. ใน `ai_worker/detector.py`** เปลี่ยน:
```python
ocr = PaddleOCR(lang="th", use_gpu=True, show_log=False)
```
เป็น:
```python
ocr = PaddleOCR(lang="th", use_gpu=False, show_log=False)
```

รันได้ปกติบน CPU — ช้ากว่าแต่เพียงพอสำหรับ parking lot demo

---

### B3. Build และ Start

```bash
# รันจาก root ของโปรเจกต์
docker compose up --build
```

> ครั้งแรกใช้เวลา 10–20 นาที (ดาวน์โหลด CUDA image ~5GB) หลังจากนั้นจะเร็วขึ้น

จะเห็น container รันอยู่ 3 ตัว:
- `mfu_mongodb` — ฐานข้อมูล
- `mfu_backend` — FastAPI พอร์ต 8000
- `mfu_ai_worker` — AI detection

### B4. Seed Camera (รันครั้งเดียวเท่านั้น)

เปิด terminal อีกอันขณะที่ container กำลังรัน:
```bash
docker exec mfu_backend python seed_camera.py
```

Copy ค่า `CAMERA_ID` ที่ได้ แล้ว paste ใส่ `.env`:
```env
CAMERA_ID=paste-the-value-here
```

แล้ว restart AI worker:
```bash
docker compose restart ai_worker
```

### B5. เช็คว่า Backend รันได้

เปิด browser: `http://localhost:8000/docs`

จะต้องเห็นหน้า Swagger API

---

## การใช้งานประจำวัน (Docker)

```bash
# Start ทุกอย่าง
docker compose up

# Stop ทุกอย่าง
docker compose down

# ดู log
docker compose logs -f backend
docker compose logs -f ai_worker

# Rebuild หลังจากแก้โค้ด
docker compose up --build backend
docker compose up --build ai_worker
```

---

## Port ของแต่ละ Service

| Service | Address |
|---|---|
| Backend API | `http://localhost:8000` |
| Swagger Docs | `http://localhost:8000/docs` |
| MongoDB | `localhost:27017` |

---

## แก้ปัญหาที่พบบ่อย

**`nvidia-smi` ใช้ไม่ได้**
→ ยังไม่ได้ติดตั้ง NVIDIA driver รับ driver จาก nvidia.com แล้วติดตั้ง

**`nvidia-smi` หาไม่เจอใน Docker**
→ ยังไม่ได้ติดตั้ง NVIDIA Container Toolkit ทำ Step A2 ใหม่

**ติดตั้ง `paddlepaddle-gpu` ไม่ได้**
→ ใช้ post120 เสมอถ้า CUDA version 12.x ขึ้นไป ดูตารางใน Step B3

**Error ว่า `CAMERA_ID` ไม่มีตอน start**
→ รัน `seed_camera.py` ก่อน แล้ว copy ID ใส่ `.env`

**Backend ต่อ MongoDB ไม่ได้**
→ Docker: `MONGODB_URL` ต้องเป็น `mongodb://mongodb:27017/mfu-vehicle-tracking` (ใช้ชื่อ service ไม่ใช่ `localhost`)
→ Manual: เช็คว่า MongoDB service รันอยู่ (`net start MongoDB`)

**Flutter build error**
→ รัน `flutter clean && flutter pub get` แล้วลองใหม่
