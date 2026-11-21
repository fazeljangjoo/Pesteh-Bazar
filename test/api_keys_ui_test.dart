// فاز ۳ — نشانی مستندات API از نشانی پایهٔ برنامه ساخته می‌شود (همان سروری که برنامه به آن وصل است).
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/api_keys_ui.dart';
import 'package:pesteh_bazar/license_service.dart' show ApiConfig;

void main() {
  test('docs url', () {
    expect(apiDocsUrl(), '${ApiConfig.baseUrl}/v1/api_docs.php');
    expect(apiDocsUrl().startsWith('https://'), isTrue);
  });
}
