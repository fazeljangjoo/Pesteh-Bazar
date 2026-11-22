# International Marketing Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the «بازاریابی بین‌المللی» section: lead cards with stages, follow-ups, per-customer sales with manager confirmation, monthly targets, scoring, and a chart dashboard for manager and owner.

**Architecture:** Four new generic entities (`mk_leads`, `mk_activities`, `mk_sales`, `mk_targets`) on the existing entity framework (offline, uid, rev, row_filter, sync). Plus one settings row (`mk_settings`) and one server action, `marketing.report`, that aggregates over the `ent_mk_*` tables. Flutter screens live in new `marketing_*.dart` files. Existing files are touched only to register the menu item, the access section, roles and the entity registry.

**Tech Stack:** PHP 8 / MySQL (server), Flutter (Android + Windows), sqflite, `fl_chart` (new dependency).

**Spec:** `docs/superpowers/specs/2026-11-21-intl-marketing-design.md`

## Global Constraints
- Every Dart change goes to BOTH `wt/android-v87` and `wt/gold-v87`. The server lives in `server/public_html/backend/api`. Branch: `v-6`.
- Preserve each file's line endings (patch scripts in the scratchpad, never `/tmp`).
- Entity gate is `['tier' => 'green', 'plan' => 'any']`.
- Permissions: `marketing.entry`, `marketing.manage`, `marketing.reports`, price key `price.marketing`.
- Stages: `lead`, `contacted`, `negotiation`, `proforma`, `won`, `lost`.
- Score weights default to: lead 5, negotiation 15, proforma 30, sale 70, ton 7, collection 100. Final score: no sales ⇒ 0.4 × total; otherwise total − 50 × sales.
- Default targets: follow-ups 100, new leads 50, proforma 1, sales 15, tons 25.
- Sales and collections count only when `status = confirmed`.
- Dates are Jalali. Weeks run Saturday to Friday.
- A marketer may back-date a follow-up by at most 7 days.
- Do not change purchases, sales, stock, accounting or workshop code.

## Review Focus
- A marketer must never receive another marketer's lead, activity or sale, either through `entity.changes` or through the full `sync.export`. Both paths use `row_filter`; there is a test per entity.
- After a lead is handed to another marketer, the previous owner's device hides it. `row_filter` includes `prev_owner_staff_id`, and the client hides leads whose owner is someone else.
- A marketer cannot confirm their own sale, and cannot edit or delete a confirmed one. Enforced in `before_save` / `before_delete`.
- Empty periods (no data yet) must render as zeros or «—», never a crash or a division by zero. The report and the score function get zero cases.
- Owner (`_staff_id = 0`) sees everything; the report works with no staff and no targets.

---

### Task 1: Server entities, access, roles
**Files:** Create `marketing.php`. Modify `entities.php` (registry merge), `access_catalog.php` (section), `permissions.php` (catalog keys, action perms, system roles), `app.php` (require plus action dispatch).
- Entities, as in the spec's data section. Lead columns:
  - `name`, `contact`, `country` (2 chars), `city`, `phone`, `email`
  - `source` (enum: expo, website, linkedin, b2b, referral, cold, social, other)
  - `products` (string), `est_tons` (decimal), `stage` (enum), `lost_reason` (enum: price, quality, competitor, no_reply, payment, shipping, other)
  - `owner_staff_id`, `owner_name`, `prev_owner_staff_id`
  - `next_followup_at` (datetime), `stage_at` (datetime), `note`
- Activities: `lead_uid` (ref), `staff_id`, `staff_name`, `at` (datetime), `kind` (enum: call, message, email, meeting, sample, proforma, note, stage), `from_stage`, `to_stage`, `result`.
- Sales: `lead_uid`, `staff_id`, `staff_name`, `date`, `tons`, `amount`, `ccy`, `product`, `collected` (bool), `collected_at` (date), `status` (pending, confirmed, rejected), `confirmed_by`, `confirmed_at`.
- Targets: `staff_id`, `month` (`"1405-08"`), `follow_ups`, `new_leads`, `negotiations`, `proformas`, `sales`, `tons`.
- Settings: `mk_settings` with the weights and final-score factors, `stale_days` 14, and stage probabilities (lead 5, contacted 10, negotiation 30, proforma 60).
- Hooks:
  - `before_save` stamps owner and staff on new rows.
  - A non-manager may only touch their own rows and may not set `status`.
  - A sale changed by a non-manager goes back to `pending`.
  - Confirmed sales are locked for non-managers.
  - Back-dating more than 7 days is rejected for non-managers.
  - An owner change sets `prev_owner_staff_id`.
