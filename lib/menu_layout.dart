import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'edition.dart' show FeatureGate;
import 'perms.dart';
import 'warehouse_ui.dart' show StockApi;

// v91 — منوی کناری قابل تنظیم برای هر کاربر: پین کردن گزینه‌ها به بالای منو (با ترتیب دلخواه) و بردن گزینه‌های کم‌کاربرد
// به پوشهٔ «سایر». فقط ظاهر است: گزینه‌هایی که کاربر دسترسی‌اش را ندارد اصلاً ساخته نمی‌شوند و با تنظیم هم ظاهر نمی‌شوند.
// شناسهٔ هر گزینه = عنوان فارسی‌اش (ListTile.title). تنظیم هر کاربر (مالک یا هر کارمند) جداست: روی دستگاه ذخیره می‌شود و
// از سرور (ui_prefs.get / ui_prefs.put) روی همهٔ دستگاه‌های همان کاربر یکی می‌شود.

class MenuLayout {
  final List<String> pinned; // ترتیب = ترتیب نمایش بالای منو
  final Set<String> other; // داخل پوشهٔ «سایر»
  const MenuLayout({this.pinned = const <String>[], this.other = const <String>{}});

  bool get isEmpty => pinned.isEmpty && other.isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{'v': 1, 'pinned': pinned, 'other': other.toList()};

  static MenuLayout fromJson(Object? j) {
    if (j is! Map) return const MenuLayout();
    List<String> list(Object? x) => x is List ? <String>[for (final Object? e in x) if (e is String && e.trim().isNotEmpty) e] : <String>[];
    final List<String> p = list(j['pinned']);
    final Set<String> o = list(j['other']).toSet()..removeAll(p);
    return MenuLayout(pinned: p.toSet().toList(), other: o);
  }

  MenuLayout copyWith({List<String>? pinned, Set<String>? other}) => MenuLayout(pinned: pinned ?? this.pinned, other: other ?? this.other);
}

class MenuLayoutStore {
  MenuLayoutStore._();
  static final MenuLayoutStore I = MenuLayoutStore._();

  final ValueNotifier<MenuLayout> layout = ValueNotifier<MenuLayout>(const MenuLayout());
  String? _loadedFor;

  String get _who {
    final Map<String, dynamic>? s = StaffPerms.I.current.value;
    return s == null ? 'owner' : 'staff_${s['id'] ?? s['username'] ?? '?'}';
  }

  String get _prefKey => 'menu_layout.$_who';

  /// یک بار برای هر کاربر: اول نسخهٔ روی دستگاه (فوری)، بعد نسخهٔ سرور (اگر اینترنت هست).
  Future<void> ensureLoaded() async {
    final String who = _who;
    if (_loadedFor == who) return;
    _loadedFor = who;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String? raw = sp.getString(_prefKey);
      layout.value = raw == null ? const MenuLayout() : MenuLayout.fromJson(jsonDecode(raw));
    } catch (_) {
      layout.value = const MenuLayout();
    }
    try {
      final Map<String, dynamic> r = await StockApi.call('ui_prefs.get', <String, dynamic>{'key': 'menu_layout'});
      final Object? v = r['value'];
      if (v is String && v.isNotEmpty && _loadedFor == who) {
        final MenuLayout srv = MenuLayout.fromJson(jsonDecode(v));
        layout.value = srv;
        final SharedPreferences sp = await SharedPreferences.getInstance();
        await sp.setString(_prefKey, jsonEncode(srv.toJson()));
      }
    } catch (_) {
      // آفلاین یا سرور قدیمی: همان نسخهٔ دستگاه
    }
  }

  Future<void> save(MenuLayout l) async {
    layout.value = l;
    final String json = jsonEncode(l.toJson());
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      await sp.setString(_prefKey, json);
    } catch (_) {}
    try {
      await StockApi.call('ui_prefs.put', <String, dynamic>{'key': 'menu_layout', 'value': json});
    } catch (_) {
      // آفلاین: دفعهٔ بعد که ذخیره شود به سرور هم می‌رسد
    }
  }
}

/// عنوان یک گزینهٔ منو (ListTile مستقیم یا داخل FeatureGate)؛ null = قابل تنظیم نیست (سرتیتر، جداکننده، فهرست پویا…).
String? menuItemKey(Widget w) {
  Widget x = w;
  if (x is FeatureGate) x = x.child;
  if (x is ListTile && x.title is Text) {
    final String? t = (x.title as Text).data;
    if (t == null || t.trim().isEmpty || kMenuFixedKeys.contains(t)) return null;
    return t;
  }
  return null;
}

