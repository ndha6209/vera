-- VERA CLOUD: secure student self-linking and published results access
-- Run once in Supabase SQL Editor. Safe to re-run.

alter table public.enrollments
  add column if not exists final_grade_published boolean not null default false;

drop policy if exists "students read own enrollments" on public.enrollments;
create policy "students read own enrollments"
on public.enrollments for select to authenticated
using (
  exists (
    select 1 from public.students s
    where s.id = enrollments.student_id
      and s.auth_user_id = auth.uid()
  )
);

create or replace function public.link_student_by_academic_no(p_student_no text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(coalesce(auth.jwt()->>'email','')));
  v_student_id uuid;
begin
  if v_uid is null or v_email = '' or nullif(trim(p_student_no),'') is null then
    return jsonb_build_object('ok',false,'message','بيانات الربط غير مكتملة.');
  end if;

  update public.students
     set auth_user_id = v_uid,
         updated_at = now()
   where student_no = trim(p_student_no)
     and lower(trim(coalesce(email,''))) = v_email
     and (auth_user_id is null or auth_user_id = v_uid)
  returning id into v_student_id;

  if v_student_id is null then
    return jsonb_build_object(
      'ok',false,
      'message','لم نجد سجلًا يطابق الرقم الأكاديمي وبريد حسابك. تأكد من بياناتك لدى شؤون الطلاب.'
    );
  end if;

  return jsonb_build_object('ok',true);
end;
$$;

revoke all on function public.link_student_by_academic_no(text) from public;
grant execute on function public.link_student_by_academic_no(text) to authenticated;
