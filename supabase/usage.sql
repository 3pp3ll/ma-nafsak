-- مع نفسك: جدول تجميع الاستخدام للتجربة.
-- شغّله مرة وحدة في Supabase: SQL Editor ← New query ← الصق ← Run.
-- يتجمع لكل جهاز ولكل يوم: عدد فتحات الشاشات، الرسائل، ردود الذكاء الاصطناعي، الإنجازات، والتكلفة.
-- ما فيه أسماء ولا إيميلات ولا محتوى سوالف.

create table if not exists public.usage_daily (
  device       text        not null,
  day          date        not null,
  screens      jsonb       not null default '{}'::jsonb,
  msgs         int         not null default 0,
  ai           int         not null default 0,
  achievements int         not null default 0,
  cost         numeric     not null default 0,
  owner        boolean     not null default false,
  updated_at   timestamptz not null default now(),
  primary key (device, day)
);

alter table public.usage_daily enable row level security;

-- التطبيق يكتب ويقرأ بالمفتاح العام (anon). مناسب للتجربة لأن البيانات أرقام بدون هوية.
-- في نسخة Flutter نخلي القراءة لحساب الأدمن بس.
drop policy if exists "usage insert" on public.usage_daily;
drop policy if exists "usage update" on public.usage_daily;
drop policy if exists "usage read"   on public.usage_daily;
create policy "usage insert" on public.usage_daily for insert to anon with check (true);
create policy "usage update" on public.usage_daily for update to anon using (true) with check (true);
create policy "usage read"   on public.usage_daily for select to anon using (true);
