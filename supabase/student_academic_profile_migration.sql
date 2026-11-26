-- VERA CLOUD: allow each linked student to read only their own attendance rows
-- Run once in Supabase SQL Editor. Safe to re-run.

drop policy if exists "students read own attendance" on public.attendance;
create policy "students read own attendance"
on public.attendance
for select
to authenticated
using (
  exists (
    select 1
    from public.enrollments e
    join public.students s on s.id = e.student_id
    where e.id = attendance.enrollment_id
      and s.auth_user_id = auth.uid()
  )
);

grant select on public.attendance to authenticated;
