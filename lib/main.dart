import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'pages/login.dart';
import 'services/theme_controller.dart';
import 'services/animation_controller.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:lottie/lottie.dart';

void main() {
  // Simple logging configuration for development.
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print(
      '${record.level.name}: ${record.loggerName}: ${record.time}: ${record.message}',
    );
  });

  final theme = ThemeController.instance;
  WidgetsFlutterBinding.ensureInitialized();
  theme.load().then((_) {
    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: theme.mode,
      builder: (context, mode, _) {
        // Use a beige-first color scheme
        final beigeSeed = const Color(0xFFDCC9B6);
        return MaterialApp(
          title: 'Nai Tsa Driver',
          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: beigeSeed,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF6F1EC),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: beigeSeed,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          // Ensure the overlay wraps every route by using the builder.
          builder: (context, child) => MotorcycleAnimationOverlay(
            child: child ?? const SizedBox.shrink(),
          ),
          home: const SplashPage(),
        );
      },
    );
  }
}

class MotorcycleAnimationOverlay extends StatefulWidget {
  final Widget child;
  const MotorcycleAnimationOverlay({required this.child, super.key});

  @override
  State<MotorcycleAnimationOverlay> createState() =>
      _MotorcycleAnimationOverlayState();
}

class _MotorcycleAnimationOverlayState extends State<MotorcycleAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  int _last = 0;
  // optional sound player and lottie support are lazy-loaded when needed
  AudioPlayer? _player;
  final bool _lottieAvailable = true; // we included lottie package

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _player = AudioPlayer();
    MotorcycleAnimationService.instance.trigger.addListener(_onTrigger);
  }

  void _onTrigger() {
    final svc = MotorcycleAnimationService.instance;
    final v = svc.trigger.value;
    if (v == _last) return;
    _last = v;
    // Play sound if provided
    if (svc.lastSoundAsset != null && _player != null) {
      try {
        _player!.play(AssetSource(svc.lastSoundAsset!));
      } catch (_) {}
    }
    _ctrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    MotorcycleAnimationService.instance.trigger.removeListener(_onTrigger);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final svc = MotorcycleAnimationService.instance;
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _t,
          builder: (context, child) {
            final t = _t.value;
            // cubic bezier between four fractional points
            final p0 = const Offset(-0.3, 1.2);
            final p1 = const Offset(0.15, 0.7);
            final p2 = const Offset(0.85, 0.15);
            final p3 = const Offset(1.2, -0.4);
            double u = 1 - t;
            final x =
                (u * u * u) * p0.dx +
                3 * (u * u) * t * p1.dx +
                3 * u * (t * t) * p2.dx +
                (t * t * t) * p3.dx;
            final y =
                (u * u * u) * p0.dy +
                3 * (u * u) * t * p1.dy +
                3 * u * (t * t) * p2.dy +
                (t * t * t) * p3.dy;
            final size = svc.lastSize;
            final mq = MediaQuery.of(context).size;
            final dx = x * mq.width;
            final dy = y * mq.height;
            final visible =
                _ctrl.status != AnimationStatus.dismissed &&
                _ctrl.status != AnimationStatus.reverse;
            if (!visible) return const SizedBox.shrink();
            Widget animChild;
            if (svc.lastUseLottie && _lottieAvailable) {
              try {
                animChild = Lottie.asset(
                  'assets/motorcycle.json',
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                );
              } catch (_) {
                animChild = Icon(
                  Icons.motorcycle,
                  size: size,
                  color: cs.primary,
                );
              }
            } else {
              animChild = Icon(Icons.motorcycle, size: size, color: cs.primary);
            }
            return Positioned(
              left: dx - (size / 2),
              top: dy - (size / 2),
              child: IgnorePointer(
                child: SizedBox(width: size, height: size, child: animChild),
              ),
            );
          },
        ),
      ],
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              child: Icon(Icons.motorcycle, size: 72, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'Nai Tsa Driver',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
