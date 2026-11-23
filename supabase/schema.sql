-- VERA CLOUD — Supabase PostgreSQL schema
create extension if not exists pgcrypto;

create type public.app_role as enum ('admin','registrar','teacher','student','accountant');
create type public.record_status as enum ('active','inactive','suspended','completed');
create type public.payment_status as enum ('unpaid','partial','paid','cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role public.app_role not null default 'student',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  student_no text unique not null,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  full_name text not null,
  email text,
  phone text,
  birth_date date,
  gender text,
  address text,
  status public.record_status not null default 'active',
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.teachers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  full_name text not null,
  email text,
  phone text,
  specialty text,
  hourly_rate numeric(12,2) not null default 0 check(hourly_rate >= 0),
  status public.record_status not null default 'active',
  created_at timestamptz not null default now()
);

create table public.courses (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  title text not null,
  description text,
  category text,
  teacher_id uuid references public.teachers(id) on delete set null,
  start_date date,
  end_date date,
  capacity integer check(capacity is null or capacity > 0),
  fee numeric(12,2) not null default 0 check(fee >= 0),
  status public.record_status not null default 'active',
  created_at timestamptz not null default now()
);

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  enrolled_at timestamptz not null default now(),
  status public.record_status not null default 'active',
  final_grade numeric(5,2) check(final_grade between 0 and 100),
  unique(student_id, course_id)
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  session_date date not null default current_date,
  status text not null check(status in ('present','absent','late','excused')),
  notes text,
  marked_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(enrollment_id, session_date)
);

create table public.exams (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  title text not null,
  instructions text,
  starts_at timestamptz,
  duration_minutes integer not null default 30 check(duration_minutes > 0),
  total_marks numeric(8,2) not null default 100 check(total_marks > 0),
  is_published boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.questions (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  question_text text not null,
  question_type text not null default 'mcq' check(question_type in ('mcq','true_false','short')),
  options jsonb not null default '[]'::jsonb,
  marks numeric(8,2) not null default 1 check(marks > 0),
  sort_order integer not null default 0
);

create table public.exam_answer_keys (
  question_id uuid primary key references public.questions(id) on delete cascade,
  correct_answer text not null
);

create table public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  score numeric(8,2),
  status text not null default 'in_progress' check(status in ('in_progress','submitted','graded')),
  unique(exam_id, student_id)
);

