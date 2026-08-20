import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../theme/app_theme.dart';

class ForgotScreen extends StatefulWidget {
  const ForgotScreen({super.key});

  @override
  State<ForgotScreen> createState() => _ForgotScreenState();
}

class _ForgotScreenState extends State<ForgotScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // -------- OTP Controllers and Focus Nodes --------
  final List<TextEditingController> _otpController = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNode = List.generate(6, (_) => FocusNode());

  bool _isValidMfuEmail(String email) {
    return email.trim().toLowerCase().endsWith("@lamduan.mfu.ac.th");
  }

  bool _verified = false; // ตรวจสอบ Username+Email
  bool _otpVerified = false; // ตรวจสอบ OTP
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _verifyingAccount = false;
  bool _verifyingOtp = false;
  bool _changingPassword = false;
  String? _resetToken;

  final Dio dio = Dio(
    BaseOptions(
      baseUrl: "https://primp-squeeze-dedicator.ngrok-free.dev",
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
    ),
  );

  void _resetVerificationState() {
    if (!_verified && !_otpVerified && _resetToken == null) return;

    setState(() {
      _verified = false;
      _otpVerified = false;
      _resetToken = null;
      for (final controller in _otpController) {
        controller.clear();
      }
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    });
  }

  String _errorMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data["detail"] != null) {
      return data["detail"].toString();
    }
    return fallback;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();

    for (final controller in _otpController) {
      controller.dispose();
    }

    for (final node in _otpFocusNode) {
      node.dispose();
    }

    super.dispose();
  }

  Future<void> _verifyAccount() async {
    if (_verifyingAccount) return;

    final username = _usernameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();

    if (username.isEmpty || email.isEmpty) {
      _showMessage("Please enter username and email");
      return;
    }

    if (!_isValidMfuEmail(email)) {
      _showMessage("Only @lamduan.mfu.ac.th email is allowed");
      return;
    }

    setState(() => _verifyingAccount = true);
    try {
      final response = await dio.post(
        "/auth/forgot-password/verify",
        data: {"username": username, "email": email},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _verified = true;
          _otpVerified = false;
          _resetToken = null;
          _newPasswordController.clear();
          _confirmPasswordController.clear();
        });

        for (final controller in _otpController) {
          controller.clear();
        }

        FocusScope.of(context).requestFocus(_otpFocusNode[0]);
        _showMessage(
          response.data?["message"]?.toString() ?? "OTP sent to Lamduan Mail",
          backgroundColor: AppColors.green,
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _verified = false;
        _otpVerified = false;
        _resetToken = null;
      });

      _showMessage(_errorMessage(e, "Verification failed"));
    } finally {
      if (mounted) setState(() => _verifyingAccount = false);
    }
  }

  Future<void> _confirmOtp() async {
    if (_verifyingOtp) return;

    final otp = _otpController.map((e) => e.text).join();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();

    if (!_verified) {
      _showMessage("Please verify your account first");
      return;
    }

    if (otp.length != 6) {
      _showMessage("Please enter the complete OTP");
      return;
    }

    setState(() => _verifyingOtp = true);
    try {
      final response = await dio.post(
        "/auth/forgot-password/verify-otp",
        data: {"username": username, "email": email, "otp": otp},
      );

      if (!mounted) return;

      final resetToken = response.data?["reset_token"]?.toString();
      if (response.statusCode == 200 &&
          resetToken != null &&
          resetToken.isNotEmpty) {
        setState(() {
          _otpVerified = true;
          _resetToken = resetToken;
        });

        _showMessage(
          "OTP verified successfully",
          backgroundColor: AppColors.green,
        );
      } else {
        _showMessage("OTP verified but reset token was not returned");
      }
    } on DioException catch (e) {
      if (!mounted) return;
      _showMessage(_errorMessage(e, "Invalid OTP"));
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  Future<void> _changePassword() async {
    final email = _emailController.text.trim().toLowerCase();
    final resetToken = _resetToken;

    if (!_isValidMfuEmail(email)) {
      _showMessage("Only @lamduan.mfu.ac.th email is allowed");
      return;
    }

    if (!_otpVerified || resetToken == null || resetToken.isEmpty) {
      _showMessage("Please verify OTP before changing password");
      return;
    }

    if (_newPasswordController.text.length < 4) {
      _showMessage("Password must be at least 4 characters");
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showMessage("Passwords do not match");
      return;
    }

    if (_changingPassword) return;
    setState(() => _changingPassword = true);

    try {
      await dio.post(
        "/auth/forgot-password/reset",
        data: {
          "username": _usernameController.text.trim(),
          "email": email,
          "password": _newPasswordController.text,
          "reset_token": resetToken,
        },
      );

      if (!mounted) return;
      _showMessage(
        "Password changed successfully",
        backgroundColor: AppColors.green,
      );
      Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      _showMessage(_errorMessage(e, "Unable to change password"));
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  void _showMessage(String msg, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: backgroundColor ?? AppColors.error,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
      filled: true,
      fillColor: AppColors.background,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: AppColors.primaryContainer,
          width: 2,
        ),
      ),
    );
  }

  Widget _buttonChild(bool loading, String label) {
    if (loading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.onPrimary,
        ),
      );
    }

    return Text(
      label,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.05 * 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.chevron_left),
                  color: AppColors.onSurface,
                  tooltip: 'Back',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryContainer,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_reset,
                    size: 48,
                    color: AppColors.primaryContainer,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              Text(
                'Reset Your Password ',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 0.5,
                ),
              ),

              const SizedBox(height: 30),

              Container(
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'ACCOUNT VERIFICATION',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.05 * 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 25),

                    TextField(
                      controller: _usernameController,
                      decoration: _inputDecoration("Username"),
                      onChanged: (_) => _resetVerificationState(),
                    ),

                    const SizedBox(height: 16),

                    TextField(
                      controller: _emailController,
                      decoration: _inputDecoration("Email@lamduan.mfu.ac.th"),
                      onChanged: (_) => _resetVerificationState(),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _verifyingAccount ? null : _verifyAccount,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _buttonChild(
                          _verifyingAccount,
                          "Verify account & send OTP",
                        ),
                      ),
                    ),

                    // ------- OTP -------
                    if (_verified) ...[
                      const SizedBox(height: 30),

                      const Divider(),

                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'VERIFY YOUR EMAIL',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.05 * 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      Text(
                        'Please enter the 6-digit OTP',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.05 * 12,
                          color: AppColors.blue,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ---------- OTP input fields ----------
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          6,
                          (index) => SizedBox(
                            width: 40,
                            height: 56,
                            child: TextField(
                              controller: _otpController[index],
                              focusNode: _otpFocusNode[index],

                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              textAlign: TextAlign.center,
                              maxLength: 1,

                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryContainer,
                              ),

                              cursorColor: AppColors.primaryContainer,

                              decoration: InputDecoration(
                                counterText: "",
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: EdgeInsets.zero,

                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: AppColors.primaryContainer
                                        .withValues(alpha: .35),
                                  ),
                                ),

                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: AppColors.primaryContainer,
                                    width: 2,
                                  ),
                                ),
                              ),

                              onChanged: (value) {
                                if (value.isNotEmpty && index < 5) {
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(_otpFocusNode[index + 1]);
                                }

                                if (value.isEmpty && index > 0) {
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(_otpFocusNode[index - 1]);
                                }
                              },
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: _verifyingOtp ? null : _confirmOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryContainer,
                            foregroundColor: AppColors.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _buttonChild(_verifyingOtp, "Confirm OTP"),
                        ),
                      ),
                    ],

                    // ------- create new password -------
                    if (_verified && _otpVerified) ...[
                      const SizedBox(height: 30),

                      const Divider(),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'CREATE NEW PASSWORD',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.05 * 12,
                              color: AppColors.green,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _newPasswordController,
                        obscureText: _obscure1,
                        decoration: _inputDecoration(
                          "New Password",
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure1
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscure1 = !_obscure1;
                              });
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscure2,
                        decoration: _inputDecoration(
                          "Confirm Password",
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure2
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscure2 = !_obscure2;
                              });
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton(
                          onPressed: _changingPassword ? null : _changePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryContainer,
                            foregroundColor: AppColors.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _buttonChild(
                            _changingPassword,
                            "Change Password",
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
