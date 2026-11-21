// «قابلیت‌های فناورانه» (پروندهٔ دانش‌بنیان) — پرچم‌های هر شرکت (features.*) و صفحهٔ روشن/خاموش کردن آن‌ها.
// منبع حقیقت = سرور (backend/api/tech_features.php، app_settings k='features.<key>'). آینهٔ محلی در SharedPreferences برای نمایش آفلاین.
// همهٔ پرچم‌ها پیش‌فرض خاموش‌اند؛ با پرچم خاموش هیچ ویجت/درخواست جدیدی در صفحه‌های موجود فعال نمی‌شود.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'perms.dart' show StaffPerms;
import 'warehouse_ui.dart' show StockApi, StockApiException;

/// کلیدهای پرچم (باید با PB_TECH_FLAGS سرور یکی باشند).
const List<String> kTechFlagKeys = <String>['anomaly', 'events', 'api', 'blend_optimizer', 'scale'];

class TechFeatures {
  TechFeatures._();
  static final TechFeatures I = TechFeatures._();

  static const String _prefix = 'tech_feature.';

  /// آخرین وضعیت شناخته‌شده؛ با هر refresh/save به‌روز می‌شود تا منو و صفحه‌ها بدون راه‌اندازی دوباره عوض شوند.
  final ValueNotifier<Map<String, bool>> flags = ValueNotifier<Map<String, bool>>(<String, bool>{});
  bool _loaded = false;

  /// خواندن آینهٔ محلی (یک بار در هر اجرا؛ بدون شبکه).
  Future<Map<String, bool>> local() async {
    if (_loaded) return flags.value;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      flags.value = <String, bool>{for (final String k in kTechFlagKeys) k: sp.getBool('$_prefix$k') ?? false};
    } catch (_) {
      flags.value = <String, bool>{for (final String k in kTechFlagKeys) k: false};
    }
    _loaded = true;
    return flags.value;
  }

  Future<bool> isOn(String key) async => (await local())[key] ?? false;

  bool isOnSync(String key) => flags.value[key] ?? false;

  Future<void> _store(List<Map<String, dynamic>> rows) async {
    final Map<String, bool> m = Map<String, bool>.from(flags.value);
    for (final Map<String, dynamic> r in rows) {
      final String k = '${r['key']}';
      if (kTechFlagKeys.contains(k)) m[k] = r['on'] == true;
    }
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      for (final MapEntry<String, bool> e in m.entries) {
        await sp.setBool('$_prefix${e.key}', e.value);
      }
    } catch (_) {}
    _loaded = true;
    flags.value = m;
  }

  static List<Map<String, dynamic>> _list(Object? v) =>
      v is List ? v.whereType<Map>().map((Map m) => Map<String, dynamic>.from(m)).toList() : <Map<String, dynamic>>[];

  /// از سرور؛ null = آفلاین/خطا (آینهٔ محلی دست نمی‌خورد).
  Future<List<Map<String, dynamic>>?> refresh() async {
    try {
      final Map<String, dynamic> r = await StockApi.call('tech.features_get');
      final List<Map<String, dynamic>> f = _list(r['features']);
      if (f.isEmpty) return null;
      await _store(f);
      return f;
    } catch (_) {
      return null;
    }
  }

  /// ذخیره روی سرور (settings.manage). خطا = StockApiException.
  Future<List<Map<String, dynamic>>> save(Map<String, bool> settings) async {
    final Map<String, dynamic> r = await StockApi.call('tech.features_save', <String, dynamic>{'settings': settings});
    final List<Map<String, dynamic>> f = _list(r['features']);
    await _store(f);
    return f;
  }
}

/// نمایش child فقط وقتی پرچم روشن است (وگرنه هیچ — رفتار قبلی).
class TechGate extends StatelessWidget {
  const TechGate({super.key, required this.flag, required this.child});
  final String flag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, bool>>(
      future: TechFeatures.I.local(),
      builder: (BuildContext context, AsyncSnapshot<Map<String, bool>> _) => ValueListenableBuilder<Map<String, bool>>(
        valueListenable: TechFeatures.I.flags,
        builder: (BuildContext context, Map<String, bool> f, Widget? __) => (f[flag] ?? false) ? child : const SizedBox.shrink(),
      ),
    );
  }
}

class TechSettingsScreen extends StatefulWidget {
  const TechSettingsScreen({super.key});

  @override
  State<TechSettingsScreen> createState() => _TechSettingsScreenState();
}

class _TechSettingsScreenState extends State<TechSettingsScreen> {
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Map<String, dynamic>>? f = await TechFeatures.I.refresh();
    if (!mounted) return;
    setState(() {
      _offline = f == null;
      _rows = f ?? <Map<String, dynamic>>[];
      _loading = false;
    });
  }

  Future<void> _toggle(String key, bool on) async {
    try {
      final List<Map<String, dynamic>> f = await TechFeatures.I.save(<String, bool>{key: on});
      if (mounted) setState(() => _rows = f);
    } on StockApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool can = StaffPerms.I.can('settings.manage');
    return Scaffold(
      appBar: AppBar(title: const Text('قابلیت‌های هوشمند')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: <Widget>[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('هر قابلیت برای کل شرکت روشن یا خاموش می‌شود و پیش‌فرض خاموش است. با خاموش بودن، برنامه دقیقاً مثل قبل کار می‌کند.'),
                ),
              ),
              if (_offline) const ListTile(leading: Icon(Icons.cloud_off), title: Text('اتصال به سرور برقرار نشد؛ دوباره تلاش کنید.')),
              for (final Map<String, dynamic> r in _rows)
                SwitchListTile(
                  title: Text('${r['label'] ?? r['key']}'),
                  subtitle: Text('${r['help'] ?? ''}'),
                  value: r['on'] == true,
                  onChanged: can ? (bool v) => _toggle('${r['key']}', v) : null,
                ),
            ]),
    );
  }
}
