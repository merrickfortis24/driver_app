import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../models/delivery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/delivery_api.dart';
import '../services/delivery_exceptions.dart';
import 'login.dart';
import 'map_page.dart';
import 'proof_capture_page.dart';

class HomePage extends StatefulWidget {
  final String initialTab;
  final bool showTopTabs; // controls whether the Active/History chips are shown
  const HomePage({
    super.key,
    this.initialTab = 'active',
    this.showTopTabs = true,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  final _api = DeliveryApi.instance;

  List<DeliveryOrder> _orders = [];
  bool _loading = true;
  String? _error;
  String _activeTab = 'active'; // 'active' | 'history'
  bool _refreshing = false;

  // Sorting/Filtering
  SortOption _sort = SortOption.status;
  OrderStatus? _activeFilter; // null = All
  OrderStatus? _historyFilter; // null = All
  Position? _position; // cached user location for distance sort
  bool _gettingPosition = false;
  bool _positionRequestedOnce =
      false; // avoid rescheduling multiple times per frame
  static const double _avgSpeedKmh = 25; // rough urban average for ETA

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await _api.fetchOrders();
      if (mounted) {
        setState(() => _orders = orders);
      }
    } catch (e) {
      // Provide a more helpful message and handle unauthorized by
      // clearing stored token and redirecting to login.
      if (e is UnauthorizedException) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('token');
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }

      final message = e is ApiException ? e.message : e.toString();
      if (mounted) {
        setState(() => _error = message);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final orders = await _api.fetchOrders();
      if (mounted) {
        setState(() => _orders = orders);
      }
    } catch (e) {
      if (e is UnauthorizedException) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('token');
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
        return;
      }
      if (mounted) {
        setState(() => _error = e is ApiException ? e.message : e.toString());
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  // Ensure we have a current position when sorting by distance.
  Future<void> _ensurePosition() async {
    if (_position != null || _gettingPosition) {
      return;
    }
    setState(() => _gettingPosition = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission denied. Distance sort may be inaccurate.',
              ),
            ),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() => _position = pos);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _gettingPosition = false);
      }
    }
  }

  double _distanceMeters(DeliveryOrder o) {
    if (_position == null || o.latitude == null || o.longitude == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
      _position!.latitude,
      _position!.longitude,
      o.latitude!,
      o.longitude!,
    );
  }

  Duration _etaFromMeters(double meters) {
    if (meters.isInfinite || meters.isNaN) return Duration.zero;
    final mps = _avgSpeedKmh * 1000 / 3600; // meters per second
    if (mps <= 0) return Duration.zero;
    final secs = (meters / mps).round();
    return Duration(seconds: secs);
  }

  String _formatDistance(double meters) {
    if (meters.isInfinite || meters.isNaN) return '';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatEta(Duration d) {
    if (d == Duration.zero) return '';
    if (d.inMinutes < 1) return '<1 min';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  int _statusRank(OrderStatus s) {
    switch (s) {
      case OrderStatus.assigned:
        return 0;
      case OrderStatus.accepted:
        return 1;
      case OrderStatus.onTheWay:
        return 2;
      case OrderStatus.pickedUp:
        return 3;
      case OrderStatus.delivered:
        return 4;
      case OrderStatus.rejected:
        return 5;
    }
  }

  List<DeliveryOrder> _applySort(List<DeliveryOrder> items) {
    final list = [...items];
    switch (_sort) {
      case SortOption.amount:
        list.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
        break;
      case SortOption.status:
        list.sort(
          (a, b) => _statusRank(a.status).compareTo(_statusRank(b.status)),
        );
        break;
      case SortOption.distance:
        // Schedule a position fetch after the current frame to avoid setState during build.
        if (_position == null && !_gettingPosition) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _ensurePosition(),
          );
        }
        list.sort((a, b) => _distanceMeters(a).compareTo(_distanceMeters(b)));
        break;
    }
    return list;
  }

  String _sortLabel(SortOption s) {
    switch (s) {
      case SortOption.distance:
        return 'Distance';
      case SortOption.amount:
        return 'Amount';
      case SortOption.status:
        return 'Status';
    }
  }

  IconData _sortIcon(SortOption s) {
    switch (s) {
      case SortOption.distance:
        return Icons.place_outlined;
      case SortOption.amount:
        return Icons.attach_money;
      case SortOption.status:
        return Icons.flag_outlined;
    }
  }

  Color _statusColor(OrderStatus s) {
    switch (s) {
      case OrderStatus.assigned:
        return Colors.orange;
      case OrderStatus.accepted:
        return Colors.blue;
      case OrderStatus.rejected:
        return Colors.red;
      case OrderStatus.onTheWay:
        return Colors.indigo;
      case OrderStatus.pickedUp:
        return Colors.teal;
      case OrderStatus.delivered:
        return Colors.green;
    }
  }

  String _statusText(OrderStatus s) {
    switch (s) {
      case OrderStatus.assigned:
        return 'Assigned';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.rejected:
        return 'Rejected';
      case OrderStatus.onTheWay:
        return 'On the way';
      case OrderStatus.pickedUp:
        return 'Picked up';
      case OrderStatus.delivered:
        return 'Delivered';
    }
  }

  List<Widget> _buildActions(DeliveryOrder o) {
    final actions = <Widget>[];
    switch (o.status) {
      case OrderStatus.assigned:
        actions.addAll([
          TextButton(
            onPressed: () async {
              await _api.acceptOrder(o.id);
              _refresh();
            },
            child: const Text('Accept'),
          ),
          TextButton(
            onPressed: () async {
              await _api.rejectOrder(o.id);
              _refresh();
            },
            child: const Text('Reject'),
          ),
        ]);
        break;
      case OrderStatus.accepted:
        actions.add(
          TextButton(
            onPressed: () async {
              await _api.updateOrderStatus(o.id, OrderStatus.onTheWay);
              _refresh();
            },
            child: const Text('Start'),
          ),
        );
        break;
      case OrderStatus.onTheWay:
        actions.add(
          TextButton(
            onPressed: () async {
              await _api.updateOrderStatus(o.id, OrderStatus.pickedUp);
              _refresh();
            },
            child: const Text('Picked up'),
          ),
        );
        break;
      case OrderStatus.pickedUp:
        actions.add(
          TextButton(
            onPressed: () async {
              // Collect proofs and amount before marking delivered
              final amount = await Navigator.of(context).push<double>(
                MaterialPageRoute(builder: (_) => ProofCapturePage(order: o)),
              );
              // amount will be null if user cancelled the screen
              if (amount != null) {
                await _api.updateOrderStatus(
                  o.id,
                  OrderStatus.delivered,
                  collectedAmount: amount,
                );
                if (mounted) _refresh();
              }
            },
            child: const Text('Delivered'),
          ),
        );
        break;
      case OrderStatus.rejected:
      case OrderStatus.delivered:
        break;
    }
    return actions;
  }

  Widget _orderTile(DeliveryOrder o) {
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor(o.status);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Privacy: don't allow opening map for delivered orders (shown in History)
        onTap: o.status == OrderStatus.delivered
            ? null
            : () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => MapPage(order: o)));
              },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: .5)),
                    ),
                    child: Text(
                      _statusText(o.status),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Total: ${_peso.format(o.totalAmount)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                o.customerName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: null),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      o.deliveryAddress,
                      style: TextStyle(color: cs.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // Distance + ETA
              Builder(
                builder: (_) {
                  final dist = _distanceMeters(o);
                  if (dist.isInfinite || dist.isNaN) {
                    return const SizedBox.shrink();
                  }
                  final eta = _etaFromMeters(dist);
                  final distText = _formatDistance(dist);
                  final etaText = _formatEta(eta);
                  final showEta = etaText.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.near_me_outlined,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          showEta ? '$distText • ~$etaText' : distText,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              if (o.deliveryInstructions != null &&
                  o.deliveryInstructions!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  o.deliveryInstructions!,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: -8,
                children: o.items
                    .map(
                      (i) => Chip(
                        label: Text('${i.quantity} x ${i.name}'),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Row(children: [..._buildActions(o)]),
              const SizedBox(height: 8),
              _ArrivalActions(order: o),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If we plan to show distance on cards and we don't have a position yet,
    // request it after this frame (avoids setState during build).
    if (_position == null && !_gettingPosition && !_positionRequestedOnce) {
      _positionRequestedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensurePosition();
        // allow future re-requests if it failed or permissions change
        _positionRequestedOnce = false;
      });
    }
    final header = PreferredSize(
      preferredSize: const Size.fromHeight(110),
      child: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A5AE0), Color(0xFF4C6FD7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_shipping_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Welcome back!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Driver',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Cash/Profile moved to bottom navigation — keep refresh only
                  IconButton(
                    onPressed: _refreshing ? null : _refresh,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.refresh, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
      ),
    );

    final stats = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _StatCard(
            icon: Icons.inventory_2_outlined,
            label: 'Pending',
            value: _orders
                .where((o) => o.status == OrderStatus.assigned)
                .length,
            color: const Color(0xFF6A5AE0),
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.access_time,
            label: 'Active',
            value: _orders
                .where(
                  (o) =>
                      o.status == OrderStatus.accepted ||
                      o.status == OrderStatus.onTheWay ||
                      o.status == OrderStatus.pickedUp,
                )
                .length,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 10),
          _StatCard(
            icon: Icons.check_circle_outline,
            label: 'Delivered',
            value: _orders
                .where((o) => o.status == OrderStatus.delivered)
                .length,
            color: const Color(0xFF10B981),
          ),
        ],
      ),
    );

    final tabs = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _activeTab = 'active'),
              icon: const Icon(Icons.place_outlined),
              label: const Text('Active Orders'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _activeTab == 'active'
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
                backgroundColor: _activeTab == 'active'
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surface,
                side: BorderSide(
                  color: _activeTab == 'active'
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _activeTab = 'history'),
              icon: const Icon(Icons.history),
              label: const Text('History'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _activeTab == 'history'
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
                backgroundColor: _activeTab == 'history'
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surface,
                side: BorderSide(
                  color: _activeTab == 'history'
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Sort and Filter controls
    final sortAndFilter = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PopupMenuButton<SortOption>(
                tooltip: 'Sort',
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: SortOption.distance,
                    child: ListTile(
                      leading: Icon(Icons.place_outlined),
                      title: Text('Distance (nearest)'),
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.amount,
                    child: ListTile(
                      leading: Icon(Icons.attach_money),
                      title: Text('Amount (highest)'),
                    ),
                  ),
                  PopupMenuItem(
                    value: SortOption.status,
                    child: ListTile(
                      leading: Icon(Icons.flag_outlined),
                      title: Text('Status'),
                    ),
                  ),
                ],
                child: OutlinedButton.icon(
                  onPressed: null, // triggers popup by parent
                  icon: Icon(_sortIcon(_sort)),
                  label: Text('Sort: ${_sortLabel(_sort)}'),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  (_activeTab == 'active'
                          ? const [
                              OrderStatus.assigned,
                              OrderStatus.accepted,
                              OrderStatus.onTheWay,
                              OrderStatus.pickedUp,
                            ]
                          : const [OrderStatus.delivered, OrderStatus.rejected])
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_statusText(s)),
                            selected:
                                (_activeTab == 'active'
                                    ? _activeFilter
                                    : _historyFilter) ==
                                s,
                            onSelected: (sel) {
                              setState(() {
                                if (_activeTab == 'active') {
                                  _activeFilter = sel ? s : null;
                                } else {
                                  _historyFilter = sel ? s : null;
                                }
                              });
                            },
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
        ],
      ),
    );

    final list = Expanded(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: Builder(
          builder: (context) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null) {
              return ListView(
                children: [
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE5E5),
                        border: Border.all(color: const Color(0xFFFFB3B3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              );
            }

            var items = _activeTab == 'active'
                ? _orders
                      .where(
                        (o) =>
                            o.status == OrderStatus.assigned ||
                            o.status == OrderStatus.accepted ||
                            o.status == OrderStatus.onTheWay ||
                            o.status == OrderStatus.pickedUp,
                      )
                      .toList()
                : _orders
                      .where(
                        (o) =>
                            o.status == OrderStatus.delivered ||
                            o.status == OrderStatus.rejected,
                      )
                      .toList();

            // Apply status filters
            if (_activeTab == 'active' && _activeFilter != null) {
              items = items.where((o) => o.status == _activeFilter).toList();
            } else if (_activeTab == 'history' && _historyFilter != null) {
              items = items.where((o) => o.status == _historyFilter).toList();
            }

            // Apply sorting
            items = _applySort(items);

            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 60),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              _activeTab == 'active'
                                  ? Icons.inventory_2_outlined
                                  : Icons.history,
                              size: 48,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _activeTab == 'active'
                                  ? 'No Active Orders'
                                  : 'No Delivery History',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _activeTab == 'active'
                                  ? 'New delivery assignments will appear here'
                                  : 'Completed deliveries will appear here',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, idx) => _orderTile(items[idx]),
            );
          },
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: header,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [stats, tabs, sortAndFilter, list],
      ),
    );
  }
}

