/// ค่าคงที่ระดับแอปทั้งหมด — ตอนนี้มีแค่ backendUrl แต่เป็นจุดเดียวที่ควรเพิ่มค่ากลางอื่นๆ ในอนาคต
///
/// เดิม backend URL (ngrok tunnel) ถูก hardcode ซ้ำอยู่ใน const แยกกันคนละตัวใน 14 ไฟล์ทั่วแอป
/// (ทุกหน้าจอประกาศ `static const _baseUrl = '...'` ของตัวเอง) พอ URL เปลี่ยนต้องไล่แก้ทุกที่
/// และเสี่ยงแก้ไม่ครบ — ตอนนี้แก้ที่เดียวพอ
///
/// ใช้ String.fromEnvironment เพื่อให้เปลี่ยนได้ตอน build โดยไม่ต้องแก้โค้ดเลยด้วย เช่น:
///   flutter run --dart-define=BACKEND_URL=https://your-tunnel.example.com
class AppConfig {
  AppConfig._();

  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://primp-squeeze-dedicator.ngrok-free.dev',
  );
}
