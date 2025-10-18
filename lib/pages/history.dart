import 'package:flutter/material.dart';
import 'home.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomePage(initialTab: 'history', showTopTabs: false);
  }
}
