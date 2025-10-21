import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/delivery_api.dart';
import '../models/delivery.dart';

class ProofCapturePage extends StatefulWidget {
  final DeliveryOrder order;
  const ProofCapturePage({super.key, required this.order});

  @override
  State<ProofCapturePage> createState() => _ProofCapturePageState();
}

class _ProofCapturePageState extends State<ProofCapturePage> {
  final _picker = ImagePicker();
  final _api = DeliveryApi.instance;
  final List<Uint8List> _photoBytes = [];
  final List<String> _photoNames = [];
  bool _uploading = false;
  String? _error;
  final _amountCtrl = TextEditingController();
  bool _showAmountField = true;

  @override
  void initState() {
    super.initState();
    // Only prompt for amount for COD/unpaid-like statuses; prefill with total
    final ps = widget.order.paymentStatus.toLowerCase();
    final pm = (widget.order.paymentMethod ?? '').toLowerCase();
    // Treat online payment methods (gcash, paypal, card, online) as not requiring cash collection
    final isOnline =
        pm.contains('gcash') ||
        pm.contains('online') ||
        pm.contains('card') ||
        pm.contains('paypal');
    final isCodOrUnpaid =
        ps.contains('cod') ||
        ps.contains('cash') ||
        ps.contains('unpaid') ||
        ps.contains('pending');
    _showAmountField = isCodOrUnpaid && !isOnline;
    if (_showAmountField) {
      _amountCtrl.text = widget.order.totalAmount.toStringAsFixed(2);
    }
  }

  Future<void> _addPhoto(ImageSource src) async {
    try {
      final picked = await _picker.pickImage(source: src, imageQuality: 85);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _photoBytes.add(bytes);
          _photoNames.add(picked.name);
        });
      }
    } catch (e) {
      setState(() => _error = 'Failed to pick image');
    }
  }

  Future<void> _submit() async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      // Photos
      final photoBytes = List<Uint8List>.from(_photoBytes);
      final names = List<String>.from(_photoNames);
      // Require at least one photo as proof
      if (photoBytes.isEmpty) {
        throw Exception('Please add at least one photo as proof of delivery.');
      }
      await _api.uploadProofPhotos(
        widget.order.id,
        photoBytes,
        fileNames: names,
      );
      if (!mounted) return;
      double? amount;
      if (_showAmountField) {
        amount = double.tryParse(_amountCtrl.text.trim());
        amount ??= widget.order.totalAmount; // fallback to total
      }
      Navigator.of(context).pop(amount ?? 0);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proof of Delivery')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Text(
              'Photos (at least 1, up to 5)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_showAmountField) ...[
              TextField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Amount Collected (PHP)',
                  helperText: 'Prefilled with order total',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photoBytes.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _photoBytes[i],
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: InkWell(
                          onTap: () => setState(() {
                            _photoBytes.removeAt(i);
                            _photoNames.removeAt(i);
                          }),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_photoBytes.length < 5)
                  OutlinedButton.icon(
                    onPressed: _uploading
                        ? null
                        : () => _addPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                if (_photoBytes.length < 5)
                  OutlinedButton.icon(
                    onPressed: _uploading
                        ? null
                        : () => _addPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _uploading ? null : _submit,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: const Text('Upload & Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
