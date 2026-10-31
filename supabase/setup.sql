-- «مع نفسك» — إعداد Supabase
-- آمن للتشغيل داخل مشروع مشترك (مثل مشروع عقود): كل الجداول والدوال تبدأ بـ mn_
-- وما يلمس أي جدول أو دالة أو trigger تابع لتطبيق ثاني.
-- يتشغل أكثر من مرة بدون مشاكل.

-- 1) أصحاب التطبيق (اللي يقدرون يعدّلون الإعدادات والشروط من لوحة التحكم)
create table if not exists public.mn_admins (
  email text primary key
);
alter table public.mn_admins enable row level security;
-- بدون أي policy: ما أحد يقرأه أو يعدّله من التطبيق. تضيف إيميلك يدوياً (الخطوة الأخيرة تحت).

create or replace function public.mn_is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.mn_admins where email = lower(coalesce(auth.jwt()->>'email','')));
$$;

-- 2) إعدادات التطبيق المشتركة (الميزات، الشروط، تعليمات الرفيق، حدود الصور، سعر الباقة)
create table if not exists public.mn_app_config (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.mn_app_config enable row level security;
drop policy if exists mn_config_read on public.mn_app_config;
create policy mn_config_read on public.mn_app_config for select using (true);
drop policy if exists mn_config_write on public.mn_app_config;
create policy mn_config_write on public.mn_app_config for all
  using (public.mn_is_admin()) with check (public.mn_is_admin());

-- 3) استخدام يومي لكل جهاز (أرقام بس، بدون أسماء ولا محتوى سوالف)
create table if not exists public.mn_usage_daily (
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
alter table public.mn_usage_daily enable row level security;
drop policy if exists mn_usage_insert on public.mn_usage_daily;
create policy mn_usage_insert on public.mn_usage_daily for insert to anon, authenticated with check (true);
drop policy if exists mn_usage_update on public.mn_usage_daily;
create policy mn_usage_update on public.mn_usage_daily for update to anon, authenticated using (true) with check (true);
drop policy if exists mn_usage_read on public.mn_usage_daily;
create policy mn_usage_read on public.mn_usage_daily for select to anon, authenticated using (true);

-- 4) ملفات المستخدمين المسجلين في «مع نفسك» فقط
create table if not exists public.mn_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  name text,
  city text,
  gender text,
  app_id text,
  marketing boolean not null default false,
  terms_accepted_at timestamptz default now(),
  created_at timestamptz not null default now()
);
alter table public.mn_profiles enable row level security;
drop policy if exists mn_profiles_self on public.mn_profiles;
create policy mn_profiles_self on public.mn_profiles for select to authenticated using (auth.uid() = id or public.mn_is_admin());
drop policy if exists mn_profiles_update on public.mn_profiles;
create policy mn_profiles_update on public.mn_profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- يضيف الملف تلقائياً، بس للي سجلوا من «مع نفسك» (ما يلمس مستخدمي عقود)
create or replace function public.mn_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(new.raw_user_meta_data->>'app','') = 'ma-nafsak' then
    begin
      insert into public.mn_profiles (id, email, name, city, gender, app_id, marketing)
      values (new.id, lower(new.email),
        new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'city',
        new.raw_user_meta_data->>'gender', new.raw_user_meta_data->>'app_id',
        coalesce((new.raw_user_meta_data->>'marketing')::boolean, false))
      on conflict (id) do nothing;
    exception when others then
      null; -- أي خطأ هنا ما يوقف التسجيل
    end;
  end if;
  return new;
end $$;

drop trigger if exists mn_on_auth_user_created on auth.users;
create trigger mn_on_auth_user_created after insert on auth.users
  for each row execute function public.mn_handle_new_user();

-- 5) طلبات باقة بلس (أي أحد يرسل طلب، وأنت تشوفها من Table Editor)
create table if not exists public.mn_plan_requests (
  id         bigint generated always as identity primary key,
  email      text,
  name       text,
  app_id     text,
  plan       text        not null default 'plus',
  handled    boolean     not null default false,
  created_at timestamptz not null default now()
);
alter table public.mn_plan_requests enable row level security;
drop policy if exists mn_plan_insert on public.mn_plan_requests;
create policy mn_plan_insert on public.mn_plan_requests for insert to anon, authenticated with check (true);
drop policy if exists mn_plan_read on public.mn_plan_requests;
create policy mn_plan_read on public.mn_plan_requests for select to authenticated using (public.mn_is_admin());

-- 6) أرقام التسجيل للتقرير (مستخدمين «مع نفسك» فقط)
create or replace function public.mn_signup_stats() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'total',     (select count(*) from public.mn_profiles),
    'confirmed', (select count(*) from public.mn_profiles p join auth.users u on u.id = p.id where u.email_confirmed_at is not null),
    'marketing', (select count(*) from public.mn_profiles where marketing),
    'week',      (select count(*) from public.mn_profiles where created_at > now() - interval '7 days')
  );
$$;
grant execute on function public.mn_signup_stats() to anon, authenticated;

-- لتصدير إيميلات اللي وافقوا على الأخبار:
-- select email, name, city, created_at from public.mn_profiles where marketing order by created_at desc;

-- 7) الخطوة الأخيرة (شغّلها بنفسك بإيميلك، مو موجودة في الملف عشان الخصوصية):
-- insert into public.mn_admins (email) values ('your@email.com') on conflict do nothing;
