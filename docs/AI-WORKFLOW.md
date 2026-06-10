# AI-WORKFLOW: MFU Vehicle Self-Tracking System

อัปเดตจาก source repo `vehicle-self-tracking-mobile-app` วันที่ 2026-06-10

เอกสารนี้เป็น workflow หลักสำหรับ AI/agents ทุกตัวใน repo นี้. `docs/agents/*` คือ role instructions ส่วน `AI-WORKFLOW.md` คือ sequence, gates, evidence, test, PRD และเอกสารส่งมอบที่ทุก role ต้องทำตาม.

## 1. Operating Principle

AI ห้ามคาดเดา. ทุก requirement, route, field, collection, screen behavior, test command และ release step ต้องมาจาก source ใน repo หรือถูกบันทึกเป็น `Open Question`, `Assumption`, หรือ `Blocker` พร้อม owner.

## 2. Mandatory Rules

1. ห้ามคาดเดา ต้องอ่านข้อมูลจาก repo ก่อนเสมอ และต้องระบุ source evidence ใน output.
2. เมื่อมีการพัฒนาหรือปรับปรุง ต้องทดสอบการทำงานก่อนสรุปว่างานเสร็จ.
3. เอกสารการปรับปรุง, change note, handoff หรือ doc ใหม่ต้องใช้รูปแบบ `T1-T20`.
4. เมื่อมีการเปลี่ยนแปลง behavior, requirement, API, UI, permission, data model หรือ release impact ต้องปรับปรุง PRD ที่เกี่ยวข้อง.
5. การพัฒนาต้องเขียนตามรูปแบบเดิมของ repo ก่อนเสมอ ทั้ง backend, AI worker และ Flutter app.
6. Flutter screens ต้องเขียนเป็น widget-based structure: screen ทำหน้าที่ orchestration, UI ย่อยแยกเป็น widgets/components.

## 3. Source Truth Order

ใช้ลำดับนี้เมื่อตรวจสอบความจริงของระบบ:

| Priority | Source | Purpose |
|---|---|---|
| 1 | Source code ที่ import/run จริง | behavior truth |
| 2 | Tests และ smoke scripts | expected behavior and regression coverage |
| 3 | `docs/prd/PRD-VehicleTracking.md` | product requirement truth |
| 4 | `docs/agents/*` | role operating instructions |
| 5 | `README.md`, `SETUP.md`, `docker-compose.yml` | environment and delivery notes |
| 6 | `Vehicle_tracking_simple.md` | design reference only — source code wins on conflict |

Route and schema truth:

- Backend route truth: `backend/api/api.py`
- Database schema truth: `backend/db/database.py`
- AI Worker pipeline truth: `ai_worker/detector.py`, `ai_worker/tracker.py`, `ai_worker/main.py`
- Flutter screen truth: `frontend/lib/screens/`
- Flutter navigation truth: `frontend/lib/main.dart` or dedicated router file
- Flutter state truth: `frontend/lib/providers/` or equivalent

## 4. Workflow And Agent Integration

```txt
Requirement
  -> T1-T4 Source Discovery
  -> Agent 00 Orchestrator
  -> Agent 01 Product Owner
  -> Agent 02 Data Model (MongoDB collections)
  -> Agent 03 Backend
  -> Agent 04 frontend
  -> Agent 05 AI Worker 
  -> T15 Implementation Summary
  -> T16 Tests / Verification
  -> Agent 06 Security (JWT, X-Secret, Cloudinary)
  -> Agent 07 QA/UAT
  -> Agent 08 Release/Ops (Docker, .env)
  -> T17 PRD / Docs Update
  -> T20 Final Handoff
```

Backend and Flutter may run in parallel only after:

- route/API contract is locked
- request/response shape is locked (`{ lat, lng }` not GeoJSON to Flutter)
- MongoDB collection/field decision is locked
- JWT and X-Secret auth scope is locked
- test data and role assumptions are documented

