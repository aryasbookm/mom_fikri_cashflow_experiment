import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/owner_pin_dialog.dart';
import 'account_screen.dart';
import 'login_screen.dart';
import 'owner_dashboard.dart';
import 'ocr_assist_screen.dart';
import 'production_screen.dart';
import 'report_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<OwnerDashboardState> _ownerDashboardKey =
      GlobalKey<OwnerDashboardState>();
  final GlobalKey<ReportScreenState> _reportKey =
      GlobalKey<ReportScreenState>();

  late final List<Widget> _pages = [
    OwnerDashboard(
      key: _ownerDashboardKey,
      onAiStateChanged: _handleOwnerAiStateChanged,
    ),
    ReportScreen(key: _reportKey),
    const ProductionScreen(showAppBar: false),
    const AccountScreen(),
  ];

  void _handleOwnerAiStateChanged() {
    if (!mounted || _currentIndex != 0) {
      return;
    }
    setState(() {});
  }

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

  Future<bool> _ensureOwnerAccess() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    if (user?.role != 'owner') {
      return true;
    }
    if (authProvider.isOwnerAuthenticated) {
      return true;
    }
    final result = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return OwnerPinDialog(onAuthenticate: authProvider.authenticateOwner);
      },
    );
    if (result == 'logout') {
      authProvider.logout();
      if (!mounted) {
        return false;
      }
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
      return false;
    }
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final reportState = _reportKey.currentState;
    final ownerState = _ownerDashboardKey.currentState;
    final aiLoading = ownerState?.isAiLoading ?? false;
    final aiCooldownSeconds = ownerState?.aiCooldownSeconds ?? 0;
    final aiTemporarilyUnavailable =
        ownerState?.isAiTemporarilyUnavailable ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForIndex(_currentIndex)),
        actions:
            _currentIndex == 1
                ? [
                  IconButton(
                    onPressed:
                        reportState?.isExporting == true
                            ? null
                            : reportState?.exportPdf,
                    icon:
                        reportState?.isExporting == true
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.picture_as_pdf),
                    tooltip: 'Export PDF',
                  ),
                ]
                : _currentIndex == 0
                ? [
                  IconButton(
                    onPressed: () async {
                      final state = _ownerDashboardKey.currentState;
                      if (state == null) {
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Beranda belum siap, coba lagi sebentar.',
                            ),
                          ),
                        );
                        setState(() {});
                        return;
                      }
                      await state.triggerAiInsightFromAppBar();
                    },
                    icon:
                        aiLoading
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : Icon(
                              Icons.auto_awesome,
                              color:
                                  aiTemporarilyUnavailable || ownerState == null
                                      ? Colors.white70
                                      : Colors.white,
                            ),
                    tooltip:
                        aiCooldownSeconds > 0
                            ? 'AI jeda $aiCooldownSeconds detik'
                            : 'Minta Saran AI',
                  ),
                ]
                : null,
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
      floatingActionButton:
          _currentIndex == 0
              ? FloatingActionButton.extended(
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OcrAssistScreen()),
                    ),
                backgroundColor: const Color(0xFF8D1B3D),
                icon: const Icon(Icons.document_scanner_outlined, color: Colors.white),
                label: const Text(
                  'Scan Catatan',
                  style: TextStyle(color: Colors.white),
                ),
              )
              : null,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF8D1B3D),
        backgroundColor: Colors.white,
        currentIndex: _currentIndex,
        onTap: (index) async {
          if (index == 3) {
            final allowed = await _ensureOwnerAccess();
            if (!allowed) {
              return;
            }
          }
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Beranda'),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Laporan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bakery_dining),
            label: 'Produksi',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Akun'),
        ],
      ),
    );
  }
}
