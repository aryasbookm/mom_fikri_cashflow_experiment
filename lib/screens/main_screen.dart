import 'package:flutter/material.dart';

import 'account_screen.dart';
import 'owner_dashboard.dart';
import 'production_screen.dart';
import 'report_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    OwnerDashboard(),
    ReportScreen(),
    ProductionScreen(showAppBar: false),
    AccountScreen(),
  ];

  String _titleForIndex(int index) {
    switch (index) {
      case 0:
        return 'Toko Kue Mom Fiqry';
      case 1:
        return 'Laporan';
      case 2:
        return 'Produksi';
      case 3:
        return 'Akun';
      default:
        return 'Toko Kue Mom Fiqry';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForIndex(_currentIndex)),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF8D1B3D),
        backgroundColor: Colors.white,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Laporan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bakery_dining),
            label: 'Produksi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Akun',
          ),
        ],
      ),
    );
  }
}