AI Worker changes must lock the internal API contract (`/internal/*` payload shape) before backend or Flutter changes proceed.

## 5. Required Source Discovery

Before implementation, the acting agent must read and record the relevant files.

Backend change minimum:

- `backend/api/api.py`
- `backend/db/database.py`
- relevant collection model/schema used by the changed route
- relevant tests and `backend/requirements.txt`

Flutter change minimum:

- `frontend/lib/main.dart` (or router file)
- target screen under `frontend/lib/screens/`
- relevant provider/service under `frontend/lib/providers/` or `frontend/lib/services/`
- `frontend/pubspec.yaml`
- relevant tests

AI Worker change minimum:

- `ai_worker/main.py`
- `ai_worker/detector.py`
- `ai_worker/tracker.py`
- `ai_worker/requirements.txt`
- `.env` (for `CAMERA_ID`, `INTERNAL_SECRET`, `VIDEO_SOURCE`)

Docs/process change minimum:

- `AGENTS.md`
- `docs/AI-WORKFLOW.md`
- `docs/agents/README.md`
- relevant role file under `docs/agents/`
- relevant PRD or template

## 6. Backend Development Pattern

Backend uses FastAPI + Python + Motor (async MongoDB driver).

Route and dependency pattern follows `backend/api/api.py`:

- declare `app = FastAPI()`
- connect `AsyncIOMotorClient` at module level
- initialise `firebase_admin` once at startup
- protect public routes with `Depends(get_user_id)` (JWT decode)
- protect internal routes with explicit `x_secret: str = Header(None)` check — raise `HTTPException(403)` on mismatch
- route order: auth → user settings → vehicle CRUD → tracking reads → alerts → cameras → internal
- keep route handlers thin: auth check → db operation → return shaped response
- convert GeoJSON `[lng, lat]` to `{ lat, lng }` before returning to any Flutter consumer

Permission mapping:

```txt
GET     -> read (requires Bearer JWT)
POST    -> write (requires Bearer JWT or X-Secret)
PATCH   -> update (requires Bearer JWT)
DELETE  -> delete (requires Bearer JWT, owner check)
/internal/* -> AI Worker only (X-Secret header, no JWT)
```

MongoDB operation pattern:

- use `ObjectId(str_id)` when querying by `_id` or cross-collection refs
- store locations as GeoJSON `{ type: "Point", coordinates: [lng, lat] }`
- `insert_one` for new documents; `update_one` with `$set` for patches; `find(...).to_list(length=N)` for lists
- do not store image data in MongoDB — only Cloudinary `secure_url` strings

## 7. Flutter Development Pattern

Flutter app uses Flutter + Provider + Dio + flutter_map.

Required pattern:

- navigation defined in `frontend/lib/main.dart` or a dedicated router file
- API calls go through a centralized Dio instance with `Authorization: Bearer $token` header
- state management via Provider (or equivalent) under `frontend/lib/providers/`
- JWT stored and read via `flutter_secure_storage`
- screens live under `frontend/lib/screens/`
- shared widgets live under `frontend/lib/widgets/`
- map screens use `flutter_map` with OpenStreetMap tile layer
- FCM token must be refreshed on every app open via `PATCH /users/me`

Current patterns to follow:

- map pin: `MarkerLayer` with `Icons.motorcycle` on `FlutterMap`
- route polyline: `PolylineLayer` with blue stroke on `FlutterMap`
- photo upload: `image_picker` → Cloudinary multipart upload → send URL to backend
- OAuth: `flutter_inappwebview` WebView for Lamduan code flow
- coordinate convention: backend always returns `{ lat, lng }` — never reverse to GeoJSON in Flutter

GeoJSON coordinate note: backend stores `[lng, lat]` internally but all Flutter-facing responses are `{ lat, lng }`. Any new endpoint that returns coordinates must follow this convention.

## 8. Testing Gate

