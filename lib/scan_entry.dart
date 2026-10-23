// پسته‌بازار (اندروید) — اسکن بارکد با دوربین + ورود دستی کد.
// فقط کد Code128 خوانده می‌شود؛ کد قابل‌چاپ (KH/MX) با Navigator.pop برمی‌گردد.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'barcode_utils.dart';

/// صفحهٔ اسکن تمام‌صفحه. کد معتبر را برمی‌گرداند؛ null یعنی کاربر بدون انتخاب بسته است.
Future<String?> scanBarcode(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => const _ScanPage(),
      fullscreenDialog: true,
    ),
  );
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final MobileScannerController _ctrl = MobileScannerController(
    formats: const [BarcodeFormat.code128],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// فقط یک بار بسته می‌شود (جلوگیری از دوبار pop وقتی بارکد پشت‌سرهم خوانده شود)
  void _finish(String code) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final code = normalizeScan(b.rawValue ?? '');
      if (code != null) {
        _finish(code);
        return;
      }
    }
  }

  Future<void> _manual() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualCodeDialog(),
    );
    if (text == null || !mounted) return;
    final code = normalizeScan(text);
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کد نامعتبر است؛ مثلاً KH00012 یا MX00003')),
      );
      return;
    }
    _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('اسکن بارکد'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _ctrl,
            builder: (context, state, _) {
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: 'چراغ‌قوه',
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                onPressed: () => _ctrl.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'دسترسی به دوربین داده نشد یا دوربین در دسترس نیست. از «ورود دستی کد» استفاده کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, height: 1.8),
                ),
              ),
            ),
          ),
          // قاب راهنما
          IgnorePointer(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            bottom: 96,
            left: 16,
            right: 16,
            child: Text(
              'بارکد را داخل قاب قرار دهید',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _manual,
            icon: const Icon(Icons.keyboard),
            label: const Text('ورود دستی کد'),
          ),
        ),
      ),
    );
  }
}

/// دیالوگ ورود دستی کد. متن را برمی‌گرداند؛ اعتبارسنجی در _manual انجام می‌شود.
class _ManualCodeDialog extends StatefulWidget {
  const _ManualCodeDialog();

  @override
  State<_ManualCodeDialog> createState() => _ManualCodeDialogState();
}

class _ManualCodeDialogState extends State<_ManualCodeDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ورود دستی کد پسته'),
      content: TextField(
        controller: _text,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: 'مثلاً KH00012'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('تأیید'),
        ),
      ],
    );
  }
}
