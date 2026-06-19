from backend.ai_worker.main import init_firebase, send_fcm_alert

print("Initializing firebase");
init_firebase()
print("Firebase OK")

send_fcm_alert({
    "status": "TEST",
    "distance_m": 9.99,
    "person_track_id": 1,
    "motorcycle_track_id": 2,
    "license_plate_text": "TEST-PLATE",
})