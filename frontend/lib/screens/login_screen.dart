import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _Logo(),
                    const SizedBox(height: 32),
                    _TitleSection(),
                    const SizedBox(height: 40),
                    _LoginCard(),
                    const Spacer(flex: 3),
                    _Footer(),
                    if (kDebugMode) const _DebugFcmToken(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryContainer, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.network(
          'https://www.mfu.ac.th/media/images/mfu-logo.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.school,
            size: 48,
            color: AppColors.primaryContainer,
          ),
        ),
      ),
    );
  }
}

class _TitleSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Vehicle Self-Tracking System',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.01 * 24,
            color: AppColors.onSurface,
            height: 32 / 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Secure, real-time access to campus transportation data for MFU Students',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.onSurfaceVariant,
            height: 20 / 14,
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'OAUTH AUTHENTICATION',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.05 * 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _onLoginPressed(context),
              icon: const Icon(Icons.mail_outline, size: 20),
              label: const Text('Login via Lamduan Mail'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.05 * 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Divider(color: AppColors.outlineVariant),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'MFU @lamduan.mfu.ac.th',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(
                child: Divider(color: AppColors.outlineVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onLoginPressed(BuildContext context) {
    // TODO: replace with real OAuth flow against Lamduan Mail
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Redirecting to Lamduan Mail login...'),
        backgroundColor: AppColors.primaryContainer,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    Navigator.pushReplacementNamed(context, '/home');
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            _FooterLink(label: 'Terms of Service', onTap: () {}),
            Text('·', style: _dotStyle),
            _FooterLink(label: 'Privacy Policy', onTap: () {}),
            Text('·', style: _dotStyle),
            _FooterLink(label: 'IT Helpdesk', onTap: () {}),
            Text('·', style: _dotStyle),
            _FooterLink(label: 'Transportation Office', onTap: () {}),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '© Mae Fah Luang University',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  TextStyle get _dotStyle => GoogleFonts.inter(
        fontSize: 12,
        color: AppColors.onSurfaceVariant,
      );
}

class _DebugFcmToken extends StatefulWidget {
  const _DebugFcmToken();

  @override
  State<_DebugFcmToken> createState() => _DebugFcmTokenState();
}

class _DebugFcmTokenState extends State<_DebugFcmToken> {
  String? _token;

  @override
  void initState() {
    super.initState();
    FirebaseMessaging.instance.getToken().then((t) => setState(() => _token = t));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_token == null) return;
        Clipboard.setData(ClipboardData(text: _token!));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('FCM token copied')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        child: Text(
          '[DEBUG] FCM: ${_token ?? 'loading...'}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.primary,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.primary,
        ),
      ),
    );
  }
}
