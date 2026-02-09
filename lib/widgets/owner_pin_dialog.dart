import 'package:flutter/material.dart';

class OwnerPinDialog extends StatefulWidget {
  const OwnerPinDialog({
    super.key,
    required this.onAuthenticate,
  });

  final Future<bool> Function(String pin) onAuthenticate;

  @override
  State<OwnerPinDialog> createState() => _OwnerPinDialogState();
}

class _OwnerPinDialogState extends State<OwnerPinDialog> {
  String _pin = '';
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_isSubmitting || _pin.isEmpty) {
      return;
    }
    setState(() {
      _isSubmitting = true;
    });
    final success = await widget.onAuthenticate(_pin);
    if (!mounted) {
      return;
    }
    if (success) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _pin = '';
      _isSubmitting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN salah. Akses ditolak.')),
    );
  }

  void _appendDigit(String digit) {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _pin += digit;
    });
  }

  void _submitIfReady() {
    if (_pin.isEmpty || _isSubmitting) {
      return;
    }
    _submit();
  }

  void _backspace() {
    if (_pin.isEmpty || _isSubmitting) {
      return;
    }
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    const maroon = Color(0xFF8D1B3D);
    const cream = Color(0xFFFFF3E0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: cream,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Masuk Menu Akun',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: maroon,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Masukkan PIN Owner',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            _PinDots(length: _pin.length),
            const SizedBox(height: 16),
            _PinPad(
              onDigit: _appendDigit,
              onBackspace: _backspace,
              onSubmit: _submitIfReady,
              isSubmitting: _isSubmitting,
              canSubmit: _pin.isNotEmpty,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.length});

  final int length;

  @override
  Widget build(BuildContext context) {
    if (length == 0) {
      return const SizedBox(height: 14);
    }
    return Wrap(
      alignment: WrapAlignment.center,
      children: List.generate(length, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFF8D1B3D),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
    required this.isSubmitting,
    required this.canSubmit,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final bool isSubmitting;
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    const digits = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
    ];

    return Column(
      children: [
        for (int row = 0; row < 3; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int col = 0; col < 3; col++)
                  _PinButton(
                    label: digits[row * 3 + col],
                    onTap: isSubmitting ? null : () => onDigit(digits[row * 3 + col]),
                  ),
              ],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PinButton(
              label: '0',
              onTap: isSubmitting ? null : () => onDigit('0'),
            ),
            _PinButton(
              icon: Icons.check_circle,
              color: canSubmit ? const Color(0xFF8D1B3D) : Colors.grey,
              onTap: isSubmitting || !canSubmit ? null : onSubmit,
            ),
            _PinButton(
              icon: Icons.backspace_outlined,
              onTap: isSubmitting ? null : onBackspace,
            ),
          ],
        ),
      ],
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({
    this.label,
    this.icon,
    this.color,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(36),
        onTap: onTap,
        child: Ink(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: const Color(0xFF8D1B3D), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, color: color ?? const Color(0xFF8D1B3D))
                : Text(
                    label ?? '',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8D1B3D),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
