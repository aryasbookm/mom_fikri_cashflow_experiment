import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/auth_provider.dart';
import 'providers/category_provider.dart';
import 'providers/product_provider.dart';
import 'providers/production_provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/user_provider.dart';
import 'screens/login_screen.dart';
import 'services/backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isAutoBackupRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _maybeRunAutoBackup();
    }
  }

  Future<void> _maybeRunAutoBackup() async {
    if (_isAutoBackupRunning) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final enabled =
        prefs.getBool(BackupService.autoBackupEnabledKey) ?? true;
    if (!enabled) {
      return;
    }
    final lastRun = prefs.getInt(BackupService.lastAutoBackupKey);
    final now = DateTime.now();
    if (lastRun != null) {
      final elapsed = now
          .difference(DateTime.fromMillisecondsSinceEpoch(lastRun));
      if (elapsed < const Duration(hours: 24)) {
        return;
      }
    }
    _isAutoBackupRunning = true;
    try {
      await BackupService.autoBackupLocal(retention: 5);
      await prefs.setInt(
        BackupService.lastAutoBackupKey,
        now.millisecondsSinceEpoch,
      );
    } catch (_) {
      // ignore auto-backup failures
    } finally {
      _isAutoBackupRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => ProductionProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
      ],
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFFFFF8E1),
          primaryColor: const Color(0xFF8D1B3D),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF8D1B3D),
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
          textTheme: GoogleFonts.poppinsTextTheme(),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}