No implementation is complete until tests or verification are run.

Minimum verification by scope:

Backend:

```bash
cd backend
pytest
```

AI Worker (offline — must use a recorded video, not live RTSP):

```bash
cd ai_worker
VIDEO_SOURCE=test_footage.mp4 python main.py
# Verify: tracking_logs and alert_history documents appear in MongoDB
# Verify: FCM notification fires on MOVED/LOST event
```

Flutter:

```bash
cd frontend
flutter pub get
flutter run
```

Docs-only change:

- verify file paths by reading current source
- grep/check references for stale paths
- no app test required unless behavior contract changes

If a test cannot run, final output must state:

- command not run
- exact reason
- risk left open
- owner/next action required

## 9. PRD Update Gate

Update `docs/prd/PRD-NewSystem.md` when any of these change:

- business requirement or acceptance criteria
- API endpoint, request body, response shape, or error behavior
- Flutter screen workflow or navigation graph
- MongoDB collection schema, index, or seed data
- AI Worker detection parameters, thresholds, or state machine logic
- Permission model (JWT claims, X-Secret rotation)
- Homography calibration points (`PIXEL_PTS` / `GPS_PTS` in `ai_worker/main.py`)
- Release behavior, env/config, operational process

Do not update PRD for purely internal refactors unless behavior or contract changes.

`Vehicle_tracking_simple.md` can be used as design background only. If it conflicts with current source, current source wins and PRD must be reconciled.

## 10. T1-T20 Change Document Format

Every change note, implementation handoff, or docs update must use these sections.

| T | Section | Required content |
|---|---|---|
| T1 | Change Title | concise name, module, date |
| T2 | Requirement | user request and business goal |
| T3 | Source Evidence | repo files/routes/collections/tests read before decision |
| T4 | Current Behavior | what source currently does |
| T5 | Impacted Agents | required agents and why |
| T6 | Scope | in scope, out of scope |
| T7 | Functional Requirements | FR IDs |
| T8 | Acceptance Criteria | AC IDs in Given/When/Then |
| T9 | API Contract | endpoints, request, response, errors |
| T10 | Data Model / Migration | MongoDB collection, field, index, seed change |
| T11 | Backend Plan / Changes | FastAPI routes, guards, db ops, tests |
| T12 | Flutter Plan / Changes | screens, navigation, providers, Dio calls, widgets |
| T13 | AI Worker Plan / Changes | detector, tracker, main loop, internal API calls |
| T14 | Security | JWT claims, X-Secret scope, Cloudinary policy, FCM token handling |
| T15 | Test Plan | test matrix and commands |
| T16 | Implementation Summary | files changed and behavior changed |
| T17 | Tests Run / Evidence | exact commands and result |
| T18 | PRD / Docs Updated | PRD/doc files changed or reason not needed |
| T19 | Risks / Blockers / Assumptions / Decisions | separated and owned |
| T20 | Release / Rollback | docker-compose, .env, smoke test, rollback steps |
| T20 | Final Handoff | status, next owner, open items |

Template file: `docs/templates/T1-T20-change-document.md`

## 11. Done Criteria

A task is done only when:

- source evidence is recorded
- implementation follows repo style (FastAPI pattern, Flutter widget pattern, AI Worker loop pattern)
- tests/verification are run and documented
- PRD/doc update decision is recorded
- Security/QA/Release gates are completed or explicitly marked not applicable
- T1-T20 final handoff is complete

## 12. Blocker Rules

Stop and ask for clarification when:

- required source file is missing or the project scaffold has not been created yet
- backend route and Flutter API call disagree and runtime compatibility cannot be proven
- internal API payload shape between AI Worker and backend is ambiguous
- MongoDB collection or field is unknown
- homography calibration points have not been measured on-site at E1
- `CAMERA_ID` in `.env` is missing or does not match a document in `cctv_cameras`
- tests cannot run and the change is high risk
- user request conflicts with security or release rules