enum SortOption { distance, amount, status }

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 6),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArrivalActions extends StatefulWidget {
  final DeliveryOrder order;
  const _ArrivalActions({required this.order});

  @override
  State<_ArrivalActions> createState() => _ArrivalActionsState();
}

class _ArrivalActionsState extends State<_ArrivalActions> {
  bool _checking = false;
  bool _arrived = false;
  String? _err;
  bool get _disabledForPrivacy => widget.order.status == OrderStatus.delivered;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _err = null;
    });
    try {
      final lat = widget.order.latitude;
      final lng = widget.order.longitude;
      if (lat == null || lng == null) {
        setState(() {
          _err = 'No destination coordinates';
        });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _err = 'Location permission denied';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).timeout(const Duration(seconds: 12));
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        lat,
        lng,
      );
      setState(() {
        _arrived = d <= 60;
      });
      if (!_arrived && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You are ${d.toStringAsFixed(0)}m away.')),
        );
      }
    } catch (e) {
      setState(() {
        _err = 'Location error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<void> _call() async {
    final p = widget.order.customerPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = 'tel:$p';
    try {
      await launchUrlString(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _err!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_checking || _disabledForPrivacy) ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_outlined),
                label: Text(_arrived ? 'Arrived' : 'I am here'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_arrived && !_disabledForPrivacy) ? _call : null,
                icon: const Icon(Icons.call),
                label: Text(
                  _arrived ? widget.order.customerPhone : 'Call customer',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
