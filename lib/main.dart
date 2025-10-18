import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'pages/login.dart';
import 'services/theme_controller.dart';
import 'services/animation_controller.dart';

void main() {
  // Simple logging configuration for development. In production you may
  // want to route logs to a file or remote service and change the level.
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // Print to console with a concise format — Flutter tooling will capture this.
    // Replace or extend this handler in production if needed.
    // ignore: avoid_print
    print(
      '${record.level.name}: ${record.loggerName}: ${record.time}: ${record.message}',
    );
  });

  final theme = ThemeController.instance;
  // Load saved theme before running the app
  WidgetsFlutterBinding.ensureInitialized();
  theme.load().then((_) {
    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
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
          // Wrap the app with an overlay that listens for the motorcycle trigger
          home: MotorcycleAnimationOverlay(child: const SplashPage()),
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
    return Stack(
      children: [
        widget.child,
        // Positioned transition for the motorcycle
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
                child: child!,
              ),
            );
          },
          child: IgnorePointer(
            child: SizedBox(
              width: 100,
              height: 60,
              child: Image.asset('assets/motorcycle.png', fit: BoxFit.contain),
            ),
          ),
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
    // Keep splash for a short time then navigate to Login
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
      backgroundColor: cs.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 120, child: Image.asset('assets/motorcycle.png')),
            const SizedBox(height: 16),
            Text(
              'Nai Tsa Driver',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: cs.onBackground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
