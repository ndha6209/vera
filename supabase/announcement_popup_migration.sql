-- VERA CLOUD: announcement popups and per-student read tracking
alter table public.announcements
  add column if not exists image_url text,
  add column if not exists is_active boolean not null default true,
  add column if not exists popup_duration_seconds integer not null default 60
    check (popup_duration_seconds between 30 and 300);

create table if not exists public.announcement_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, announcement_id)
);

alter table public.announcement_reads enable row level security;
drop policy if exists "students read own announcement receipts" on public.announcement_reads;
drop policy if exists "students mark own announcements read" on public.announcement_reads;
create policy "students read own announcement receipts" on public.announcement_reads for select to authenticated using (user_id = auth.uid());
create policy "students mark own announcements read" on public.announcement_reads for insert to authenticated with check (user_id = auth.uid());
grant select, insert on public.announcement_reads to authenticated;
grant select, insert, update, delete on public.announcements to authenticated;
