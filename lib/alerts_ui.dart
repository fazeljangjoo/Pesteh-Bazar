// فاز ۲ «قابلیت‌های فناورانه» — هشدارها، آستانهٔ موجودی کم، مدیریت وب‌هوک و زنگ هشدار. پشت پرچم features.events (پیش‌فرض خاموش).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'live_events.dart';
import 'perms.dart' show StaffPerms;
import 'tech_features.dart';
import 'utils.dart' show jalaliDate, toFaDigits;
import 'warehouse_ui.dart' show StockApi, StockApiException;

void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

List<Map<String, dynamic>> _list(Object? v) =>
    v is List ? v.whereType<Map>().map((Map m) => Map<String, dynamic>.from(m)).toList() : <Map<String, dynamic>>[];

/// زنگ هشدارها با نشان تعداد خوانده‌نشده (فقط با پرچم روشن). ساختنش polling زنده را هم شروع می‌کند.
class LiveAlertsBell extends StatelessWidget {
  const LiveAlertsBell({super.key});

  @override
  Widget build(BuildContext context) {
    return TechGate(
      flag: 'events',
      child: Builder(builder: (BuildContext context) {
        unawaited(LiveEvents.I.ensureStarted());
        return ValueListenableBuilder<int>(
          valueListenable: LiveEvents.I.unread,
          builder: (BuildContext context, int n, Widget? _) => IconButton(
            tooltip: 'هشدارها',
            icon: Badge(isLabelVisible: n > 0, label: Text(toFaDigits('$n')), child: const Icon(Icons.campaign_outlined)),
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AlertsScreen())),
          ),
        );
      }),
    );
  }
}

