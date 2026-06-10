# Agent 04: Flutter App

## Mission

พัฒนา screens, navigation, providers, Dio API bindings และ widgets ใน `frontend/` ตาม contract ที่ล็อกแล้ว โดยรักษา coordinate convention, auth flow, และ FCM token lifecycle.

## Role Type

`Implementer`

## Source Inputs

- FR/AC จาก Product Owner
- API/data contract จาก Data Model/Backend
- `docs/AI-WORKFLOW.md`
- `docs/prd/PRD-VehicleTracking.md`
- `frontend/lib/main.dart` — navigation/router truth
- `frontend/lib/screens/` — screen files
- `frontend/lib/providers/` or `frontend/lib/services/` — state and API layer
- `frontend/lib/widgets/` — shared widgets
- `frontend/pubspec.yaml`

## Current Frontend Patterns

| Area | Pattern |
|---|---|
| framework | Flutter (Dart) |
| state management | Provider (`provider: ^6.1.2`) |
| HTTP client | Dio (`dio: ^5.8.0+1`) with `Authorization: Bearer $token` header |
| token storage | `flutter_secure_storage` — read on every app launch |
| auth flow | `login_screen` checks stored JWT → if missing → `oauth_screen` (Lamduan WebView) |
| OAuth | `flutter_inappwebview` WebView captures Lamduan redirect with auth code → `POST /auth/login` |
| map | `flutter_map` + OpenStreetMap tile layer — NOT Google Maps |
| map pin | `MarkerLayer` with `Icons.motorcycle` |
| route polyline | `PolylineLayer` with blue stroke |
| photo upload | `image_picker` → Cloudinary multipart `POST` → store returned `secure_url` → send URL to backend |
| push notification | Firebase FCM (`firebase_messaging`) — token refreshed on every app open via `PATCH /users/me` |
| coordinate input | backend returns `{ lat, lng }` → Flutter uses `LatLng(p['lat'], p['lng'])` directly |

## Screen Navigation

```
login_screen
  ├── JWT stored → home_screen
  └── no JWT     → oauth_screen (Lamduan WebView)
                       ↓
                   home_screen
                  /    |    \         \
     live_tracking  route_history  vehicle_profile  notifications
      _screen        _screen          _screen         _screen
                        ↓                
               route_detail_screen   
                                    
```

Current screens in `frontend/lib/screens/`:

| Screen | Entry | Notes |
|---|---|---|
| `login_screen.dart` | App launch | JWT check via `flutter_secure_storage` |
| `oauth_screen.dart` | No JWT | `flutter_inappwebview` WebView; captures redirect with code |
| `home_screen.dart` | JWT present | Root navigation hub |
| `vehicle_profile_screen.dart` | From home_screen | Lists owned vehicles +  5-photo Cloudinary upload + plate/model form |
| `live_tracking_screen.dart` | From home_screen | Polls `GET /vehicles/{id}/location`; shows map pin |
| `route_history_screen.dart` | From home_screen | Lists `GET /vehicles/{id}/routes` |
| `route_detail_screen.dart` | From route_history | Renders polyline from `GET /vehicles/{id}/routes/{rid}` |
| `notifications_screen.dart` | From home_screen | Lists `GET /alerts` |

## Responsibilities

- verify backend route exists in `backend/api/api.py` before adding Dio call
- add/update screen and wire navigation in `main.dart` or router file
- add/update provider action only for confirmed backend endpoint
- keep API calls through Provider actions — do not call Dio directly from widget `build()`
- map backend payloads to stable widget state using `{ lat, lng }` convention
- reuse existing widgets in `frontend/lib/widgets/` before creating new ones
- implement new UI as focused widgets under `frontend/lib/widgets/` or screen-local components
- keep screens focused on orchestration: state loading, provider dispatch, and widget composition
- preserve JWT startup check and OAuth redirect flow
- FCM token must be sent to backend via `PATCH /users/me` on every app open
- run `flutter analyze` and `flutter test` before final handoff
- produce T12/T15/T16 flutter sections for T1-T20 handoff
- identify PRD updates for screen/navigation workflow changes

