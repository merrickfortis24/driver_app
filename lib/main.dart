import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'pages/login.dart';
import 'services/theme_controller.dart';
import 'services/animation_controller.dart';

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
  late final Animation<Offset> _pos;
  int _last = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pos = Tween(
      begin: const Offset(-1.2, 0.0),
      end: const Offset(1.2, 0.0),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    MotorcycleAnimationService.instance.trigger.addListener(_onTrigger);
  }

  void _onTrigger() {
    final v = MotorcycleAnimationService.instance.trigger.value;
    if (v == _last) return;
    _last = v;
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
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _pos,
          builder: (context, child) {
            final offset = _pos.value;
            return FractionalTranslation(
              translation: offset,
              child: Visibility(
                visible:
                    _ctrl.status != AnimationStatus.dismissed &&
                    _ctrl.status != AnimationStatus.reverse,
                child: IgnorePointer(
                  child: SizedBox(
                    width: 120,
                    height: 60,
                    child: Icon(Icons.motorcycle, size: 56, color: cs.primary),
                  ),
                ),
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
