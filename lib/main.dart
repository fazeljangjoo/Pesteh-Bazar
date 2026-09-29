import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dues_screen.dart';
import 'home_screen.dart';
import 'inventory_screen.dart';
import 'license_gate_screen.dart';
import 'notify_service.dart';
import 'parties_screen.dart';
import 'purchases_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'subscription_screen.dart';
import 'sync_service.dart';

void main() {
  // چترِ ایمنیِ سراسری: اگر جایی خطایی بدون try/catch رها شود (مثلاً یک استثنای
  // پیش‌بینی‌نشده‌ی دیتابیس)، به‌جای گم‌شدنِ بی‌صدا یا کرش کل اپ، حداقل لاگ می‌شود
  // و در حالت دیباگ روی کنسول دیده می‌شود.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };

    await NotifyService.I.init();
    // همگام‌سازی خودکار با سرور (ارسال تغییرات آفلاین + دریافت تغییرات سایر دستگاه‌ها)
    // نکته: یادآوری‌های سررسید بعد از ورود/باز شدن دیتابیس حساب در LicenseGate زمان‌بندی می‌شود.
    SyncService.I.start();
    runApp(const PestehApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class PestehApp extends StatelessWidget {
  const PestehApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'بازار پسته',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF5B7F2A), useMaterial3: true),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const LicenseGate(child: HomeShell()),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _pages = [
    HomeScreen(),
    PurchasesScreen(),
    SalesScreen(),
    InventoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      body: IndexedStack(index: _i, children: _pages),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'moreMenu',
        tooltip: 'بیشتر (سررسید، طرف‌حساب، گزارش، اشتراک)',
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        child: const Icon(Icons.menu),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('بازار پسته', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('سررسیدها'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DuesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_alt_outlined),
                title: const Text('طرف‌حساب‌ها'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PartiesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.assessment_outlined),
                title: const Text('گزارش سود و زیان'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('اشتراک من'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), label: 'خرید'),
          NavigationDestination(icon: Icon(Icons.sell_outlined), label: 'فروش'),
          NavigationDestination(icon: Icon(Icons.warehouse_outlined), label: 'موجودی'),
        ],
      ),
    );
  }
}
