import 'dart:typed_data';
import 'dart:io';
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
  final List<XFile> _photos = [];
  bool _uploading = false;
  String? _error;

  Future<void> _addPhoto(ImageSource src) async {
    try {
      final picked = await _picker.pickImage(source: src, imageQuality: 85);
      if (picked != null) {
        setState(() => _photos.add(picked));
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
      List<Uint8List> photoBytes = [];
      List<String> names = [];
      for (final xf in _photos) {
        final bytes = await xf.readAsBytes();
        photoBytes.add(bytes);
        names.add(xf.name);
      }
      if (photoBytes.isNotEmpty) {
        await _api.uploadProofPhotos(
          widget.order.id,
          photoBytes,
          fileNames: names,
        );
      }
      // Require at least one photo as proof
      if (photoBytes.isEmpty) {
        throw Exception('Please add at least one photo as proof of delivery.');
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
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
              'Photos (optional, up to 5)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _photos)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(p.path),
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: InkWell(
                          onTap: () => setState(() => _photos.remove(p)),
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
                if (_photos.length < 5)
                  OutlinedButton.icon(
                    onPressed: _uploading
                        ? null
                        : () => _addPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                if (_photos.length < 5)
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