- `row_filter`:
  - Leads: `owner_staff_id = ? OR prev_owner_staff_id = ?`.
  - Activities and sales: `staff_id = ? OR lead_uid IN (own leads)`.
  - Targets: `staff_id = ?`.
  - Settings: no filter.
  - Each returns `null` for `marketing.manage` and for the owner.
- Self-test `marketing_selftest.php` (pure functions only).

### Task 2: Score + metrics pure functions (PHP + Dart mirror)
**Files:** `marketing_calc.php`, `lib/marketing_calc.dart` (both apps), `marketing_cases.json` (server and `test/` of both apps), `test/marketing_calc_test.dart`.
- `pb_mk_score(array $m, array $w): array` and `mkScore(MkCounts m, MkWeights w) → MkScore`.
  - Inputs: `new_leads`, `negotiations`, `proformas`, `sales`, `tons`, `collections`.
  - Output: per-item points, `total`, `final`.
- `pb_mk_rate(a, b)` returns `null` when `b = 0`.
- Cases:
  - Nooshin, Ordibehesht: `{11, 64, 1, 1, 20, 1}` ⇒ total 1355, final 1305.
  - Alireza: `{31, 119, 0, 0, 0, 0}` ⇒ total 1940, final 776.
  - All zeros ⇒ 0 / 0.

### Task 3: `marketing.report` action
**Files:** `marketing.php`.
- Payload: `{from, to, staff_id?, country?, source?}` with Gregorian dates; the client converts from Jalali.
- Returns:
  - `kpis`: counts for the period and the previous period of equal length, plus the target for the period (scaled by days)
  - `funnel`
  - `trend[]`: daily when the range is 45 days or less, else weekly when 200 days or less, else monthly
  - `board[]`: per marketer counts, score and target progress
  - `countries[]`, `sources[]`, `lost_reasons[]`
  - `aging`: average days per stage
  - `stale[]`, `overdue[]`
  - `heatmap`: staff × day follow-up counts
  - `forecast_tons`
  - `pending_sales`
- A non-manager without reports access gets only their own numbers, plus `rank` and `team_size`.
- Money fields are masked without `price.marketing`.

### Task 4: Flutter data layer
**Files:** `lib/marketing_store.dart` (wraps `EntityStore` for the `mk_*` entities, offline personal counts), `entity_store.dart` (registry entries, `kEntityRegistryVersion` +1), `company_profile.dart` (`kHiddenEntityMenu` += `mk_*`).

### Task 5: Entry UI
**Files:** `lib/marketing_leads_ui.dart`
- Leads list with search and stage, country and owner filters.
- Kanban on wide screens.
- Lead card: details, history and «پیگیری تازه» bottom sheet; sales list with add/confirm.
- «امروز من».

### Task 6: Manager UI
**Files:** `lib/marketing_admin_ui.dart`
- Targets grid (staff × month).
- Weights settings.
- Pending-sales confirmation list.
- Lead hand-off.

### Task 7: Dashboard
**Files:** `lib/marketing_dashboard_ui.dart`, `pubspec.yaml` (`fl_chart`)
- Charts per spec items 1–11.
- Period and filter bar.
- Excel/PDF export through the existing `excel_io` / `pdf_service`.

### Task 8: Wiring
**Files:** `main.dart` (menu item gated by `canAny([...marketing])`), `access_catalog.dart` (section mirror), `perms.dart` (labels).
- The section home: dashboard for the owner and for reports/manage users, «امروز من» for the others.

### Task 9: Verification
- `php -l` on all files.
- Run the selftest.
- `flutter analyze` and `flutter test` in both apps.
