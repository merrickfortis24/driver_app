import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/delivery_api.dart';

class CashPage extends StatefulWidget {
  const CashPage({super.key});

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  final _api = DeliveryApi.instance;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  Uint8List? _photo;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await _api.fetchCashSummary();
      setState(() => _data = d);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (img != null) {
      setState(() async {
        _photo = await img.readAsBytes();
      });
    }
  }

  Future<void> _submit() async {
    final v = double.tryParse(_amountCtrl.text.trim());
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final res = await _api.submitRemittance(
        amount: v,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        proofJpeg: _photo,
      );
      setState(() { _data = res; _amountCtrl.clear(); _noteCtrl.clear(); _photo = null; });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remittance submitted')),
      );
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _submitting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Cash & Remittance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        color: cs.surface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(child: _metric('Today Collected', _data?['today']?['collected'] ?? 0)),
                              const SizedBox(width: 12),
                              Expanded(child: _metric('Today Remitted', _data?['today']?['remitted'] ?? 0)),
                              const SizedBox(width: 12),
                              Expanded(child: _metric('Cash in Hand', _data?['today']?['cashInHand'] ?? 0, highlight: true)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Submit Remittance', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _amountCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Amount (PHP)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickPhoto,
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Add Proof Photo (optional)'),
                          ),
                          const SizedBox(width: 12),
                          if (_photo != null)
                            const Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send),
                          label: const Text('Submit'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Recent Remittances', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ...((_data?['remittances'] as List<dynamic>? ?? [])).map((r) {
                        return ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text('₱${(r['amount'] ?? 0).toString()}'),
                          subtitle: Text((r['createdAt'] ?? '').toString()),
                          trailing: (r['proof'] != null && (r['proof'] as String).isNotEmpty)
                              ? const Icon(Icons.image, color: Colors.blue)
                              : null,
                        );
                      }),
                    ],
                  ),
                ),
    );
  }

  Widget _metric(String label, dynamic value, {bool highlight = false}) {
    final v = (value is num) ? value.toStringAsFixed(2) : value.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          '₱$v',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: highlight ? Colors.green : null,
          ),
        ),
      ],
    );
  }
}
