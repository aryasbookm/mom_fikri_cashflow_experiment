import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/transaction_provider.dart';
import 'main_screen.dart';
import 'staff_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isBiometricReady = false;
  bool _isBiometricLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeBiometricQuickLogin();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _initializeBiometricQuickLogin() async {
    final authProvider = context.read<AuthProvider>();
    final enabled = await authProvider.isBiometricQuickLoginEnabled();
    final hasSession = await authProvider.hasBiometricSession();
    final supported = await _localAuth.isDeviceSupported();
    final canCheck = await _localAuth.canCheckBiometrics;
    final ready = enabled && hasSession && supported && canCheck;
    if (!mounted) {
      return;
    }
    setState(() {
      _isBiometricReady = ready;
      _isBiometricLoading = false;
    });
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final pin = _pinController.text.trim();

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(username, pin);

    if (!mounted) {
      return;
    }

    if (success) {
      await _navigateAfterLogin();
      if (!mounted) {
        return;
      }
      final canUseBiometric = await authProvider.hasBiometricSession();
      if (!mounted) {
        return;
      }
      setState(() {
        _isBiometricReady = canUseBiometric;
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Username atau PIN salah')));
    }
  }

  Future<void> _handleBiometricLogin() async {
    if (_isBiometricLoading) {
      return;
    }
    setState(() {
      _isBiometricLoading = true;
    });
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason:
            'Verifikasi sidik jari untuk masuk ke Toko Kue Mom Fiqry',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!authenticated) {
        return;
      }
      if (!mounted) {
        return;
      }
      final authProvider = context.read<AuthProvider>();
      final user = await authProvider.loginWithBiometricSession();
      if (user == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sesi sidik jari tidak ditemukan. Login manual dulu.',
            ),
          ),
        );
        setState(() {
          _isBiometricReady = false;
        });
        return;
      }
      await _navigateAfterLogin();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal autentikasi sidik jari. Coba lagi.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBiometricLoading = false;
        });
      }
    }
  }

  Future<void> _disableBiometricQuickLogin() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.clearBiometricSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _isBiometricReady = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Login sidik jari dinonaktifkan.')),
    );
  }

  Future<void> _navigateAfterLogin() async {
    if (!mounted) {
      return;
    }
    final role = context.read<AuthProvider>().currentUser?.role;
    if (role == 'owner') {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } else if (role == 'staff') {
      context.read<TransactionProvider>().clearTransactions();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StaffDashboard()),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Role tidak dikenali')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color(0xFF8D1B3D);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8D1B3D), Color(0xFFC2185B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storefront_rounded, size: 80, color: themeColor),
                    const SizedBox(height: 16),
                    Text(
                      'Toko Kue Mom Fiqry',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: themeColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'PIN',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Masuk',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (!_isBiometricLoading && _isBiometricReady) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _handleBiometricLogin,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Masuk dengan Sidik Jari'),
                          style: OutlinedButton.styleFrom(
                            shape: const StadiumBorder(),
                            side: BorderSide(color: themeColor),
                            foregroundColor: themeColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _disableBiometricQuickLogin,
                        child: const Text('Nonaktifkan Sidik Jari'),
                      ),
                    ],
                    if (_isBiometricLoading) ...[
                      const SizedBox(height: 12),
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
