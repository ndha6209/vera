-- VERA CLOUD: تحسين سجل التدقيق وتوثيق تغييرات الحسابات
-- آمن للتنفيذ أكثر من مرة (idempotent).

create or replace function public.log_row_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  old_data jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else '{}'::jsonb end;
  new_data jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else '{}'::jsonb end;
  changed_fields text[] := array[]::text[];
  field_name text;
  rid text;
  extra jsonb := '{}'::jsonb;
begin
  rid := coalesce(new_data->>'id', old_data->>'id',
                  new_data->>'student_no', old_data->>'student_no');

  if tg_op = 'INSERT' then
    select coalesce(array_agg(k order by k), array[]::text[])
      into changed_fields from jsonb_object_keys(new_data) as k;
  elsif tg_op = 'DELETE' then
    select coalesce(array_agg(k order by k), array[]::text[])
      into changed_fields from jsonb_object_keys(old_data) as k;
  else
    for field_name in select key from jsonb_each(new_data)
    loop
      if old_data->field_name is distinct from new_data->field_name then
        changed_fields := array_append(changed_fields, field_name);
      end if;
    end loop;
  end if;

  -- لا نخزن كلمات مرور أو رموز دخول أو محتويات السجلات الحساسة.
  extra := jsonb_build_object('changed_fields', changed_fields);
  if tg_table_name = 'profiles' then
    extra := extra || jsonb_build_object(
      'name', coalesce(new_data->>'full_name', old_data->>'full_name'),
      'old_role', old_data->>'role',
      'new_role', new_data->>'role',
      'old_active', old_data->>'is_active',
      'new_active', new_data->>'is_active'
    );
  end if;

  insert into public.audit_logs(actor_id, action, table_name, record_id, details)
  values(auth.uid(), tg_op, tg_table_name, rid, extra);

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

-- توثيق إنشاء الحسابات وتعديل صلاحياتها وحالتها.
drop trigger if exists audit_profiles on public.profiles;
create trigger audit_profiles
after insert or update or delete on public.profiles
for each row execute function public.log_row_change();

-- إعادة تثبيت المشغلات على الجداول التشغيلية الموجودة في المخطط.
do $$
declare t text;
begin
  foreach t in array array[
    'students','teachers','courses','enrollments','attendance','exams',
    'questions','exam_attempts','exam_answers','invoices','payments',
    'expenses','announcements'
  ] loop
    execute format('drop trigger if exists audit_%I on public.%I', t, t);
    execute format(
      'create trigger audit_%I after insert or update or delete on public.%I for each row execute function public.log_row_change()',
      t, t
    );
  end loop;
end $$;

alter table public.audit_logs enable row level security;
drop policy if exists "admin read audit" on public.audit_logs;
create policy "admin read audit" on public.audit_logs
for select to authenticated
using (public.current_role() = 'admin');

grant select on public.audit_logs to authenticated;
