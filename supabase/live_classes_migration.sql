-- VERA CLOUD: live classroom foundation
-- Run this migration once in Supabase SQL Editor.

create table if not exists public.live_classes (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null,
  description text,
  scheduled_at timestamptz not null,
  duration_minutes integer not null default 60 check (duration_minutes between 5 and 480),
  status text not null default 'scheduled'
    check (status in ('scheduled','live','ended','cancelled')),
  meeting_url text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.live_class_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.live_classes(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check (char_length(trim(message)) between 1 and 3000),
  created_at timestamptz not null default now()
);

create table if not exists public.live_class_notes (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.live_classes(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  note text not null default '',
  updated_at timestamptz not null default now(),
  unique (session_id, user_id)
);

create index if not exists live_classes_course_date_idx
  on public.live_classes(course_id, scheduled_at desc);
create index if not exists live_class_messages_session_date_idx
  on public.live_class_messages(session_id, created_at);
create index if not exists live_class_notes_user_idx
  on public.live_class_notes(user_id, session_id);

create or replace function public.can_manage_live_course(p_course_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    public.current_role() = 'admin'
    or (
      public.current_role() = 'teacher'
      and exists (
        select 1
        from public.courses c
        join public.teachers t on t.id = c.teacher_id
        where c.id = p_course_id and t.profile_id = auth.uid()
      )
    ),
    false
  );
$$;

create or replace function public.can_access_live_class(p_session_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    exists (
      select 1 from public.live_classes lc
      where lc.id = p_session_id
        and (
          public.can_manage_live_course(lc.course_id)
          or (
            public.current_role() = 'student'
            and exists (
              select 1
              from public.enrollments e
              join public.students s on s.id = e.student_id
              where e.course_id = lc.course_id
                and e.status = 'active'
                and s.auth_user_id = auth.uid()
            )
          )
        )
    ),
    false
  );
$$;

alter table public.live_classes enable row level security;
alter table public.live_class_messages enable row level security;
alter table public.live_class_notes enable row level security;

drop policy if exists "live classes visible to course members" on public.live_classes;
create policy "live classes visible to course members"
on public.live_classes for select to authenticated
using (
  public.can_manage_live_course(course_id)
  or (
    public.current_role() = 'student'
    and exists (
      select 1
      from public.enrollments e
      join public.students s on s.id = e.student_id
      where e.course_id = live_classes.course_id
        and e.status = 'active'
        and s.auth_user_id = auth.uid()
    )
  )
);

drop policy if exists "course teachers create live classes" on public.live_classes;
create policy "course teachers create live classes"
on public.live_classes for insert to authenticated
with check (public.can_manage_live_course(course_id) and created_by = auth.uid());

drop policy if exists "course teachers update live classes" on public.live_classes;
create policy "course teachers update live classes"
on public.live_classes for update to authenticated
using (public.can_manage_live_course(course_id))
with check (public.can_manage_live_course(course_id));

drop policy if exists "course teachers delete live classes" on public.live_classes;
create policy "course teachers delete live classes"
on public.live_classes for delete to authenticated
using (public.can_manage_live_course(course_id));

drop policy if exists "class members read chat" on public.live_class_messages;
create policy "class members read chat"
on public.live_class_messages for select to authenticated
using (public.can_access_live_class(session_id));

drop policy if exists "class members send chat" on public.live_class_messages;
create policy "class members send chat"
on public.live_class_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and public.can_access_live_class(session_id)
);

drop policy if exists "users manage own class notes" on public.live_class_notes;
create policy "users manage own class notes"
on public.live_class_notes for all to authenticated
using (user_id = auth.uid() and public.can_access_live_class(session_id))
with check (user_id = auth.uid() and public.can_access_live_class(session_id));

grant select, insert, update, delete on public.live_classes to authenticated;
grant select, insert on public.live_class_messages to authenticated;
grant select, insert, update, delete on public.live_class_notes to authenticated;
grant execute on function public.can_manage_live_course(uuid) to authenticated;
grant execute on function public.can_access_live_class(uuid) to authenticated;

-- Add the new operational tables to the existing audit trail.
drop trigger if exists audit_live_classes on public.live_classes;
create trigger audit_live_classes
after insert or update or delete on public.live_classes
for each row execute function public.log_row_change();

drop trigger if exists audit_live_class_messages on public.live_class_messages;
create trigger audit_live_class_messages
after insert or update or delete on public.live_class_messages
for each row execute function public.log_row_change();

-- Enable Supabase Realtime for chat, without failing if already published.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'live_class_messages'
  ) then
    alter publication supabase_realtime add table public.live_class_messages;
  end if;
exception when undefined_object then
  raise notice 'supabase_realtime publication is not available in this project yet.';
end $$;
