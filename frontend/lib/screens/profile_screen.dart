import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme/app_theme.dart';
import 'notifications_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
  final _storage = const FlutterSecureStorage();

  Map<String, dynamic>? _user;
  bool _loading = true;

  // Threshold edit state
  final _thresholdCtrl = TextEditingController();
  bool _thresholdDirty = false;
  bool _savingThreshold = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _thresholdCtrl.addListener(() => setState(() => _thresholdDirty = true));
  }

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<String?> get _token => _storage.read(key: 'jwt_token');

  Future<void> _loadUser() async {
    try {
      final token = await _token;
      final res = await _dio.get(
        '/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      setState(() {
        _user = Map<String, dynamic>.from(res.data);
        _thresholdCtrl.text = (res.data['detection_threshold_min'] ?? 2).toString();
        _thresholdDirty = false;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveThreshold() async {
    final val = int.tryParse(_thresholdCtrl.text);
    if (val == null || val < 1) {
      _showSnack('Minimum is 1 minute', isError: true);
      return;
    }
    setState(() => _savingThreshold = true);
    try {
      final token = await _token;
      await _dio.patch(
        '/users/me',
        data: {'detection_threshold_min': val},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      setState(() {
        _savingThreshold = false;
        _thresholdDirty = false;
        _user?['detection_threshold_min'] = val;
      });
      _showSnack('Threshold updated');
    } catch (_) {
      setState(() => _savingThreshold = false);
      _showSnack('Failed to update', isError: true);
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

    await _storage.delete(key: 'jwt_token');
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : const Color(0xFF1E8A3E),
    ));
  }

  // Extract student ID from MFU email (e.g. 6531234@lamduan.mfu.ac.th → 6531234)
  String _studentId(String email) {
    final local = email.split('@').first;
    return RegExp(r'^\d+$').hasMatch(local) ? local : '—';
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      title: const Text(
        'MFU TRACKER',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.5),
      ),
      centerTitle: false,
      leading: const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.account_circle, color: AppColors.onPrimary),
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
          icon: const Icon(Icons.notifications_outlined, color: AppColors.onPrimary),
          padding: const EdgeInsets.only(right: 8),
        ),
      ],
    );
  }

  Widget _buildBody() {
    final displayName = _user?['display_name'] as String? ?? 'MFU Student';
    final email       = _user?['email'] as String? ?? '';
    final studentId   = _studentId(email);

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
          'Computer Engineering • MFU',
          style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
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

  const _Card({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
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
                  style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant, letterSpacing: 0.4),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onSurface),
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined, size: 16, color: AppColors.onSurfaceVariant),
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
    return const Divider(height: 1, color: AppColors.outlineVariant, indent: 30);
  }
}