create table public.exam_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.exam_attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  answer_text text,
  is_correct boolean,
  awarded_marks numeric(8,2) not null default 0,
  updated_at timestamptz not null default now(),
  unique(attempt_id, question_id)
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_no text unique not null,
  student_id uuid references public.students(id) on delete set null,
  description text not null,
  amount numeric(12,2) not null check(amount > 0),
  due_date date,
  status public.payment_status not null default 'unpaid',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  amount numeric(12,2) not null check(amount > 0),
  method text not null default 'cash',
  reference_no text,
  paid_at timestamptz not null default now(),
  received_by uuid references public.profiles(id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  expense_date date not null default current_date,
  category text not null,
  description text not null,
  amount numeric(12,2) not null check(amount > 0),
  reference_no text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null default 'all',
  published_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  table_name text not null,
  record_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_role()
returns public.app_role language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() and is_active = true $$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.current_role() in ('admin','registrar','teacher','accountant'), false) $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, full_name, phone, role)
  values(new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)), new.raw_user_meta_data->>'phone', 'student')
  on conflict(id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.log_row_change()
returns trigger language plpgsql security definer set search_path = public
as $$
declare rid text;
begin
  rid := case when tg_op='DELETE' then old.id::text else new.id::text end;
  insert into public.audit_logs(actor_id, action, table_name, record_id)
  values(auth.uid(), tg_op, tg_table_name, rid);
  if tg_op='DELETE' then return old; else return new; end if;
end $;

do $
declare t text;
begin
  foreach t in array array['students','teachers','courses','enrollments','attendance','exams','questions','exam_attempts','exam_answers','invoices','payments','expenses','announcements'] loop
    execute format('drop trigger if exists audit_%I on public.%I',t,t);
    execute format('create trigger audit_%I after insert or update or delete on public.%I for each row execute function public.log_row_change()',t,t);
  end loop;
end $$;

alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.teachers enable row level security;
alter table public.courses enable row level security;
alter table public.enrollments enable row level security;
alter table public.attendance enable row level security;
alter table public.exams enable row level security;
alter table public.questions enable row level security;
alter table public.exam_answer_keys enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.exam_answers enable row level security;
alter table public.invoices enable row level security;
alter table public.payments enable row level security;
alter table public.expenses enable row level security;
alter table public.announcements enable row level security;
alter table public.audit_logs enable row level security;

create policy "profiles read self or admin" on public.profiles for select to authenticated
using (id=auth.uid() or public.current_role()='admin');
create policy "admin update profiles" on public.profiles for update to authenticated
using (public.current_role()='admin') with check (public.current_role()='admin');

create policy "staff manage students" on public.students for all to authenticated
using (public.current_role() in ('admin','registrar')) with check (public.current_role() in ('admin','registrar'));
create policy "student read own record" on public.students for select to authenticated
using (auth_user_id=auth.uid());

create policy "staff read teachers" on public.teachers for select to authenticated using(public.is_staff());
create policy "admin registrar manage teachers" on public.teachers for all to authenticated
using(public.current_role() in ('admin','registrar')) with check(public.current_role() in ('admin','registrar'));

create policy "authenticated read active courses" on public.courses for select to authenticated using(status='active' or public.is_staff());
create policy "admin registrar manage courses" on public.courses for all to authenticated
using(public.current_role() in ('admin','registrar')) with check(public.current_role() in ('admin','registrar'));

create policy "staff manage enrollments" on public.enrollments for all to authenticated
using(public.current_role() in ('admin','registrar','teacher')) with check(public.current_role() in ('admin','registrar','teacher'));
create policy "staff manage attendance" on public.attendance for all to authenticated
using(public.current_role() in ('admin','registrar','teacher')) with check(public.current_role() in ('admin','registrar','teacher'));

create policy "read published exams" on public.exams for select to authenticated using(is_published or public.current_role() in ('admin','teacher','registrar'));
create policy "admin teacher manage exams" on public.exams for all to authenticated
using(public.current_role() in ('admin','teacher')) with check(public.current_role() in ('admin','teacher'));
create policy "read exam questions" on public.questions for select to authenticated
using(exists(select 1 from public.exams e where e.id=exam_id and (e.is_published or public.current_role() in ('admin','teacher'))));
create policy "teachers manage answer keys" on public.exam_answer_keys for all to authenticated
using(public.current_role() in ('admin','teacher')) with check(public.current_role() in ('admin','teacher'));
create policy "admin teacher manage questions" on public.questions for all to authenticated
using(public.current_role() in ('admin','teacher')) with check(public.current_role() in ('admin','teacher'));

create policy "students own attempts and staff" on public.exam_attempts for select to authenticated
using(public.current_role() in ('admin','teacher','registrar') or exists(select 1 from public.students s where s.auth_user_id=auth.uid() and s.id=student_id));
create policy "students create own attempts" on public.exam_attempts for insert to authenticated
with check(exists(select 1 from public.students s where s.auth_user_id=auth.uid() and s.id=student_id));
create policy "students update own attempts" on public.exam_attempts for update to authenticated
using(exists(select 1 from public.students s join public.profiles p on lower(p.full_name)=lower(s.full_name) where p.id=auth.uid() and s.id=student_id))
with check(exists(select 1 from public.students s join public.profiles p on lower(p.full_name)=lower(s.full_name) where p.id=auth.uid() and s.id=student_id));
create policy "answers own or staff" on public.exam_answers for all to authenticated
using(public.current_role() in ('admin','teacher') or exists(select 1 from public.exam_attempts a join public.students s on s.id=a.student_id where a.id=attempt_id and s.auth_user_id=auth.uid()))
with check(public.current_role() in ('admin','teacher') or exists(select 1 from public.exam_attempts a join public.students s on s.id=a.student_id join public.profiles p on lower(p.full_name)=lower(s.full_name) where a.id=attempt_id and p.id=auth.uid()));

create policy "finance staff read invoices" on public.invoices for select to authenticated using(public.current_role() in ('admin','accountant','registrar'));
create policy "finance staff manage invoices" on public.invoices for all to authenticated using(public.current_role() in ('admin','accountant')) with check(public.current_role() in ('admin','accountant'));
create policy "finance staff manage payments" on public.payments for all to authenticated using(public.current_role() in ('admin','accountant')) with check(public.current_role() in ('admin','accountant'));
create policy "finance staff manage expenses" on public.expenses for all to authenticated using(public.current_role() in ('admin','accountant')) with check(public.current_role() in ('admin','accountant'));
create policy "staff manage announcements" on public.announcements for all to authenticated using(public.current_role() in ('admin','registrar')) with check(public.current_role() in ('admin','registrar'));
create policy "read announcements" on public.announcements for select to authenticated using(true);
create policy "admin read audit" on public.audit_logs for select to authenticated using(public.current_role()='admin');

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- IMPORTANT: create your first account through Supabase Auth, then promote it manually:
-- update public.profiles set role='admin' where id='YOUR_AUTH_USER_UUID';
-- Never place the Supabase service_role key in the browser or in GitHub.
