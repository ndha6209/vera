-- VERA CLOUD: expand account roles and promote the existing account to General Admin.
-- Run this script once in Supabase SQL Editor for project ovzyukmifefunukogkxr.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'developer';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'manager';

-- Promote the existing VERA owner account (same account previously used for Student Affairs).
-- This changes the role on the existing profile; it does not create a new account.
UPDATE public.profiles
SET role = 'admin',
    updated_at = now()
WHERE id = 'b80b75c7-29e5-403d-98e8-20d3c0c7900c';

-- Verify the result:
SELECT id, full_name, role, is_active
FROM public.profiles
WHERE id = 'b80b75c7-29e5-403d-98e8-20d3c0c7900c';
