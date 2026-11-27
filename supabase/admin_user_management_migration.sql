-- VERA CLOUD: secure administrator-managed account changes.
-- Run once in Supabase SQL Editor for project ovzyukmifefunukogkxr.

create or replace function public.admin_manage_profile(
  p_user_id uuid,
  p_role public.app_role,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_role public.app_role;
  v_old_active boolean;
  v_admin_count integer;
begin
  if auth.uid() is null or public.current_role() <> 'admin' then
    raise exception 'غير مصرح: هذه العملية للمدير العام فقط';
  end if;

  if p_user_id is null or p_role is null or p_is_active is null then
    raise exception 'بيانات الحساب غير مكتملة';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'لا يمكن تغيير صلاحية حساب المدير العام الحالي أو إيقافه من الحساب نفسه';
  end if;

  -- Serialize admin changes so two simultaneous requests cannot remove the last active admin.
  perform pg_advisory_xact_lock(hashtext('vera_admin_profile_management'));

  select role, is_active
    into v_old_role, v_old_active
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'الحساب المطلوب غير موجود';
  end if;

  if v_old_role = 'admin' and v_old_active
     and (p_role <> 'admin' or not p_is_active) then
    select count(*) into v_admin_count
    from public.profiles
    where role = 'admin' and is_active = true;

    if v_admin_count <= 1 then
      raise exception 'لا يمكن خفض صلاحية أو إيقاف آخر مدير عام نشط';
    end if;
  end if;

  update public.profiles
  set role = p_role,
      is_active = p_is_active,
      updated_at = now()
  where id = p_user_id;
end;
$$;

revoke all on function public.admin_manage_profile(uuid, public.app_role, boolean) from public;
grant execute on function public.admin_manage_profile(uuid, public.app_role, boolean) to authenticated;

-- Remove direct profile updates: account changes must pass through the guarded function above.
drop policy if exists "admin update profiles" on public.profiles;