/// گزینه‌هایی که همیشه سر جایشان (پایین منو) می‌مانند.
const Set<String> kMenuFixedKeys = <String>{'خروج از حساب', 'اشتراک من', 'ویرایش منو'};

/// چیدمان نهایی: [پین‌شده‌ها] ← بقیه به ترتیب پیش‌فرض ← پوشهٔ «سایر» ← «ویرایش منو».
/// [children] همان فهرست پیش‌فرض منو است که قبلاً با مجوزها فیلتر شده.
List<Widget> arrangeMenu(BuildContext context, List<Widget> children, MenuLayout l, {required VoidCallback onEdit}) {
  final Map<String, Widget> keyed = <String, Widget>{};
  for (final Widget w in children) {
    final String? k = menuItemKey(w);
    if (k != null) keyed.putIfAbsent(k, () => w);
  }
  final List<Widget> pinned = <Widget>[for (final String k in l.pinned) if (keyed[k] != null) keyed[k]!];
  final List<Widget> other = <Widget>[
    for (final MapEntry<String, Widget> e in keyed.entries)
      if (l.other.contains(e.key) && !l.pinned.contains(e.key)) e.value,
  ];
  final List<Widget> rest = <Widget>[
    for (final Widget w in children)
      if (!(menuItemKey(w) != null && (l.pinned.contains(menuItemKey(w)) || l.other.contains(menuItemKey(w))))) w,
  ];
  // آخرین بخش منو (جداکننده + خروج/اشتراک) زیر «سایر» و «ویرایش منو» می‌ماند
  int tail = rest.length;
  for (int i = rest.length - 1; i >= 0; i--) {
    final Widget w = rest[i];
    if (w is Divider) {
      tail = i;
      break;
    }
    if (w is ListTile && w.title is Text && kMenuFixedKeys.contains((w.title as Text).data)) continue;
    break;
  }
  // سرتیتر بالای منو (نام برنامه، نسخه، نام کاربر در گوشی) بالای پین‌شده‌ها می‌ماند
  int head = 0;
  while (head < tail && menuItemKey(rest[head]) == null && rest[head] is! ListTile && rest[head] is! FeatureGate) {
    head++;
  }
  final Color hint = Theme.of(context).hintColor;
  return <Widget>[
    ...rest.sublist(0, head),
    if (pinned.isNotEmpty) ...<Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
        child: Row(children: <Widget>[
          Icon(Icons.push_pin, size: 14, color: hint),
          const SizedBox(width: 6),
          Text('پین‌شده', style: TextStyle(fontSize: 12, color: hint)),
        ]),
      ),
      ...pinned,
      const Divider(height: 1),
    ],
    ...rest.sublist(head, tail),
    if (other.isNotEmpty)
      ExpansionTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text('سایر (${other.length})'),
        childrenPadding: const EdgeInsetsDirectional.only(start: 8),
        children: other,
      ),
    ListTile(
      leading: const Icon(Icons.edit_note_outlined),
      title: const Text('ویرایش منو'),
      subtitle: const Text('پین کردن و پوشهٔ «سایر»', style: TextStyle(fontSize: 11.5)),
      onTap: onEdit,
    ),
    ...rest.sublist(tail),
  ];
}

/// صفحهٔ «ویرایش منو»: پین/برداشتن پین، بردن به «سایر»/برگرداندن، و ترتیب پین‌شده‌ها با کشیدن.
class MenuEditScreen extends StatefulWidget {
  /// گزینه‌هایی که همین کاربر می‌بیند: (عنوان، آیکون)
  final List<(String, Widget?)> items;
  const MenuEditScreen({super.key, required this.items});
  @override
  State<MenuEditScreen> createState() => _MenuEditScreenState();
}

class _MenuEditScreenState extends State<MenuEditScreen> {
  late List<String> _pinned;
  late Set<String> _other;

  @override
  void initState() {
    super.initState();
    final MenuLayout l = MenuLayoutStore.I.layout.value;
    final Set<String> have = widget.items.map(((String, Widget?) e) => e.$1).toSet();
    _pinned = l.pinned.where(have.contains).toList(); // گزینه‌ای که دیگر دسترسی‌اش نیست از ویرایشگر حذف می‌شود (در تنظیم می‌ماند)
    _other = l.other.where(have.contains).toSet();
  }

