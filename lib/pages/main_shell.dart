import 'package:flutter/material.dart';
import 'home.dart';
import 'cash_page.dart';
import 'profile_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_index) {
      case 0:
        body = const HomePage(initialTab: 'active');
        break;
      case 1:
        body = const HomePage(initialTab: 'history');
        break;
      case 2:
        body = const CashPage();
        break;
      case 3:
        body = const ProfilePage();
        break;
      default:
        body = const HomePage();
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (v) => setState(() => _index = v),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.place_outlined),
            label: 'Active',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.payments), label: 'Cash'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Profile',
          ),
        ],
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
