import 'package:flutter/material.dart';
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
  // Remittance submission removed per new spec: only metrics + recent remittances

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
      final d = await _api.fetchCashSummary();
      setState(() => _data = d);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  // Submit/pick photo removed

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
  appBar: AppBar(title: const Text('Cash')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: cs.surface,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _metric(
                              'Today Collected',
                              _data?['today']?['collected'] ?? 0,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _metric(
                              'Today Remitted',
                              _data?['today']?['remitted'] ?? 0,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _metric(
                              'Cash in Hand',
                              _data?['today']?['cashInHand'] ?? 0,
                              highlight: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 8),
                  Text(
                    'Recent Remittances',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...((_data?['remittances'] as List<dynamic>? ?? [])).map((r) {
                    return ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title: Text('₱${(r['amount'] ?? 0).toString()}'),
                      subtitle: Text((r['createdAt'] ?? '').toString()),
                      trailing:
                          (r['proof'] != null &&
                              (r['proof'] as String).isNotEmpty)
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
