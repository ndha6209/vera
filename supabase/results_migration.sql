-- VERA CLOUD: secure academic results publishing
-- Run once in Supabase SQL Editor for the existing project.

alter table public.enrollments
  add column if not exists final_grade_published boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'enrollments_published_grade_requires_value'
      and conrelid = 'public.enrollments'::regclass
  ) then
    alter table public.enrollments
      add constraint enrollments_published_grade_requires_value
      check (not final_grade_published or final_grade is not null);
  end if;
end $$;

drop policy if exists "student read own enrollments" on public.enrollments;
create policy "student read own enrollments"
on public.enrollments for select to authenticated
using (
  exists (
    select 1 from public.students s
    where s.id = student_id
      and s.auth_user_id = auth.uid()
      and s.status = 'active'
  )
);

drop policy if exists "student read enrolled course details" on public.courses;
create policy "student read enrolled course details"
on public.courses for select to authenticated
using (
  exists (
    select 1
    from public.enrollments e
    join public.students s on s.id = e.student_id
    where e.course_id = courses.id
      and s.auth_user_id = auth.uid()
      and s.status = 'active'
  )
);

create index if not exists students_auth_user_id_idx
  on public.students(auth_user_id);
create index if not exists enrollments_student_published_idx
  on public.enrollments(student_id, final_grade_published);
