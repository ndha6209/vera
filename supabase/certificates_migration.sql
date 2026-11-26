-- VERA CLOUD: electronic certificates with secure issuance and public verification
-- Run once in Supabase SQL Editor. Safe to re-run.

create sequence if not exists public.vera_certificate_seq;

create table if not exists public.certificates (
  id uuid primary key default gen_random_uuid(),
  certificate_no text not null unique default (
    'VERA-' || to_char(now(),'YYYY') || '-' ||
    lpad(nextval('public.vera_certificate_seq')::text,6,'0')
  ),
  verification_code text not null unique default encode(gen_random_bytes(16),'hex'),
  enrollment_id uuid not null references public.enrollments(id) on delete restrict,
  student_id uuid not null references public.students(id) on delete restrict,
  course_id uuid not null references public.courses(id) on delete restrict,
  issued_at timestamptz not null default now(),
  issued_by uuid references public.profiles(id),
  is_revoked boolean not null default false,
  revoked_at timestamptz,
  revoked_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create unique index if not exists certificates_one_active_per_enrollment
  on public.certificates(enrollment_id) where is_revoked = false;

create or replace function public.prepare_certificate()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_student uuid;
  v_course uuid;
  v_status public.record_status;
begin
  if tg_op = 'INSERT' then
    select e.student_id, e.course_id, e.status
      into v_student, v_course, v_status
      from public.enrollments e
     where e.id = new.enrollment_id;
    if v_student is null then
      raise exception 'التسجيل المحدد غير موجود.';
    end if;
    if v_status <> 'completed' then
      raise exception 'لا يمكن إصدار شهادة قبل إكمال الدورة واعتماد حالة التسجيل كمكتمل.';
    end if;
    new.student_id := v_student;
    new.course_id := v_course;
    new.issued_by := auth.uid();
    new.issued_at := coalesce(new.issued_at, now());
  else
    if new.enrollment_id is distinct from old.enrollment_id
       or new.student_id is distinct from old.student_id
       or new.course_id is distinct from old.course_id
       or new.certificate_no is distinct from old.certificate_no
       or new.verification_code is distinct from old.verification_code
       or new.issued_at is distinct from old.issued_at
       or new.issued_by is distinct from old.issued_by then
      raise exception 'لا يمكن تعديل بيانات الشهادة الأساسية بعد إصدارها.';
    end if;
    if new.is_revoked and not old.is_revoked then
      new.revoked_at := now();
      new.revoked_by := auth.uid();
    elsif not new.is_revoked then
      new.revoked_at := null;
      new.revoked_by := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists certificates_prepare on public.certificates;
create trigger certificates_prepare
before insert or update on public.certificates
for each row execute function public.prepare_certificate();

alter table public.certificates enable row level security;

drop policy if exists "staff read certificates" on public.certificates;
create policy "staff read certificates"
on public.certificates for select to authenticated
using (public.current_role() in ('admin','registrar'));

drop policy if exists "students read own certificates" on public.certificates;
create policy "students read own certificates"
on public.certificates for select to authenticated
using (exists (
  select 1 from public.students s
  where s.id = certificates.student_id and s.auth_user_id = auth.uid()
));

drop policy if exists "staff issue certificates" on public.certificates;
create policy "staff issue certificates"
on public.certificates for insert to authenticated
with check (public.current_role() in ('admin','registrar'));

drop policy if exists "staff revoke certificates" on public.certificates;
create policy "staff revoke certificates"
on public.certificates for update to authenticated
using (public.current_role() in ('admin','registrar'))
with check (public.current_role() in ('admin','registrar'));

grant select, insert, update on public.certificates to authenticated;
grant usage, select on sequence public.vera_certificate_seq to authenticated;

create or replace function public.verify_certificate(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c record;
begin
  select cert.certificate_no, cert.issued_at, cert.is_revoked,
         s.full_name as student_name, co.title as course_title
    into c
    from public.certificates cert
    join public.students s on s.id = cert.student_id
    join public.courses co on co.id = cert.course_id
   where lower(cert.verification_code) = lower(trim(coalesce(p_code,'')))
   limit 1;

  if not found then
    return jsonb_build_object('valid',false,'message','رمز التحقق غير صحيح أو الشهادة غير موجودة.');
  end if;
  if c.is_revoked then
    return jsonb_build_object('valid',false,'message','هذه الشهادة ملغاة ولم تعد صالحة.');
  end if;

  return jsonb_build_object(
    'valid',true,
    'certificate_no',c.certificate_no,
    'issued_at',c.issued_at,
    'student_name',c.student_name,
    'course_title',c.course_title
  );
end;
$$;

revoke all on function public.verify_certificate(text) from public;
grant execute on function public.verify_certificate(text) to anon, authenticated;
