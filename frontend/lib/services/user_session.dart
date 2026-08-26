/// Singleton เก็บ token/role/user ของผู้ใช้ที่ login อยู่ตลอด session (ในหน่วยความจำ)
///
/// เดิมคลาสนี้อยู่ใน login_screen.dart แล้วหน้าจออื่นๆ ต้อง
/// `import 'login_screen.dart' show UserSession;` เพื่อจะใช้ — coupling ข้ามไปยังไฟล์หน้าจอ
/// ที่ไม่เกี่ยวข้องกันโดยตรง ย้ายมาไว้ในเลเยอร์ service ที่ควรอยู่แทน
class UserSession {
  UserSession._();
  static final UserSession instance = UserSession._();

  String? token;
  String? role;
  Map<String, dynamic>? user;

  bool get isLoggedIn => token != null;

  /// ล้าง session ทั้งหมด (เรียกตอน logout หรือตอน token หมดอายุ/ถูกเพิกถอน)
  void clear() {
    token = null;
    role = null;
    user = null;
  }
}
