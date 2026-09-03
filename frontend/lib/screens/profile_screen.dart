import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/firebase_messaging.dart' show unregisterFcmToken;
import '../services/api_client.dart';
import '../services/background_location_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = const FlutterSecureStorage();

  Map<String, dynamic>? _user;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _initUser();
    _loadUser();
  }

  Future<String?> _getToken() async {
    // ใช้ in-memory token ก่อน ถ้าไม่มีค่อยอ่านจาก secure storage
    if (UserSession.instance.token != null) return UserSession.instance.token;
    try {
      return await _storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  Future<void> _initUser() async {
    final session = UserSession.instance;
    if (session.user != null) {
      if (mounted) setState(() => _userName = session.user!['name'] as String?);
      return;
    }
    final token = session.token;
    if (token == null) return;
    try {
      final res = await ApiClient.instance.dio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      session.user = Map<String, dynamic>.from(res.data as Map);
      if (mounted) setState(() => _userName = session.user!['name'] as String?);
    } catch (_) {}
  }

  Future<void> _loadUser() async {
    // ถ้ามี user data ใน session แล้ว ใช้เลย ไม่ต้องเรียก API
    if (UserSession.instance.user != null) {
      setState(() {
        _user = UserSession.instance.user;
      });
      return;
    }
    try {
      final token = await _getToken();
      if (token == null) {
        return;
      }
      final res = await ApiClient.instance.dio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final user = Map<String, dynamic>.from(res.data);
      UserSession.instance.user = user;
      if (!mounted) return;
      setState(() {
        _user = user;
      });
    } catch (_) {}
  }

  Future<void> _showEditSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        initialName: _user?['name'] as String? ?? '',
        initialEmail: _user?['email'] as String? ?? '',
        onSave: _saveProfile,
      ),
    );
  }

  /// คืน null เมื่อบันทึกสำเร็จ, คืนข้อความ error ถ้าล้มเหลว (sheet เอาไปโชว์เป็น popup)
  Future<String?> _saveProfile(String name, String email) async {
    final token = await _getToken();
    if (token == null) return 'Not logged in.';
    try {
      final res = await ApiClient.instance.dio.patch(
        '/auth/profile',
        data: {'name': name, 'email': email},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final updated = Map<String, dynamic>.from(res.data);
      UserSession.instance.user = updated;
      if (mounted) {
        setState(() => _user = updated);
        _showSnack('Profile updated');
      }
      return null;
    } on DioException catch (e) {
      // 409 = อีเมลนี้ถูกใช้กับบัญชีอื่นแล้ว (backend เช็คใน update_profile)
      return e.response?.statusCode == 409
          ? 'This lamduan email address already exists and cannot be changed.'
          : e.response?.data?['detail']?.toString() ?? 'Update failed';
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final token = await _getToken();
    if (token != null) {
      await unregisterFcmToken(token);
    }
    // หยุด background location tracking ด้วย — ไม่งั้นเครื่องนี้จะยังส่ง GPS เข้าบัญชีเดิม
    // ต่อแม้ logout ไปแล้ว (background service ไม่รู้เรื่อง logout เอง ต้องสั่งหยุดตรงนี้)
    await BackgroundLocationService.instance.stop();

    try {
      await _storage.delete(key: 'jwt_token');
    } catch (_) {}
    UserSession.instance.token = null;
    UserSession.instance.user = null;
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : const Color(0xFF1E8A3E),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(children: [Expanded(child: _buildBody())]),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      centerTitle: false,

      leading: Padding(
        padding: const EdgeInsets.all(10),
        child: CircleAvatar(
          backgroundColor: AppColors.primaryContainer,
          child: Text(
            _userName != null && _userName!.isNotEmpty
                ? _userName![0].toUpperCase()
                : '?',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
            ),
          ),
        ),
      ),

      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'MFU TRACKER',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),

          if (_userName != null)
            Text(
              _userName!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.onPrimary,
              ),
            ),
        ],
      ),

      actions: [
        IconButton(
          onPressed: _showEditSheet,
          icon: const Icon(Icons.edit_outlined, color: AppColors.onPrimary),
          tooltip: 'Edit Profile',
        ),

        const NotificationBell(
          color: AppColors.onPrimary,
          padding: EdgeInsets.only(right: 8),
        ),
      ],
    );
  }

  Widget _buildBody() {
    final displayName = _user?['name'] as String? ?? 'MFU Student';
    final email = _user?['email'] as String? ?? '';
    // Student ID = ส่วนหน้า @ ของ lamduan mail (เช่น 6631501042@lamduan.mfu.ac.th)
    final studentId = email.contains('@') ? email.split('@').first : '—';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        _buildProfileHeader(displayName, email),
        const SizedBox(height: 24),
        _buildAccountSection(displayName, studentId, email),
        const SizedBox(height: 24),
        _buildLogoutButton(),
      ],
    );
  }

  Widget _buildProfileHeader(String name, String email) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            color: AppColors.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(name),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '• MFU •',
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection(String name, String studentId, String email) {
    return _Card(
      title: 'Account Information',
      icon: Icons.person_outline,
      children: [
        _InfoTile(icon: Icons.person, label: 'Full Name', value: name),
        const _Divider(),
        _InfoTile(
          icon: Icons.badge_outlined,
          label: 'Student ID',
          value: studentId,
          onCopy: studentId != '—' ? () => _copyToClipboard(studentId) : null,
        ),
        const _Divider(),
        _InfoTile(
          icon: Icons.mail_outlined,
          label: 'University Email',
          value: email,
          onCopy: email.isNotEmpty ? () => _copyToClipboard(email) : null,
        ),
      ],
    );
  }

  Widget _buildLogoutButton() {
    return OutlinedButton.icon(
      onPressed: _logout,
      icon: const Icon(Icons.logout, size: 18),
      label: const Text('Log Out'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        side: const BorderSide(color: AppColors.error),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
    _showSnack('Copied to clipboard');
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Card({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(
                Icons.copy_outlined,
                size: 16,
                color: AppColors.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Copy',
            ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      color: AppColors.outlineVariant,
      indent: 30,
    );
  }
}

// ── Edit Profile Bottom Sheet ─────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final String initialName;
  final String initialEmail;
  final Future<String?> Function(String name, String email) onSave;

  const _EditProfileSheet({
    required this.initialName,
    required this.initialEmail,
    required this.onSave,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // ปิด sheet ต่อเมื่อบันทึกสำเร็จจริงเท่านั้น — ถ้าอีเมลซ้ำ (409) ให้ค้าง sheet ไว้
      // แล้วเด้ง popup แจ้งแทน snackbar (เห็นชัดกว่า ต้องกด OK ถึงจะปิด บังคับให้รับรู้)
      final error = await widget.onSave(
        _nameCtrl.text.trim(),
        _emailCtrl.text.trim(),
      );
      if (!mounted) return;
      if (error == null) {
        Navigator.of(context).pop();
      } else {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Could not save'),
            content: Text(error),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                _buildField(
                  controller: _nameCtrl,
                  label: 'Full Name',
                  icon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 14),
                _buildField(
                  controller: _emailCtrl,
                  label: 'University Email',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimary,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onPrimary,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.primaryContainer,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }
}
