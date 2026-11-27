-- VERA CLOUD public landing page content
-- Run once in Supabase SQL Editor.
create table if not exists public.public_site_content (
  id uuid primary key default gen_random_uuid(),
  content_type text not null check (content_type in ('course','video','notice','feature')),
  title text not null,
  body text,
  image_url text,
  media_url text,
  action_label text,
  action_url text,
  sort_order integer not null default 0,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.public_site_content enable row level security;

drop policy if exists "public can read active site content" on public.public_site_content;
create policy "public can read active site content"
on public.public_site_content for select
to anon, authenticated
using (is_active = true);

drop policy if exists "admin manage public site content" on public.public_site_content;
create policy "admin manage public site content"
on public.public_site_content for all
to authenticated
using (public.current_role() = 'admin')
with check (public.current_role() = 'admin');

grant select on public.public_site_content to anon, authenticated;
grant insert, update, delete on public.public_site_content to authenticated;

create index if not exists public_site_content_active_order_idx
on public.public_site_content (is_active, sort_order, created_at desc);
