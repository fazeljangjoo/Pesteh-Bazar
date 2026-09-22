import 'package:flutter/material.dart';

import 'inventory_screen.dart';
import 'notify_service.dart';
import 'purchases_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotifyService.I.init();
  // یادآوری‌های پرداخت‌نشده را دوباره زمان‌بندی می‌کند (پس از راه‌اندازی مجدد گوشی هم لازم است)
  // ignore: unawaited_futures
  NotifyService.I.rescheduleAll();
  runApp(const PestehApp());
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
      home: const HomeShell(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _i,
        children: const [
          PurchasesScreen(),
          InventoryScreen(),
          SalesScreen(),
          ReportsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), label: 'خرید'),
          NavigationDestination(icon: Icon(Icons.warehouse_outlined), label: 'موجودی'),
          NavigationDestination(icon: Icon(Icons.sell_outlined), label: 'فروش'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), label: 'گزارش'),
        ],
      ),
    );
  }
}
