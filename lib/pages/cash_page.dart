import 'package:flutter/material.dart';
import '../services/delivery_api.dart';
import '../widgets/header_icon.dart';
import '../services/theme_controller.dart';

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
  // Remittance state
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.fetchCashSummary();
      if (!mounted) return;
      setState(() {
        _data = d;
        final today = d['today'] as Map<String, dynamic>? ?? {};
        final cashInHand = (today['cashInHand'] is num)
            ? (today['cashInHand'] as num).toDouble()
            : double.tryParse((today['cashInHand'] ?? '0').toString()) ?? 0.0;
        _amountCtrl.text = cashInHand > 0 ? cashInHand.toStringAsFixed(2) : '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    final today = _data?['today'] as Map<String, dynamic>? ?? {};
    final cashInHand = (today['cashInHand'] is num)
        ? (today['cashInHand'] as num).toDouble()
        : double.tryParse((today['cashInHand'] ?? '0').toString()) ?? 0.0;
    final v = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (v <= 0 || v > cashInHand + 0.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter an amount between 0 and ₱${cashInHand.toStringAsFixed(2)}',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      final res = await _api.submitRemittance(
        amount: v,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        proofJpeg: null,
      );
      if (!mounted) return;
      setState(() {
        _data = res;
        final t = res['today'] as Map<String, dynamic>? ?? {};
        final newCash = (t['cashInHand'] is num)
            ? (t['cashInHand'] as num).toDouble()
            : double.tryParse((t['cashInHand'] ?? '0').toString()) ?? 0.0;
        _amountCtrl.text = newCash > 0 ? newCash.toStringAsFixed(2) : '';
        _noteCtrl.clear();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Remittance submitted')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                  HeaderIcon(
                    title: 'Cash',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
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
                  // Remittance Form
                  Text(
                    'Remit Cash in Hand',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Amount to Remit (PHP)',
                      helperText: 'Prefilled with today\'s Cash in Hand',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.payments_outlined),
                      label: const Text('Remit'),
                    ),
                  ),
                  const SizedBox(height: 16),
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

// header icon moved to shared widget HeaderIcon
