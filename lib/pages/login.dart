import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_connection/api_connection.dart';

import 'main_shell.dart';
import '../services/animation_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

// Verification modal widget
class VerificationDialog extends StatefulWidget {
  final int? driverId;
  final bool autoSend;
  const VerificationDialog({super.key, this.driverId, this.autoSend = false});

  @override
  State<VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<VerificationDialog> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  int _cooldown = 0; // seconds remaining for resend

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // If caller requested automatic send, trigger it after the first frame
    if (widget.autoSend) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ignore: use_build_context_synchronously
        _resend();
      });
    }
  }

  Future<int?> _getDriverIdFromProfile() async {
    // If caller provided driverId, use it
    if (widget.driverId != null) return widget.driverId;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return null;
    final resp = await http
        .get(
          Uri.parse(API.profile),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    final data = json.decode(resp.body);
    if (data is Map) {
      // Try to sync server verification state to local prefs if available
      try {
        final prefs = await SharedPreferences.getInstance();
        final serverVerified =
            data['is_verified'] ??
            data['verified'] ??
            data['isVerified'] ??
            (data['driver'] is Map ? data['driver']['is_verified'] : null);
        final idFromMap =
            data['id'] ??
            data['driver_id'] ??
            data['Driver_ID'] ??
            (data['driver'] is Map ? data['driver']['id'] : null);
        if (idFromMap != null && serverVerified != null) {
          final idInt = idFromMap is int
              ? idFromMap
              : int.tryParse(idFromMap.toString());
          if (idInt != null) {
            final key = 'is_verified_$idInt';
            final bool verifiedBool = (serverVerified is bool)
                ? serverVerified
                : (serverVerified.toString() == '1' ||
                      serverVerified.toString().toLowerCase() == 'true');
            if (verifiedBool) {
              await prefs.setBool(key, true);
            } else {
              await prefs.remove(key);
            }
          }
        }
      } catch (_) {}

      return data['id'] ??
          data['driver_id'] ??
          data['Driver_ID'] ??
          (data['driver'] is Map ? data['driver']['id'] : null);
    }
    return null;
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return; // guard
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await _getDriverIdFromProfile();
      if (id == null) throw Exception('Driver id not found');
      final sendUrl = Uri.parse(
        '${API.hostConnectDriver}/send_verification_code.php',
      );
      final resp = await http
          .post(
            sendUrl,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'driver_id': id}),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Failed to resend');
      }
      // start cooldown on successful send
      _startCooldown();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCooldown([int seconds = 60]) {
    if (!mounted) return;
    setState(() => _cooldown = seconds);
    // Use a periodic Timer rather than Ticker to avoid extra imports
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldown = (_cooldown > 0) ? _cooldown - 1 : 0);
      return _cooldown > 0;
    });
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await _getDriverIdFromProfile();
      if (id == null) throw Exception('Driver id not found');
      final verifyUrl = Uri.parse('${API.hostConnectDriver}/verify_code.php');
      final resp = await http
          .post(
            verifyUrl,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode({'driver_id': id, 'code': code}),
          )
          .timeout(const Duration(seconds: 10));
      final data = json.decode(resp.body);
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          data is Map &&
          data['success'] == true) {
        if (!mounted) return;
        // Persist that this device is verified for this driver until server clears it
        final prefs = await SharedPreferences.getInstance();
        final id = await _getDriverIdFromProfile();
        if (id != null) {
          await prefs.setBool('is_verified_$id', true);
        }
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        setState(
          () => _error = data is Map && data['message'] != null
              ? data['message'].toString()
              : 'Invalid code',
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter verification code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('A 6-digit code was sent to your email. Enter it below.'),
          const SizedBox(height: 8),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(counterText: ''),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_cooldown > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Resend available in $_cooldown s',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            // visual progress for cooldown (maps 60 -> 0)
            SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: (_cooldown / 60),
                backgroundColor: Colors.black12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: (_loading || _cooldown > 0) ? null : _resend,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : (_cooldown > 0
                    ? Text('Resend ($_cooldown)')
                    : const Text('Resend')),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _verify,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>(); // + add a form key
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  int? _driverId;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return; // + validate before request
    setState(() {
      _loading = true;
      _error = null;
    });

    final url = Uri.parse(API.login);
    try {
      final response = await http
          .post(
            url,
            // keep x-www-form-urlencoded (no custom Content-Type header needed)
            headers: {'Accept': 'application/json'},
            body: {
              'email': _emailController.text.trim().toLowerCase(),
              'password': _passController.text,
            },
          )
          .timeout(const Duration(seconds: 20));

      // Debug output to VS Code Debug Console
      // ignore: avoid_print
      print('Login status: ${response.statusCode} body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(response.body);
        final token = (data is Map)
            ? (data['token'] ?? data['Api_Token'])
            : null;
        if (token != null && token is String && token.isNotEmpty) {
          // try to extract driver id from the login response if present
          int? tryId() {
            if (data is Map) {
              var v = data['id'] ?? data['driver_id'] ?? data['Driver_ID'];
              if (v == null && data['user'] is Map) v = data['user']['id'];
              if (v is int) return v;
              if (v is String) return int.tryParse(v);
            }
            return null;
          }

          _driverId = tryId();
          // We avoid capturing BuildContext across async gaps; dialog is shown later.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
          // Play motorcycle animation on successful login
          MotorcycleAnimationService.instance.show();
          // If this device is already locally verified for this driver, skip dialog.
          var skipVerification = false;
          if (_driverId != null) {
            final key = 'is_verified_$_driverId';
            skipVerification = prefs.getBool(key) ?? false;
          }

          if (skipVerification) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainShell()),
            );
          } else {
            // Prompt for verification code — dialog will handle sending/resend
            if (!mounted) return;
            final verified = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) =>
                  VerificationDialog(driverId: _driverId, autoSend: true),
            );

            if (verified == true) {
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const MainShell()),
              );
            } else {
              setState(() => _error = 'Verification required');
            }
          }
        } else {
          setState(
            () => _error =
                (data is Map ? (data['error'] ?? data['message']) : null)
                    ?.toString() ??
                'Invalid credentials',
          );
        }
      } else {
        setState(
          () => _error = 'Server ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      setState(() => _error = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Call backend to send verification code to the logged in driver.
  // Note: verification dialog handles sending/resend directly.

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Keep login background light for readability even in dark mode.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF12100E) : cs.surface;
    final cardBg = const Color(0xFFF6F1EC);
    final accent = const Color(0xFF7A5A34); // brown/gold

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                SizedBox(
                  width: 110,
                  height: 110,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/logo.jpg', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        // use Color.fromRGBO instead of withOpacity for compatibility
                        color: const Color.fromRGBO(0, 0, 0, 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        'Rider Portal',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter your email';
                          }
                          final ok = RegExp(
                            r'^[^@]+@[^@]+\.[^@]+$',
                          ).hasMatch(v.trim());
                          return ok ? null : 'Enter a valid email';
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        obscureText: _obscure,
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'Enter your password'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            // avoid using .withOpacity (deprecated); use Color.fromRGBO
                            disabledBackgroundColor: const Color.fromRGBO(
                              122,
                              90,
                              52,
                              0.6,
                            ),
                            disabledForegroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