/// ورودی منو با نشان (tech_menu.dart)
class AlertsMenuTile extends StatelessWidget {
  const AlertsMenuTile({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    unawaited(LiveEvents.I.ensureStarted());
    return ValueListenableBuilder<int>(
      valueListenable: LiveEvents.I.unread,
      builder: (BuildContext context, int n, Widget? _) => ListTile(
        leading: Badge(isLabelVisible: n > 0, label: Text(toFaDigits('$n')), child: const Icon(Icons.campaign_outlined)),
        title: const Text('هشدارها'),
        subtitle: const Text('موجودی کم، فروش زیر بها، ناهنجاری بازده', style: TextStyle(fontSize: 11.5)),
        onTap: onOpen,
      ),
    );
  }
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _resolved = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = LiveEvents.I.stream.where((Map<String, dynamic> e) => e['type'] == 'alert.raised').listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> r = await StockApi.call('alerts.list', <String, dynamic>{if (_resolved) 'include_resolved': 1});
      if (!mounted) return;
      setState(() {
        _items = _list(r['items']);
        _loading = false;
        _error = null;
      });
    } on StockApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _readAll() async {
    try {
      final Map<String, dynamic> r = await StockApi.call('alerts.read', <String, dynamic>{'all': true});
      LiveEvents.I.unread.value = (r['unread'] as num?)?.toInt() ?? 0;
      await _load();
    } on StockApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  Future<void> _read(Map<String, dynamic> it) async {
    if (it['read'] == true) return;
    try {
      final Map<String, dynamic> r = await StockApi.call('alerts.read', <String, dynamic>{'ids': <Object?>[it['id']]});
      LiveEvents.I.unread.value = (r['unread'] as num?)?.toInt() ?? LiveEvents.I.unread.value;
      await _load();
    } catch (_) {}
  }

  Future<void> _resolve(Map<String, dynamic> it) async {
    try {
      await StockApi.call('alerts.resolve', <String, dynamic>{'id': it['id']});
      await LiveEvents.I.refreshUnread();
      await _load();
    } on StockApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  Color _color(String level) => level == 'high' ? Colors.red : (level == 'warn' ? Colors.orange : Colors.blueGrey);

  @override
  Widget build(BuildContext context) {
    final bool admin = StaffPerms.I.can('settings.manage');
    return Scaffold(
      appBar: AppBar(title: const Text('هشدارها'), actions: <Widget>[
        IconButton(tooltip: 'همه خوانده شد', onPressed: _readAll, icon: const Icon(Icons.done_all)),
        if (admin)
          IconButton(
            tooltip: 'آستانهٔ موجودی کم',
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AlertSettingsScreen())),
            icon: const Icon(Icons.tune),
          ),
        IconButton(tooltip: 'به‌روزرسانی', onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: <Widget>[
        SwitchListTile(
          title: const Text('هشدارهای بسته‌شده هم'),
          value: _resolved,
          onChanged: (bool v) {
            setState(() => _resolved = v);
            _load();
          },
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                      ? const Center(child: Text('هشداری نیست'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (BuildContext context, int i) {
                            final Map<String, dynamic> it = _items[i];
                            final bool read = it['read'] == true;
                            final bool closed = it['resolved_at'] != null;
                            return Card(
                              child: ListTile(
                                onTap: () => _read(it),
                                leading: Icon(it['level'] == 'high' ? Icons.error_outline : Icons.warning_amber_outlined, color: _color('${it['level']}')),
                                title: Text('${it['title']}', style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.bold)),
                                subtitle: Text('${it['body'] ?? ''}\n${jalaliDate('${it['created_at'] ?? ''}'.split(' ').first)}${closed ? ' • بسته شد' : ''}'),
                                isThreeLine: true,
                                trailing: (!closed && admin) ? TextButton(onPressed: () => _resolve(it), child: const Text('بستن')) : null,
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

/// آستانهٔ موجودی کم برای هر نوع پسته (و اختیاری: دسته)
class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({super.key});

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _ThrRow {
  _ThrRow(String t, String kg, this.categoryId)
      : type = TextEditingController(text: t),
        kg = TextEditingController(text: kg);
  final TextEditingController type;
  final TextEditingController kg;
  final int? categoryId;
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  final List<_ThrRow> _rows = <_ThrRow>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> r = await StockApi.call('alerts.settings_get');
      _rows.clear();
      for (final Map<String, dynamic> x in _list(r['low_stock'])) {
        final double kg = (x['min_kg'] as num?)?.toDouble() ?? 0;
        _rows.add(_ThrRow('${x['type_name']}', kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : '$kg', (x['category_id'] as num?)?.toInt()));
      }
    } on StockApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final _ThrRow r in _rows) {
      final String t = r.type.text.trim();
      if (t.isEmpty && r.kg.text.trim().isEmpty) continue;
      final double? kg = double.tryParse(r.kg.text.trim().replaceAll(',', '').replaceAll('٫', '.'));
      if (t.isEmpty || kg == null || kg <= 0) {
        _snack(context, 'نوع پسته و حداقل موجودی (کیلو) هر ردیف را درست وارد کنید');
        return;
      }
      rows.add(<String, Object?>{'type_name': t, 'min_kg': kg, if (r.categoryId != null) 'category_id': r.categoryId});
    }
    setState(() => _saving = true);
    try {
      await StockApi.call('alerts.settings_save', <String, dynamic>{'low_stock': rows});
      if (mounted) {
        _snack(context, 'ذخیره شد');
        Navigator.pop(context);
      }
    } on StockApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('آستانهٔ موجودی کم')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: <Widget>[
              const Text('وقتی موجودی یک نوع پسته از این مقدار کمتر شود هشدار ساخته می‌شود و با بالا رفتن موجودی خودکار بسته می‌شود.'),
              const SizedBox(height: 8),
              for (final _ThrRow r in _rows)
                Row(children: <Widget>[
                  Expanded(flex: 3, child: TextField(controller: r.type, decoration: const InputDecoration(labelText: 'نوع پسته'))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextField(controller: r.kg, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'حداقل (کیلو)'))),
                  IconButton(onPressed: () => setState(() => _rows.remove(r)), icon: const Icon(Icons.remove_circle_outline), tooltip: 'حذف'),
                ]),
              TextButton.icon(onPressed: () => setState(() => _rows.add(_ThrRow('', '', null))), icon: const Icon(Icons.add), label: const Text('افزودن نوع')),
            ]),
    );
  }
}

/// مدیریت وب‌هوک (فقط settings.manage): افزودن، انتخاب رویدادها، ارسال آزمایشی، تاریخچهٔ ارسال
class WebhooksScreen extends StatefulWidget {
  const WebhooksScreen({super.key});

  @override
  State<WebhooksScreen> createState() => _WebhooksScreenState();
}

class _WebhooksScreenState extends State<WebhooksScreen> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _types = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> r = await StockApi.call('webhooks.list');
      if (!mounted) return;
      setState(() {
        _items = _list(r['items']);
        _types = _list(r['event_types']);
        _loading = false;
      });
    } on StockApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(context, e.message);
      }
    }
  }

  Future<void> _edit([Map<String, dynamic>? w]) async {
    final Map<String, dynamic>? saved = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _WebhookDialog(item: w, types: _types));
    if (saved == null) return;
    final Object? secret = (saved['item'] as Map?)?['secret'];
    if (secret is String && secret.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('کلید امضا'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('این کلید فقط همین یک بار نمایش داده می‌شود. آن را در سامانهٔ گیرنده برای بررسی سرآیند X-PB-Signature ذخیره کنید.'),
            const SizedBox(height: 8),
            SelectableText(secret, textDirection: TextDirection.ltr),
          ]),
          actions: <Widget>[
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: secret)), child: const Text('کپی')),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('ذخیره کردم')),
          ],
        ),
      );
    }
    await _load();
  }

  Future<void> _test(Map<String, dynamic> w) async {
    try {
      final Map<String, dynamic> r = await StockApi.call('webhooks.test', <String, dynamic>{'id': w['id']});
      if (mounted) _snack(context, r['ok'] == true ? 'ارسال آزمایشی موفق بود (کد ${r['http_code']})' : 'ارسال ناموفق: ${r['http_code'] ?? ''} ${r['response_excerpt'] ?? ''}');
    } on StockApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  Future<void> _delete(Map<String, dynamic> w) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        content: Text('وب‌هوک «${w['name'] ?? w['url']}» و تاریخچهٔ ارسالش حذف شود؟'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StockApi.call('webhooks.delete', <String, dynamic>{'id': w['id']});
      await _load();
    } on StockApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('وب‌هوک‌ها')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('افزودن')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 96), children: <Widget>[
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('با هر رویداد انتخاب‌شده، یک درخواست POST با بدنهٔ JSON به نشانی https شما فرستاده می‌شود. '
                      'سرآیند X-PB-Signature = sha256=HMAC(کلید، بدنه). در صورت شکست، بعد از ۱ و ۵ و ۳۰ دقیقه و ۲ و ۶ ساعت دوباره تلاش می‌شود.'),
                ),
              ),
              if (_items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('وب‌هوکی تعریف نشده است'))),
              for (final Map<String, dynamic> w in _items)
                Card(
                  child: ListTile(
                    leading: Icon(w['active'] == true ? Icons.webhook : Icons.pause_circle_outline, color: w['active'] == true ? Colors.green : Colors.grey),
                    title: Text('${w['name'] ?? w['url']}'),
                    subtitle: Text('${w['url']}\n${(w['event_types'] as List?)?.join('، ') ?? ''}'
                        '${(w['fail_count'] as num? ?? 0) > 0 ? '\nشکست پیاپی: ${toFaDigits('${w['fail_count']}')}' : ''}'),
                    isThreeLine: true,
                    onTap: () => _edit(w),
                    trailing: PopupMenuButton<String>(
                      onSelected: (String v) {
                        if (v == 'test') _test(w);
                        if (v == 'log') Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _DeliveriesScreen(webhook: w)));
                        if (v == 'delete') _delete(w);
                      },
                      itemBuilder: (_) => const <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(value: 'test', child: Text('ارسال آزمایشی')),
                        PopupMenuItem<String>(value: 'log', child: Text('تاریخچهٔ ارسال')),
                        PopupMenuItem<String>(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                ),
            ]),
    );
  }
}

