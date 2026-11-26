-- VERA CLOUD: مكتبة الملفات التعليمية وتنزيل ملفات PDF
-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor.

create table if not exists public.learning_resources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  file_name text not null,
  file_path text not null unique,
  mime_type text not null default 'application/pdf',
  file_size bigint not null default 0,
  uploaded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.learning_resources enable row level security;

drop policy if exists "authenticated users read learning resources" on public.learning_resources;
create policy "authenticated users read learning resources"
  on public.learning_resources for select to authenticated
  using (true);

drop policy if exists "staff upload learning resources" on public.learning_resources;
create policy "staff upload learning resources"
  on public.learning_resources for insert to authenticated
  with check (public.current_role() in ('admin','registrar'));

drop policy if exists "staff delete learning resources" on public.learning_resources;
create policy "staff delete learning resources"
  on public.learning_resources for delete to authenticated
  using (public.current_role() in ('admin','registrar'));

grant select, insert, delete on public.learning_resources to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('vera-learning-files', 'vera-learning-files', false, 26214400, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = 26214400,
    allowed_mime_types = array['application/pdf'];

drop policy if exists "authenticated read VERA learning files" on storage.objects;
create policy "authenticated read VERA learning files"
  on storage.objects for select to authenticated
  using (bucket_id = 'vera-learning-files');

drop policy if exists "staff upload VERA learning files" on storage.objects;
create policy "staff upload VERA learning files"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'vera-learning-files'
    and public.current_role() in ('admin','registrar')
  );

drop policy if exists "staff delete VERA learning files" on storage.objects;
create policy "staff delete VERA learning files"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'vera-learning-files'
    and public.current_role() in ('admin','registrar')
  );
