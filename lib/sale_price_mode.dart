// v94 — «نحوهٔ قیمت‌گذاری» در فرم فروش، مثل فرم خرید: فروش با یک فی / فی پایه ۵۰ گرم / فروش گرمی.
// فقط کمک محاسبه است: فی کیلوییِ نهایی در همان فیلد «فی فروش» نوشته و مثل قبل ذخیره می‌شود (سرور و ستون‌ها بدون تغییر).
import 'package:flutter/material.dart';

import 'buy_mode_ui.dart';
import 'fmt.dart' show MoneyField;
import 'utils.dart' show faNum, parseNum;

const Map<BuyMode, String> kSaleModeLabels = kSellModeLabels; // v95: یکی با buy_mode_ui

/// فی کیلوییِ فروش از روش انتخاب‌شده (null = دادهٔ کافی نیست). همان فرمول خرید ([buyModeEffective])، گرد به عدد صحیح.
int? salePriceFromMode(BuyMode m, double? input, double? gram, {double ref = 50}) {
  final double? v = buyModeEffective(m, input, gram, ref);
  return v?.round();
}

class SalePriceModeCtl {
  BuyMode mode = BuyMode.fixed;
  final TextEditingController input = TextEditingController();
  final TextEditingController gram = TextEditingController();
  double ref = 50;
  int? _lotKey;

  /// گرم لات انتخاب‌شده (اگر ثبت شده) فقط یک بار برای هر لات پیش‌فرض می‌شود.
  void prefillGram(int? lotId, num? g) {
    if (lotId == _lotKey) return;
    _lotKey = lotId;
    if (g != null && g > 0) gram.text = faNum(g, dec: g == g.roundToDouble() ? 0 : 2);
  }

  double? get gramVal => parseNum(gram.text);
  double? get inputVal => MoneyField.stored(input)?.toDouble();
  int? get price => salePriceFromMode(mode, inputVal, gramVal, ref: ref);

  void dispose() {
    input.dispose();
    gram.dispose();
  }
}

/// تراشه‌های روش + (در حالت گرمی) فیلد فی پایه/گرمی و گرم. هر تغییر، فی کیلویی را در [price] می‌نویسد.
class SalePriceModeBox extends StatelessWidget {
  const SalePriceModeBox({super.key, required this.ctl, required this.price, required this.onChanged, this.gap = 12});
  final SalePriceModeCtl ctl;
  final TextEditingController price;
  final VoidCallback onChanged;
  final double gap;

  void _apply() {
    if (ctl.mode != BuyMode.fixed) {
      final int? p = ctl.price;
      if (p != null) MoneyField.setStored(price, p);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final BuyMode m = ctl.mode;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          const Text('نحوهٔ قیمت‌گذاری:', style: TextStyle(fontWeight: FontWeight.w600)),
          for (final BuyMode x in BuyMode.values)
            ChoiceChip(
              key: ValueKey<String>('saleMode_${x.name}'),
              label: Text(kSaleModeLabels[x]!),
              selected: m == x,
              onSelected: (bool on) {
                if (!on) return;
                ctl.mode = x;
                _apply();
              },
            ),
        ]),
      ),
      if (m != BuyMode.fixed) ...<Widget>[
        const SizedBox(height: 6),
        // v94: فی و گرم کنار هم (فشرده، مثل فرم خرید)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(
            flex: 3,
            child: Padding(padding: EdgeInsets.only(bottom: gap > 12 ? gap - 12 : 0), child: MoneyField( // اندروید: MoneyField پارامتر gap ندارد
                key: const ValueKey<String>('saleModeInput'),
                controller: ctl.input,
                label: m == BuyMode.perGram ? 'فی هر گرم' : 'فی پایه ${faNum(ctl.ref, dec: 0)} گرم',
                required: true,
                onChanged: _apply)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: TextFormField(
                key: const ValueKey<String>('saleModeGram'),
                controller: ctl.gram,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'گرم', border: OutlineInputBorder()),
                validator: (String? v) {
                  final double? g = parseNum(v ?? '');
                  return g == null || g <= 0 || g > 100 ? '۰ تا ۱۰۰' : null;
                },
                onChanged: (_) => _apply(),
              ),
            ),
          ),
        ]),
        buyModeInfo(context, m, input: ctl.inputVal, gram: ctl.gramVal, ref: ctl.ref),
        const SizedBox(height: 8),
      ],
    ]);
  }
}
