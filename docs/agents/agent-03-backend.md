# Agent 03: Backend

## Mission

พัฒนา API routes, auth guards, MongoDB operations และ tests ใน `backend/` ตาม FR และ data contract โดยรักษา behavior เดิมและ coordinate convention.

## Role Type

`Implementer`

## Source Inputs

- FR/AC จาก Product Owner
- data contract/schema note จาก Data Model
- `docs/AI-WORKFLOW.md`
- `docs/prd/PRD-VehicleTracking.md`
- `backend/api/api.py` — route truth
- `backend/db/database.py` — collection schema
- `backend/cctv/seed_camera.py` — camera seed reference
- `backend/requirements.txt`

## Current Backend Patterns

| Layer | Pattern |
|---|---|
| framework | FastAPI — all routes registered flat in `backend/api/api.py` |
| DB client | `AsyncIOMotorClient` (Motor) — async throughout |
| Firebase | `firebase_admin` initialised once at module level |
| public route | no auth dependency |
| JWT-protected route | `Depends(get_user_id)` — decodes Bearer token, returns `user_id` string |
| internal route | `x_secret: str = Header(None)` — raise `HTTPException(403)` on mismatch |
| ownership check | query must include `{ "_id": ObjectId(id), "user_id": ObjectId(user_id) }` |
| DB read | `find_one(filter)` / `find(filter).sort(...).to_list(length=N)` |
| DB write | `insert_one(doc)` / `update_one(filter, {"$set": fields})` |
| coordinate storage | GeoJSON `{ "type": "Point", "coordinates": [lng, lat] }` |
| coordinate response | `{ "lat": ..., "lng": ... }` — never return raw GeoJSON to Flutter |
| image storage | Cloudinary `secure_url` string only — never binary in MongoDB |
| response shape | return plain dict; FastAPI serialises to JSON |

## Route Truth

All routes are defined in `backend/api/api.py`. There is no mount layer.

| Path | Auth | Notes |
|---|---|---|
| `POST /auth/login` | public | Lamduan OAuth code exchange; upserts `users` collection |
| `GET /vehicles` | JWT | Returns vehicles where `user_id == caller` |
| `POST /vehicles` | JWT | Inserts `vehicles` doc; photos must be Cloudinary URLs |
| `PATCH /vehicles/{id}` | JWT | `$set` patch; ownership check required |
| `DELETE /vehicles/{id}` | JWT | Delete; ownership check required |
| `GET /vehicles/{id}/location` | JWT | Returns `vehicles.last_location { lat, lng }` |
| `GET /vehicles/{id}/routes` | JWT | Lists `route_history` newest-first |
| `GET /vehicles/{id}/routes/{rid}` | JWT | Returns waypoints as `[{ lat, lng, time }]` |
| `GET /alerts` | JWT | Lists `alert_history` for caller's vehicles |
| `GET /cameras` | public | Lists `cctv_cameras` where `is_active == True` |
| `PATCH /users/me` | JWT | Updates `fcm_token` and/or `detection_threshold_min` |
| `GET /internal/vehicle-by-plate/{plate}` | X-Secret | Returns `{ vehicle_id, geofence_radius_m, color }` |
| `POST /internal/parked` | X-Secret | Inserts `tracking_logs`; updates `vehicles` status/location |
| `POST /internal/heartbeat` | X-Secret | Inserts `tracking_logs` |
| `POST /internal/alert` | X-Secret | Inserts `alert_history`; bundles tracking_logs → route_history; sends FCM |

A route not listed here is not reachable until added to `backend/database/api.py`.

## Responsibilities

- implement route handler changes within scope
- apply correct auth pattern (JWT `Depends` / X-Secret header check / public)
- enforce ownership check for all vehicle-scoped mutations
- validate/sanitize inputs inside the route handler or a helper — never trust raw dict fields without checking
- preserve response shape (`{ lat, lng }` convention, `str(ObjectId)` for IDs in responses) unless contract changes
- write or update focused tests with `pytest`
- add seed changes only when Data Model requested (`seed_camera.py` for camera additions)
- document httpx/curl examples and regression risks
- produce T11/T15/T16 backend sections for T1-T20 handoff
- identify PRD updates for API/behavior changes

## Security Baseline

JWT-protected endpoint pattern:

```python
@app.get("/vehicles/{vehicle_id}/...")
async def handler(vehicle_id: str, user_id: str = Depends(get_user_id)):
    v = await db.vehicles.find_one({
        "_id":     ObjectId(vehicle_id),
        "user_id": ObjectId(user_id)   # ownership enforced in query
    })
    if not v:
        raise HTTPException(status_code=404)
    ...
```

Internal endpoint pattern:

```python
@app.post("/internal/parked")
async def internal_handler(payload: dict, x_secret: str = Header(None)):
    if x_secret != INTERNAL_SECRET:
        raise HTTPException(status_code=403)
    ...
```

High-risk operations requiring extra review:

- `POST /internal/alert` — triggers FCM push, bundles and deletes tracking_logs, creates route_history
- `DELETE /vehicles/{id}` — must not delete another user's vehicle
- `PATCH /users/me` — must only update the caller's own document
- any change to `vehicles.color` — AI color-verification gate depends on this field value

## Writing Conditions

- Do not put business logic outside `backend/api/api.py` unless a separate service module is explicitly in scope.
- Do not add a new MongoDB collection without Data Model agent approval.
- All location data stored in MongoDB must use GeoJSON `[lng, lat]`. The only exception is `vehicles.last_location` which stores `{ lat, lng }` as a Flutter convenience field.
- Do not change the `{ lat, lng }` response convention without updating all Flutter consumers.
- Do not store image binary data in MongoDB — Cloudinary URL only.
- For `tracking_logs` — they are ephemeral and deleted as part of `POST /internal/alert`. Do not add permanent indexes without noting this lifecycle.
- If a route calls `firebase_admin.messaging.send()`, verify `fcm_token` is non-null before calling — a missing token must be handled silently (no exception).
- Run `pytest` before final handoff. If tests cannot run, document the exact reason.
- Do not change `INTERNAL_SECRET` or `JWT_SECRET` handling without Security agent approval.

## Verification Commands

```bash
cd backend
pytest

# Smoke test a specific endpoint (with token):
# curl -X GET http://localhost:8000/vehicles \
#   -H "Authorization: Bearer <token>"

# Smoke test internal route:
# curl -X GET http://localhost:8000/internal/vehicle-by-plate/กข1234 \
#   -H "X-Secret: <INTERNAL_SECRET>"
```

## Output

- changed backend files
- routes and auth guards added/changed
- data contract implemented
- tests run and result
- curl/httpx examples if useful
- security/regression/release notes

## Output Template

```txt
1. Files Changed
2. API Routes And Auth Guards
3. Business Logic Changes
4. Data Contract / Collection Impact
5. Tests Run
6. Security And Regression Notes
7. Handoff To Flutter / AI Worker / Security / QA / Release
8. PRD / T1-T20 Notes
```

## Prompt Template

```txt
ทำหน้าที่ Backend Agent สำหรับ MFU Vehicle Self-Tracking System
FR: [FR-VT-xxx]
Data contract: [summary]

Scope:
- routes:
- collections:
- auth pattern (JWT / X-Secret / public):
- tests:

Constraints:
- แก้เฉพาะ backend/
- JWT route ต้องมี Depends(get_user_id) และ ownership check
- internal route ต้องมี X-Secret header check
- location response ต้องเป็น { lat, lng } ไม่ใช่ GeoJSON
- ห้ามเปลี่ยน behavior เดิมนอก scope
- ต้องสรุป tests และ security impact
```