class _WebhookDialog extends StatefulWidget {
  const _WebhookDialog({this.item, required this.types});
  final Map<String, dynamic>? item;
  final List<Map<String, dynamic>> types;

  @override
  State<_WebhookDialog> createState() => _WebhookDialogState();
}

class _WebhookDialogState extends State<_WebhookDialog> {
  late final TextEditingController _name = TextEditingController(text: '${widget.item?['name'] ?? ''}');
  late final TextEditingController _url = TextEditingController(text: '${widget.item?['url'] ?? 'https://'}');
  late final Set<String> _sel = <String>{...((widget.item?['event_types'] as List?)?.map((Object? e) => '$e') ?? const <String>[])};
  late bool _active = widget.item?['active'] != false;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> r = await StockApi.call('webhooks.save', <String, dynamic>{
        if (widget.item != null) 'id': widget.item!['id'],
        'name': _name.text.trim(),
        'url': _url.text.trim(),
        'event_types': _sel.toList(),
        'active': _active,
      });
      if (mounted) Navigator.pop(context, r);
    } on StockApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'وب‌هوک جدید' : 'ویرایش وب‌هوک'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام (اختیاری)')),
            TextField(controller: _url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'نشانی (فقط https)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('فعال'), value: _active, onChanged: (bool v) => setState(() => _active = v)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('همهٔ رویدادها'),
              value: _sel.contains('*'),
              onChanged: (bool? v) => setState(() => v == true ? _sel.add('*') : _sel.remove('*')),
            ),
            if (!_sel.contains('*'))
              for (final Map<String, dynamic> t in widget.types)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${t['label']}'),
                  subtitle: Text('${t['key']}', textDirection: TextDirection.ltr),
                  value: _sel.contains('${t['key']}'),
                  onChanged: (bool? v) => setState(() => v == true ? _sel.add('${t['key']}') : _sel.remove('${t['key']}')),
                ),
          ]),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _saving || _sel.isEmpty ? null : _save, child: Text(_saving ? '…' : 'ذخیره')),
      ],
    );
  }
}

