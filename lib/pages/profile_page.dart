import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/delivery.dart';
import '../services/delivery_api.dart';
import 'login.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _api = DeliveryApi.instance;
  Driver? _driver;
  bool _loading = true;
  String? _error;
  final _df = DateFormat('y-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.fetchProfile();
      if (mounted) setState(() => _driver = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
      ),
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
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.person_outline, size: 28, color: Colors.indigo),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_driver!.name,
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(_driver!.email, style: const TextStyle(color: Colors.black54)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _driver!.isActive ? Colors.green.shade50 : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _driver!.isActive ? Colors.green.shade200 : Colors.red.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    _driver!.isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      color: _driver!.isActive ? Colors.green.shade800 : Colors.red.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Account', style: TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 10),
                                _Row('Driver ID', _driver!.id),
                                _Row('Email', _driver!.email),
                                _Row('Created', _driver!.createdAt != null ? _df.format(_driver!.createdAt!) : '-'),
                                _Row('Last login', _driver!.lastLogin != null ? _df.format(_driver!.lastLogin!) : '-'),
                                _Row('Token expires', _driver!.tokenExpires != null ? _df.format(_driver!.tokenExpires!) : '-'),
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
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.black54))),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