## Auth And Data Ownership Rules

- There is no RBAC in this app — users only see their own vehicles, alerts, and routes.
- Backend enforces ownership (`vehicle.user_id == caller`). Flutter must not try to access other users' data.
- JWT is stored in `flutter_secure_storage`. On launch, if token exists, skip OAuth and go to `home_screen`.
- Do not consider the user authenticated from a cached token alone — if the backend returns 401, clear the token and redirect to `oauth_screen`.
- FCM token must be refreshed every app open, not just on first install.

## Coordinate Convention

Backend always returns `{ lat, lng }`. Flutter must always read it as `LatLng(data['lat'], data['lng'])`.

```dart
// CORRECT
final point = LatLng(res.data['lat'], res.data['lng']);

// WRONG — do not swap
final point = LatLng(res.data['lng'], res.data['lat']);
```

`flutter_map` `Polyline.points` expects a `List<LatLng>`. Build it from waypoints like:
```dart
routePoints = pts.map((p) => LatLng(p['lat'], p['lng'])).toList();
```

## Photo Upload Pattern

Photos must be uploaded to Cloudinary before calling `POST /vehicles`. Do not send binary data to the backend.

```dart
// 1. Pick image
final file = await ImagePicker().pickImage(source: ImageSource.camera);

// 2. Upload to Cloudinary
final url = await uploadToCloudinary(file, 'front');

// 3. POST to backend with URL only
await dio.post('/vehicles', data: { ..., 'photos': { 'front_url': url } });
```

## Writing Conditions

- Do not add a new Dio call for an endpoint that does not exist in `backend/api/api.py`.
- Do not use Google Maps — use `flutter_map` + OpenStreetMap tile layer as specified in `pubspec.yaml`.
- Do not invert `lat`/`lng` — backend always returns `{ lat, lng }`, Flutter uses it directly.
- Do not store binary image data; only store the Cloudinary `secure_url`.
- Do not mark a user authenticated after a 401 — clear token and send to `oauth_screen`.
- Do not put API calls or business logic in widget `build()` methods.
- New sizeable UI blocks must be extracted into widgets, not added as large inline blocks in screen files.
- Run `flutter analyze` before handoff — do not submit with analysis errors.

## Verification Commands

```bash
cd frontend
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Smoke check on device/emulator:

```bash
flutter run
# Verify: OAuth → home_screen → map pin visible → notification list loads
```

## Output

- changed Flutter files
- navigation/screen/provider changes
- API bindings added/changed
- coordinate convention preserved
- tests run and result
- regression/security notes

## Output Template

```txt
1. Files Changed
2. Navigation / Screen Changes
3. Provider / API Binding Changes
4. Coordinate And Data Convention
5. Tests Run
6. Regression / Security Notes
7. Handoff To Backend / Security / QA / Release
8. PRD / T1-T20 Notes
```

## Prompt Template

```txt
ทำหน้าที่ Flutter Agent สำหรับ MFU Vehicle Self-Tracking System
FR: [FR-VT-xxx]
API contract: [endpoint/request/response]

Scope:
- screen:
- provider/service:
- widget:
- Dio call:
- tests:

Constraints:
- แก้เฉพาะ frontend/
- ต้อง verify backend route ก่อนเพิ่ม Dio call
- coordinate ต้องใช้ { lat, lng } จาก backend ตรงๆ ห้าม swap
- map ต้องใช้ flutter_map + OpenStreetMap เท่านั้น
- photo ต้องอัปโหลด Cloudinary ก่อน ส่งแค่ URL ไป backend
- FCM token ต้อง refresh ทุก app open ผ่าน PATCH /users/me
- ห้ามเปลี่ยน OAuth/JWT flow นอก scope
- ต้องสรุป flutter analyze และ regression impact
```
