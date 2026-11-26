-- VERA CLOUD: صفحات فريق العمل والمبرمجين وملفات المدرسين
-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor.

create table if not exists public.people_directory (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('team','developer')),
  full_name text not null,
  job_title text not null,
  specialty text,
  bio text,
  photo_url text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.teachers
  add column if not exists bio text,
  add column if not exists photo_url text;

create index if not exists people_directory_category_order_idx
  on public.people_directory(category, sort_order, full_name);

alter table public.people_directory enable row level security;

drop policy if exists "read active directory profiles" on public.people_directory;
create policy "read active directory profiles"
  on public.people_directory for select to authenticated
  using (is_active = true or public.current_role() in ('admin','registrar'));

drop policy if exists "admin registrar manage directory" on public.people_directory;
create policy "admin registrar manage directory"
  on public.people_directory for all to authenticated
  using (public.current_role() in ('admin','registrar'))
  with check (public.current_role() in ('admin','registrar'));

grant select, insert, update, delete on public.people_directory to authenticated;
