import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:http/http.dart' as http;
import '../models/delivery.dart';

class MapPage extends StatefulWidget {
  final DeliveryOrder order;
  const MapPage({super.key, required this.order});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _map = MapController();
  StreamSubscription<Position>? _posSub;
  Position? _current;
  // In-app routing state
  bool _loadingRoute = false;
  List<ll.LatLng> _route = const [];
  String? _routeError;

  @override
  void initState() {
    super.initState();
    _startLocationStream();
  }

  Future<void> _startLocationStream() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      _posSub?.cancel();
      _posSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((p) {
            if (!mounted) {
              return;
            }
            setState(() => _current = p);
          });
    } catch (_) {}
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _centerOnMe() async {
    try {
      // Ensure location services are enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Turn on Location (GPS)')));
        await Geolocator.openLocationSettings();
        return;
      }

      // Ensure we have permission
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission permanently denied. Enable it in Settings.',
            ),
          ),
        );
        await Geolocator.openAppSettings();
        return;
      }
      if (perm == LocationPermission.denied) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }

      // Try to get a fresh position, then fall back to last known if needed
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 8));
      } on TimeoutException {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) rethrow;
        pos = last;
      }

      setState(() => _current = pos);
      _map.move(ll.LatLng(pos.latitude, pos.longitude), 17);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get current location')),
      );
    }
  }

  Future<void> _buildInAppRoute({bool recenter = true}) async {
    // Requires destination coordinates and a current location
    final destLat = widget.order.latitude;
    final destLng = widget.order.longitude;
    if (destLat == null || destLng == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No destination coordinates')),
      );
      return;
    }

    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });

    try {
      // Ensure we have a current location
      Position pos;
      if (_current != null) {
        pos = _current!;
      } else {
        // Use same logic as _centerOnMe() but quieter
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw Exception('Location services off');
        }
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          throw Exception('Permission denied');
        }
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(const Duration(seconds: 8));
        } on TimeoutException {
          final last = await Geolocator.getLastKnownPosition();
          if (last == null) rethrow;
          pos = last;
        }
      }

      final from = '${pos.longitude},${pos.latitude}';
      final to = '${destLng.toStringAsFixed(6)},${destLat.toStringAsFixed(6)}';
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$from;$to?overview=full&geometries=geojson',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        throw Exception('Routing failed (${resp.statusCode})');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['routes'] == null || (data['routes'] as List).isEmpty) {
        throw Exception('No route found');
      }
      final coords = (data['routes'][0]['geometry']['coordinates'] as List)
          .cast<List>()
          .map(
            (e) =>
                ll.LatLng((e[1] as num).toDouble(), (e[0] as num).toDouble()),
          )
          .toList(growable: false);
      setState(() {
        _route = coords;
      });

      if (recenter && coords.isNotEmpty) {
        // Simple recenter to the middle of the route
        final mid = coords[coords.length ~/ 2];
        _map.move(mid, 14);
      }
    } on TimeoutException {
      setState(() {
        _routeError = 'Routing timed out';
      });
    } catch (e) {
      setState(() {
        _routeError = 'Could not build route';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRoute = false;
        });
      }
      if (mounted && _routeError != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_routeError!)));
      }
    }
  }

  void _clearInAppRoute() {
    setState(() {
      _route = const [];
      _routeError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double? lat = widget.order.latitude;
    final double? lng = widget.order.longitude;

    if (lat == null || lng == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery Destination')),
        body: _NoCoords(address: widget.order.deliveryAddress),
        bottomNavigationBar: _BottomBar(address: widget.order.deliveryAddress),
      );
    }

    final dest = ll.LatLng(lat, lng);
    final me = _current == null
        ? null
        : ll.LatLng(_current!.latitude, _current!.longitude);

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Destination')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(initialCenter: dest, initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.driver_app',
              ),
              if (_route.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route,
                      strokeWidth: 5,
                      color: Colors.blueAccent,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Destination marker
                  Marker(
                    point: dest,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 36,
                    ),
                  ),
                  // Current location marker (if available)
                  if (me != null)
                    Marker(
                      point: me,
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Color(0x33000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Quick center-on-me button
          Positioned(
            right: 12,
            bottom: 120,
            child: FloatingActionButton.small(
              heroTag: 'center_on_me',
              onPressed: _centerOnMe,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BottomBar(
            lat: lat,
            lng: lng,
            address: widget.order.deliveryAddress,
            onInAppNavigate: () async {
              if (_route.isEmpty) {
                await _buildInAppRoute();
              } else {
                _clearInAppRoute();
              }
            },
            loading: _loadingRoute,
            showingRoute: _route.isNotEmpty,
          ),
          _ArrivalBar(
            destLat: lat,
            destLng: lng,
            address: widget.order.deliveryAddress,
            phone: widget.order.customerPhone,
          ),
        ],
      ),
    );
  }
}

class _NoCoords extends StatelessWidget {
  final String address;
  const _NoCoords({required this.address});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No coordinates available for this address.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(address, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'You can still open it in your maps app to navigate.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final double? lat;
  final double? lng;
  final String address;
  final Future<void> Function()? onInAppNavigate;
  final bool loading;
  final bool showingRoute;
  const _BottomBar({
    this.lat,
    this.lng,
    required this.address,
    this.onInAppNavigate,
    this.loading = false,
    this.showingRoute = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasCoords = lat != null && lng != null;
    final query = hasCoords
        ? '${lat!.toStringAsFixed(6)},${lng!.toStringAsFixed(6)}'
        : Uri.encodeComponent(address);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final url =
                      'https://www.google.com/maps/search/?api=1&query=$query';
                  try {
                    final ok = await launchUrlString(
                      url,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open Google Maps'),
                        ),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open Google Maps'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open in Google Maps'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onInAppNavigate,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.alt_route),
                label: Text(showingRoute ? 'Hide route' : 'Navigate (in app)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrivalBar extends StatefulWidget {
  final double destLat;
  final double destLng;
  final String address;
  final String phone;
  const _ArrivalBar({
    required this.destLat,
    required this.destLng,
    required this.address,
    required this.phone,
  });

  @override
  State<_ArrivalBar> createState() => _ArrivalBarState();
}

class _ArrivalBarState extends State<_ArrivalBar> {
  bool _checking = false;
  bool _arrived = false;
  String? _error;

  Future<void> _checkArrival() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        setState(() {
          _error = 'Location services are turned off';
        });
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Location permission permanently denied';
        });
        await Geolocator.openAppSettings();
        return;
      }
      if (perm == LocationPermission.denied) {
        setState(() {
          _error = 'Location permission denied';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));

      final distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        widget.destLat,
        widget.destLng,
      );

      setState(() {
        _arrived = distance <= 60;
      });
      if (!_arrived && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You are ${distance.toStringAsFixed(0)}m away. Get closer to call.',
            ),
          ),
        );
      }
    } on TimeoutException {
      setState(() {
        _error = 'Location request timed out';
      });
    } catch (_) {
      setState(() {
        _error = 'Location error';
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
    final num = widget.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final tel = 'tel:$num';
    try {
      await launchUrlString(tel);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checking ? null : _checkArrival,
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
                    onPressed: _arrived ? _call : null,
                    icon: const Icon(Icons.call),
                    label: Text(_arrived ? widget.phone : 'Call customer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