  Widget? _icon(String k) => widget.items.firstWhere(((String, Widget?) e) => e.$1 == k, orElse: () => (k, null)).$2;

  Future<void> _save() async {
    final MenuLayout old = MenuLayoutStore.I.layout.value;
    final Set<String> have = widget.items.map(((String, Widget?) e) => e.$1).toSet();
    // گزینه‌هایی که این کاربر الان نمی‌بیند (مثلاً قابلیت خاموش) تنظیم قبلی‌شان را نگه می‌دارند
    final List<String> pinned = <String>[..._pinned, ...old.pinned.where((String k) => !have.contains(k))];
    final Set<String> other = <String>{..._other, ...old.other.where((String k) => !have.contains(k))};
    await MenuLayoutStore.I.save(MenuLayout(pinned: pinned, other: other));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ویرایش منو'),
        actions: <Widget>[
          TextButton(
            onPressed: () => setState(() {
              _pinned = <String>[];
              _other = <String>{};
            }),
            child: const Text('پیش‌فرض'),
          ),
          const SizedBox(width: 4),
          FilledButton(onPressed: _save, child: const Text('ذخیره')),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CustomScrollView(slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('پین‌شده‌ها بالای منو می‌آیند؛ برای تغییر ترتیب، ردیف را با ⠿ بکشید.', style: TextStyle(color: th.hintColor)),
              ),
            ),
            if (_pinned.isEmpty)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(16), child: Text('هنوز گزینه‌ای پین نشده است.')))
            else
              SliverReorderableList(
                itemCount: _pinned.length,
                onReorder: (int a, int b) => setState(() {
                  if (b > a) b--;
                  _pinned.insert(b, _pinned.removeAt(a));
                }),
                itemBuilder: (BuildContext c, int i) {
                  final String k = _pinned[i];
                  return Material(
                    key: ValueKey<String>('p:$k'),
                    child: ListTile(
                      leading: _icon(k),
                      title: Text(k),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                        IconButton(tooltip: 'برداشتن پین', icon: const Icon(Icons.push_pin), onPressed: () => setState(() => _pinned.remove(k))),
                        ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator))),
                      ]),
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: Divider()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text('همهٔ گزینه‌ها: 📌 پین · 📁 بردن به پوشهٔ «سایر»', style: TextStyle(color: th.hintColor)),
              ),
            ),
            SliverList.builder(
              itemCount: widget.items.length,
              itemBuilder: (BuildContext c, int i) {
                final (String k, Widget? ic) = widget.items[i];
                final bool pin = _pinned.contains(k);
                final bool oth = _other.contains(k);
                return ListTile(
                  leading: ic,
                  title: Text(k),
                  subtitle: oth ? const Text('در پوشهٔ «سایر»', style: TextStyle(fontSize: 11.5)) : null,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    IconButton(
                      tooltip: pin ? 'برداشتن پین' : 'پین به بالای منو',
                      icon: Icon(pin ? Icons.push_pin : Icons.push_pin_outlined, color: pin ? th.colorScheme.primary : null),
                      onPressed: () => setState(() {
                        if (pin) {
                          _pinned.remove(k);
                        } else {
                          _pinned.add(k);
                          _other.remove(k);
                        }
                      }),
                    ),
                    IconButton(
                      tooltip: oth ? 'برگرداندن از «سایر»' : 'بردن به «سایر»',
                      icon: Icon(oth ? Icons.folder : Icons.folder_outlined, color: oth ? th.colorScheme.primary : null),
                      onPressed: () => setState(() {
                        if (oth) {
                          _other.remove(k);
                        } else {
                          _other.add(k);
                          _pinned.remove(k);
                        }
                      }),
                    ),
                  ]),
                );
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// (عنوان، آیکون) گزینه‌های قابل تنظیمِ فهرست منو برای صفحهٔ ویرایش.
List<(String, Widget?)> menuEditableItems(List<Widget> children) {
  final List<(String, Widget?)> o = <(String, Widget?)>[];
  final Set<String> seen = <String>{};
  for (final Widget w in children) {
    final String? k = menuItemKey(w);
    if (k == null || !seen.add(k)) continue;
    Widget x = w;
    if (x is FeatureGate) x = x.child;
    o.add((k, x is ListTile ? x.leading : null));
  }
  return o;
}
