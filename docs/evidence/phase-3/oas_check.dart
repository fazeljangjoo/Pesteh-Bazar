// بررسی ساختاری OpenAPI 3.1 بدون ابزار بیرونی: YAML معتبر، همهٔ $refها resolve، operationId یکتا، پارامتر مسیر اعلام‌شده، توضیح پاسخ‌ها.
import 'dart:io';
import 'package:yaml/yaml.dart';

void main(List<String> a) {
  final doc = loadYaml(File(a[0]).readAsStringSync());
  final errs = <String>[];
  Object? ptr(String ref) {
    if (!ref.startsWith('#/')) { errs.add('external ref $ref'); return null; }
    Object? cur = doc;
    for (final seg in ref.substring(2).split('/')) {
      final k = seg.replaceAll('~1', '/').replaceAll('~0', '~');
      if (cur is YamlMap && cur.containsKey(k)) { cur = cur[k]; } else { errs.add('unresolved $ref'); return null; }
    }
    return cur;
  }
  int refs = 0;
  void walk(Object? n, String at) {
    if (n is YamlMap) {
      if (n.containsKey(r'$ref')) { refs++; ptr(n[r'$ref'] as String); }
      n.forEach((k, v) => walk(v, '$at/$k'));
    } else if (n is YamlList) {
      for (var i = 0; i < n.length; i++) { walk(n[i], '$at/$i'); }
    }
  }
  walk(doc, '');
  if (doc['openapi'] != '3.1.0') errs.add('openapi version');
  for (final k in ['title', 'version']) { if (doc['info']?[k] == null) errs.add('info.$k'); }
  final ids = <String>{};
  int ops = 0;
  void checkOps(YamlMap paths, String kind) {
    paths.forEach((p, item) {
      final params = RegExp(r'\{(\w+)\}').allMatches('$p').map((m) => m.group(1)).toSet();
      (item as YamlMap).forEach((method, op) {
        if (!['get', 'post', 'put', 'delete', 'patch'].contains(method)) return;
        ops++;
        final id = op['operationId'];
        if (id == null) errs.add('$p $method: no operationId');
        else if (!ids.add('$id')) errs.add('duplicate operationId $id');
        if (op['summary'] == null) errs.add('$p $method: no summary');
        final rs = op['responses'] as YamlMap?;
        if (rs == null || rs.isEmpty) errs.add('$p $method: no responses');
        rs?.forEach((c, r) {
          final rr = (r is YamlMap && r.containsKey(r'$ref')) ? ptr(r[r'$ref']) : r;
          if (rr is! YamlMap || rr['description'] == null) errs.add('$p $method $c: response description');
        });
        final declared = <String>{};
        for (final prm in (op['parameters'] as YamlList? ?? YamlList())) {
          final pp = (prm is YamlMap && prm.containsKey(r'$ref')) ? ptr(prm[r'$ref']) : prm;
          if (pp is YamlMap && pp['in'] == 'path') {
            declared.add('${pp['name']}');
            if (pp['required'] != true) errs.add('$p: path param not required');
          }
        }
        if (kind == 'paths' && declared.length != params.length) errs.add('$p $method: path params $params vs $declared');
        for (final s in (op['security'] as YamlList? ?? YamlList())) {
          for (final name in (s as YamlMap).keys) { if (doc['components']['securitySchemes'][name] == null) errs.add('unknown security $name'); }
        }
      });
    });
  }
  checkOps(doc['paths'] as YamlMap, 'paths');
  checkOps(doc['webhooks'] as YamlMap, 'webhooks');
  for (final s in (doc['security'] as YamlList)) {
    for (final name in (s as YamlMap).keys) { if (doc['components']['securitySchemes'][name] == null) errs.add('unknown global security $name'); }
  }
  // تطابق مسیرها با پیاده‌سازی
  final want = {'/lots', '/lots/{id}', '/stock', '/purchases', '/sales', '/workshop/operations', '/workshop/operations/{id}', '/costs/lots/{id}', '/webhooks', '/webhooks/{id}'};
  final got = (doc['paths'] as YamlMap).keys.map((e) => '$e').toSet();
  if (want.difference(got).isNotEmpty || got.difference(want).isNotEmpty) errs.add('paths mismatch ${want.difference(got)} ${got.difference(want)}');
  print('operations=$ops refs=$refs errors=${errs.length}');
  for (final e in errs) { print('  $e'); }
  exit(errs.isEmpty ? 0 : 1);
}
