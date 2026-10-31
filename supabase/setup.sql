-- مع نفسك: إعداد Supabase للتجربة.
-- شغّله مرة وحدة: Supabase ← SQL Editor ← New query ← الصق الملف كامل ← Run.
-- آمن تعيد تشغيله لو عدّلنا عليه بعدين.

-- 1) تجميع الاستخدام: لكل جهاز ولكل يوم، أرقام بس بدون أسماء ولا محتوى سوالف.
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
drop policy if exists "usage insert" on public.usage_daily;
drop policy if exists "usage update" on public.usage_daily;
drop policy if exists "usage read"   on public.usage_daily;
create policy "usage insert" on public.usage_daily for insert to anon, authenticated with check (true);
create policy "usage update" on public.usage_daily for update to anon, authenticated using (true) with check (true);
create policy "usage read"   on public.usage_daily for select to anon, authenticated using (true);

-- 2) ملفات المستخدمين: تنعبى تلقائياً لما أحد يسجّل. فيها الإيميل والموافقة على الأخبار.
create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  email             text,
  name              text,
  city              text,
  app_id            text,
  marketing         boolean     not null default false,
  terms_accepted_at timestamptz,
  created_at        timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists "own profile read"   on public.profiles;
drop policy if exists "own profile update" on public.profiles;
create policy "own profile read"   on public.profiles for select to authenticated using (auth.uid() = id);
create policy "own profile update" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name, city, app_id, marketing, terms_accepted_at)
  values (new.id, lower(new.email), new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'city',
          new.raw_user_meta_data->>'app_id', coalesce((new.raw_user_meta_data->>'marketing')::boolean, false), now())
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- 3) أرقام التسجيل للوحة التحكم (أعداد بس، بدون إيميلات).
create or replace function public.signup_stats() returns json
language sql security definer set search_path = public as $$
  select json_build_object(
    'total',     (select count(*) from auth.users),
    'confirmed', (select count(*) from auth.users where email_confirmed_at is not null),
    'marketing', (select count(*) from public.profiles where marketing),
    'week',      (select count(*) from auth.users where created_at > now() - interval '7 days'));
$$;
grant execute on function public.signup_stats() to anon, authenticated;

-- 4) طلبات الباقة: يقدر أي أحد يرسل طلب، وأنت تشوفها من Table Editor.
create table if not exists public.plan_requests (
  id         bigserial primary key,
  email      text,
  name       text,
  app_id     text,
  plan       text        not null default 'plus10',
  handled    boolean     not null default false,
  created_at timestamptz not null default now()
);
alter table public.plan_requests enable row level security;
drop policy if exists "request insert" on public.plan_requests;
create policy "request insert" on public.plan_requests for insert to anon, authenticated with check (true);

-- لتصدير إيميلات اللي وافقوا على الأخبار:
-- select email, name, city, created_at from public.profiles where marketing order by created_at desc;