class _DeliveriesScreen extends StatefulWidget {
  const _DeliveriesScreen({required this.webhook});
  final Map<String, dynamic> webhook;

  @override
  State<_DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<_DeliveriesScreen> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;

  static const Map<String, String> _st = <String, String>{'ok': 'موفق', 'retry': 'تلاش دوباره', 'pending': 'در صف', 'failed': 'ناموفق'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> r = await StockApi.call('webhooks.deliveries', <String, dynamic>{'id': widget.webhook['id']});
      if (mounted) {
        setState(() {
          _items = _list(r['items']);
          _loading = false;
        });
      }
    } on StockApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('تاریخچهٔ ارسال — ${widget.webhook['name'] ?? ''}'), actions: <Widget>[IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('ارسالی ثبت نشده است'))
              : ListView(children: <Widget>[
                  for (final Map<String, dynamic> d in _items)
                    ListTile(
                      dense: true,
                      leading: Icon(d['status'] == 'ok' ? Icons.check_circle_outline : (d['status'] == 'failed' ? Icons.error_outline : Icons.schedule),
                          color: d['status'] == 'ok' ? Colors.green : (d['status'] == 'failed' ? Colors.red : Colors.orange)),
                      title: Text('${d['event_type'] ?? ''} — ${_st['${d['status']}'] ?? d['status']}', textDirection: TextDirection.rtl),
                      subtitle: Text('کد ${d['http_code'] ?? '—'} • تلاش ${toFaDigits('${d['attempt']}')} • ${d['created_at'] ?? ''}'
                          '${'${d['response_excerpt'] ?? ''}'.isEmpty ? '' : '\n${d['response_excerpt']}'}'),
                    ),
                ]),
    );
  }
}
