// فاز ۳ «قابلیت‌های فناورانه» — مدیریت کلید API (فقط settings.manage): ساخت (نام + scope)، نمایش یک‌بارهٔ کلید، لغو، آخرین استفاده.
// پشت پرچم features.api (پیش‌فرض خاموش). مستندات: https://<host>/backend/api/v1/api_docs.php
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'license_service.dart' show ApiConfig;
import 'utils.dart' show jalaliDate;
import 'warehouse_ui.dart' show StockApi, StockApiException;

List<Map<String, dynamic>> _list(Object? v) =>
    v is List ? v.whereType<Map>().map((Map m) => Map<String, dynamic>.from(m)).toList() : <Map<String, dynamic>>[];

/// نشانی مستندات (از نشانی پایهٔ API برنامه)
String apiDocsUrl() => '${ApiConfig.baseUrl}/v1/api_docs.php';

class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _scopes = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> r = await StockApi.call('api_keys.list');
      if (!mounted) return;
      setState(() {
        _items = _list(r['items']);
        _scopes = _list(r['scopes']);
        _loading = false;
        _error = null;
      });
    } on StockApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _create() async {
    final Map<String, dynamic>? r = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _CreateKeyDialog(scopes: _scopes));
    if (r == null || !mounted) return;
    final String key = '${r['key'] ?? ''}';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('کلید API ساخته شد'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Text('این کلید فقط همین یک بار نمایش داده می‌شود و بعداً قابل دیدن نیست. آن را جای امنی ذخیره کنید.'),
          const SizedBox(height: 8),
          SelectableText(key, textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Text('سرآیند درخواست: Authorization: Bearer <کلید>', textDirection: TextDirection.rtl, style: Theme.of(ctx).textTheme.bodySmall),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: key)), child: const Text('کپی')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('ذخیره کردم')),
        ],
      ),
    );
    await _load();
  }

  Future<void> _revoke(Map<String, dynamic> k) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        content: Text('کلید «${k['name']}» لغو شود؟ برنامه‌هایی که از آن استفاده می‌کنند دیگر دسترسی نخواهند داشت. این کار برگشت‌پذیر نیست.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('لغو کلید')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StockApi.call('api_keys.revoke', <String, dynamic>{'id': k['id']});
      await _load();
    } on StockApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _scopeLabel(String s) => '${_scopes.firstWhere((Map<String, dynamic> x) => x['key'] == s, orElse: () => <String, dynamic>{'label': s})['label']}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('کلیدهای API')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _loading ? null : _create, icon: const Icon(Icons.add), label: const Text('کلید جدید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 96), children: <Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        const Text('با کلید API، نرم‌افزارهای دیگر (حسابداری، داشبورد، سامانهٔ خریدار) می‌توانند دادهٔ شرکت را فقط بخوانند. '
                            'هر کلید فقط مجوزهای انتخاب‌شده را دارد؛ قیمت و بها فقط با مجوز «دیدن قیمت و بها». حداکثر ۶۰ درخواست در دقیقه.'),
                        const SizedBox(height: 6),
                        Row(children: <Widget>[
                          const Text('مستندات: '),
                          Expanded(child: SelectableText(apiDocsUrl(), textDirection: TextDirection.ltr)),
                          IconButton(tooltip: 'کپی نشانی', onPressed: () => Clipboard.setData(ClipboardData(text: apiDocsUrl())), icon: const Icon(Icons.copy, size: 18)),
                        ]),
                      ]),
                    ),
                  ),
                  if (_items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('کلیدی ساخته نشده است'))),
                  for (final Map<String, dynamic> k in _items)
                    Card(
                      child: ListTile(
                        leading: Icon(k['revoked_at'] == null ? Icons.vpn_key_outlined : Icons.block, color: k['revoked_at'] == null ? Colors.green : Colors.grey),
                        title: Text('${k['name']}  (pb_${k['prefix']}_…)', textDirection: TextDirection.rtl),
                        subtitle: Text([
                          ((k['scopes'] as List?) ?? <Object?>[]).map((Object? s) => _scopeLabel('$s')).join('، '),
                          'ساخت: ${jalaliDate('${k['created_at'] ?? ''}'.split(' ').first)}'
                              '  •  آخرین استفاده: ${k['last_used_at'] == null ? 'هرگز' : jalaliDate('${k['last_used_at']}'.split(' ').first)}',
                          if (k['revoked_at'] != null) 'لغو شده: ${jalaliDate('${k['revoked_at']}'.split(' ').first)}',
                        ].join('\n')),
                        isThreeLine: true,
                        trailing: k['revoked_at'] == null ? TextButton(onPressed: () => _revoke(k), child: const Text('لغو')) : null,
                      ),
                    ),
                ]),
    );
  }
}

class _CreateKeyDialog extends StatefulWidget {
  const _CreateKeyDialog({required this.scopes});
  final List<Map<String, dynamic>> scopes;

  @override
  State<_CreateKeyDialog> createState() => _CreateKeyDialogState();
}

class _CreateKeyDialogState extends State<_CreateKeyDialog> {
  final TextEditingController _name = TextEditingController();
  final Set<String> _sel = <String>{'lots:read', 'stock:read'};
  bool _saving = false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نام کلید را وارد کنید')));
      return;
    }
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> r = await StockApi.call('api_keys.create', <String, dynamic>{'name': _name.text.trim(), 'scopes': _sel.toList()});
      if (mounted) Navigator.pop(context, r);
    } on StockApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('کلید API جدید'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(controller: _name, maxLength: 100, decoration: const InputDecoration(labelText: 'نام (مثلاً «نرم‌افزار حسابداری»)')),
            for (final Map<String, dynamic> s in widget.scopes)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${s['label']}'),
                subtitle: Text('${s['key']}', textDirection: TextDirection.ltr),
                value: _sel.contains('${s['key']}'),
                onChanged: (bool? v) => setState(() => v == true ? _sel.add('${s['key']}') : _sel.remove('${s['key']}')),
              ),
          ]),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _saving || _sel.isEmpty ? null : _save, child: Text(_saving ? '…' : 'ساخت کلید')),
      ],
    );
  }
}
