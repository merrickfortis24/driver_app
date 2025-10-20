import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/delivery.dart';
import '../services/delivery_api.dart';
import 'login.dart';
import '../widgets/header_icon.dart';
import '../services/theme_controller.dart';
// Inline editing implemented; no separate edit page import needed

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

// header icon moved to shared widget HeaderIcon

class _ProfilePageState extends State<ProfilePage> {
  final _api = DeliveryApi.instance;
  Driver? _driver;
  bool _loading = true;
  String? _error;
  final _df = DateFormat('y-MM-dd HH:mm');
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.fetchProfile();
      if (mounted) {
        setState(() {
          _driver = d;
          // populate controllers for inline edit
          _nameController.text = d.name;
          _emailController.text = d.email;
          _phoneController.text = d.phone ?? '';
          _addressController.text = d.address ?? '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    Color headerBg() => brightness == Brightness.dark
        ? const Color(0xFF2B2724)
        : const Color(0xFFFAF6F0);

    final header = PreferredSize(
      preferredSize: const Size.fromHeight(86),
      child: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: headerBg(),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  HeaderIcon(title: 'My Profile', icon: Icons.person_outline),
                  const Spacer(),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeController.instance.mode,
                    builder: (context, mode, _) {
                      final isDark = mode == ThemeMode.dark;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            ThemeController.instance.set(
                              isDark ? ThemeMode.light : ThemeMode.dark,
                            );
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFE6DA),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Icon(
                                isDark
                                    ? Icons.dark_mode
                                    : Icons.nightlight_round,
                                color: const Color(0xFF6B4F32),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
      ),
    );

    return Scaffold(
      appBar: header,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            )
          : _driver == null
          ? const Center(child: Text('No profile loaded'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Profile card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Initials avatar
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: const Color(0xFF7A5A34),
                            child: Text(
                              _initials(_driver!.name),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Name (editable)
                                _editing
                                    ? TextFormField(
                                        controller: _nameController,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            vertical: 6,
                                            horizontal: 8,
                                          ),
                                          border: InputBorder.none,
                                        ),
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return 'Please enter your name';
                                          }
                                          return null;
                                        },
                                      )
                                    : Text(
                                        _driver!.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                const SizedBox(height: 6),
                                Text(
                                  'Delivery Rider',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _driver!.createdAt != null
                                          ? _df.format(_driver!.createdAt!)
                                          : '-',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Edit / Save / Cancel actions (constrained to avoid overflow)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Material(
                              color: Colors.transparent,
                              child: _editing
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            backgroundColor: const Color(
                                              0xFFF4E9DF,
                                            ),
                                            foregroundColor: const Color(
                                              0xFF7A5A34,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            elevation: 0,
                                          ),
                                          onPressed: _saving
                                              ? null
                                              : () async {
                                                  // save
                                                  if (!_formKey.currentState!
                                                      .validate()) {
                                                    return;
                                                  }
                                                  final messenger =
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      );
                                                  setState(() {
                                                    _saving = true;
                                                  });
                                                  try {
                                                    await _api.updateProfile(
                                                      name: _nameController.text
                                                          .trim(),
                                                      email: _emailController
                                                          .text
                                                          .trim(),
                                                      phone: _phoneController
                                                          .text
                                                          .trim(),
                                                      address:
                                                          _addressController
                                                              .text
                                                              .trim(),
                                                    );
                                                    if (!mounted) return;
                                                    messenger.showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Profile updated',
                                                        ),
                                                      ),
                                                    );
                                                    setState(() {
                                                      _editing = false;
                                                    });
                                                    await _load();
                                                  } catch (e) {
                                                    if (mounted) {
                                                      messenger.showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            e.toString(),
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } finally {
                                                    if (mounted) {
                                                      setState(() {
                                                        _saving = false;
                                                      });
                                                    }
                                                  }
                                                },
                                          child: _saving
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation(
                                                          Colors.white,
                                                        ),
                                                  ),
                                                )
                                              : const Row(
                                                  children: [
                                                    Icon(Icons.save, size: 16),
                                                    SizedBox(width: 8),
                                                    Text('Save'),
                                                  ],
                                                ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFFBFA78D),
                                            ),
                                            foregroundColor: const Color(
                                              0xFF7A5A34,
                                            ),
                                          ),
                                          onPressed: _saving
                                              ? null
                                              : () {
                                                  // cancel edits, restore values
                                                  setState(() {
                                                    _editing = false;
                                                    _nameController.text =
                                                        _driver!.name;
                                                    _emailController.text =
                                                        _driver!.email;
                                                    _phoneController.text =
                                                        _driver!.phone ?? '';
                                                    _addressController.text =
                                                        _driver!.address ?? '';
                                                  });
                                                },
                                          child: const Text('Cancel'),
                                        ),
                                      ],
                                    )
                                  : InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () =>
                                          setState(() => _editing = true),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF4E9DF),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.edit,
                                              size: 16,
                                              color: Color(0xFF7A5A34),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Edit Profile',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Color(0xFF7A5A34),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Personal Information card (view or edit)
                Form(
                  key: _formKey,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Personal Information',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _editing
                            ? Column(
                                children: [
                                  _formFieldRow(
                                    Icons.person_outline,
                                    'Full Name',
                                    _nameController,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Enter name';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  _formFieldRow(
                                    Icons.email_outlined,
                                    'Email',
                                    _emailController,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Enter email';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  _formFieldRow(
                                    Icons.phone_outlined,
                                    'Phone Number',
                                    _phoneController,
                                  ),
                                  const SizedBox(height: 8),
                                  _formFieldRow(
                                    Icons.location_on_outlined,
                                    'Address',
                                    _addressController,
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.badge_outlined,
                                    'Driver ID',
                                    _driver!.id,
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.lock_clock,
                                    'Token Expires',
                                    _driver!.tokenExpires != null
                                        ? _df.format(_driver!.tokenExpires!)
                                        : '-',
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _infoRow(
                                    Icons.person_outline,
                                    'Full Name',
                                    _driver!.name,
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.email_outlined,
                                    'Email',
                                    _driver!.email,
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.phone_outlined,
                                    'Phone Number',
                                    _driver!.phone ?? '-',
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.location_on_outlined,
                                    'Address',
                                    _driver!.address ?? '-',
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.badge_outlined,
                                    'Driver ID',
                                    _driver!.id,
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.lock_clock,
                                    'Token Expires',
                                    _driver!.tokenExpires != null
                                        ? _df.format(_driver!.tokenExpires!)
                                        : '-',
                                  ),
                                ],
                              ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF7A5A34)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(value),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formFieldRow(
    IconData icon,
    String label,
    TextEditingController controller, {
    String? Function(String?)? validator,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF7A5A34)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: controller,
                validator: validator,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// _Row was removed in favor of the new _infoRow helper above.
