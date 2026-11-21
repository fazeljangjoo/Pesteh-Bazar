# شواهد فاز ۳ — API باز (REST v1) و کلید API

- `verification_summary.txt`: آزمون‌ها و تحلیل هر دو برنامه، `php -l`، selftestها و مقایسهٔ عکس‌برداری پایان فاز ۳.
- `api_selftest_output.json`: ۵۰ بررسی روی همان کد مسیریاب REST (sqlite؛ داده ساختگی):
  - کلید لغوشده ⇒ 401؛ scope ناکافی ⇒ 403؛ پرچم خاموش ⇒ 403؛ اشتراک غیرفعال ⇒ 403.
  - دادهٔ مستأجر دیگر برنمی‌گردد (لات، فروش، کارگاه، بها)؛ قیمت فقط با costs:read.
  - صفحه‌بندی cursor؛ ۶۱امین درخواست در دقیقه ⇒ 429 با Retry-After؛ کلید فقط به‌صورت هش ذخیره می‌شود.
- `openapi_structural_check.txt` + `oas_check.dart`: بررسی ساختاری `openapi.yaml` با بستهٔ yaml دارت:
  - YAML معتبر؛ ۱۲ عملیات؛ ۸۶ ارجاع `$ref` همه resolve؛ operationId یکتا؛ پارامترهای مسیر اعلام‌شده؛ تطابق مسیرها با پیاده‌سازی.
- **linter رسمی (`npx @redocly/cli lint`) اجرا نشد:** دریافت بسته از npm در این جلسه مجاز نشد. دستور برای اجرا:
  `npx @redocly/cli@1.34.3 lint server/public_html/backend/api/v1/openapi.yaml`
- **معیار پذیرش «یک کلید با scope محدود فقط دادهٔ مجاز را می‌بیند»:** در selftest بررسی شد. روی سرور واقعی با `curl -H "Authorization: Bearer <کلید>" https://pesteh-bazar.ir/backend/api/v1/lots` هم بررسی کنید.
- **تصویر صفحه:** گرفته نشد (برنامه به سرور وصل نبود).
