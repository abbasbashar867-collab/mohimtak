-- Supabase يمنح صلاحيات واسعة افتراضياً؛ نسحبها كلها ثم نمنح المطلوب فقط.
revoke all on all tables    in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- حتى مفتاح الخادم لا يعدّل السجلات أو الحسابات مباشرة
revoke insert, update, delete, truncate on all tables in schema public from service_role;

alter table public.roles                  enable row level security;
alter table public.permissions            enable row level security;
alter table public.role_permissions       enable row level security;
alter table public.user_roles             enable row level security;
alter table public.profiles               enable row level security;
alter table public.identity_documents     enable row level security;
alter table public.account_status_history enable row level security;
alter table public.audit_logs             enable row level security;
alter table public.security_events        enable row level security;
alter table public.settings               enable row level security;
alter table public.rate_limits            enable row level security;

grant select on public.roles, public.permissions, public.role_permissions, public.user_roles,
  public.profiles, public.identity_documents, public.account_status_history,
  public.audit_logs, public.security_events, public.settings to authenticated;

create policy roles_admin       on public.roles            for select to authenticated using ((select public.is_super_admin()));
create policy permissions_admin on public.permissions      for select to authenticated using ((select public.is_super_admin()));
create policy role_perm_admin   on public.role_permissions for select to authenticated using ((select public.is_super_admin()));
create policy user_roles_own    on public.user_roles       for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_super_admin()));
create policy profiles_own_or_admin on public.profiles     for select to authenticated
  using (id = (select auth.uid()) or (select public.is_super_admin()));
-- حتى صاحب المستند لا يصل إليه: المدير العام فقط
create policy documents_admin   on public.identity_documents     for select to authenticated using ((select public.is_super_admin()));
create policy history_admin     on public.account_status_history for select to authenticated using ((select public.is_super_admin()));
create policy audit_admin       on public.audit_logs             for select to authenticated using ((select public.is_super_admin()));
create policy events_admin      on public.security_events        for select to authenticated using ((select public.is_super_admin()));
create policy settings_admin    on public.settings               for select to authenticated using ((select public.is_super_admin()));

grant execute on function public.get_public_settings() to anon, authenticated, service_role;
grant execute on function public.is_super_admin()      to authenticated;
grant execute on function public.review_registration(uuid, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.set_account_status(uuid, public.account_status, text)         to authenticated;
grant execute on function public.log_document_view(uuid, text, text)                           to authenticated;

revoke execute on all functions in schema public from service_role;
grant execute on function public.get_public_settings() to service_role;
grant execute on function public.register_account(uuid, public.account_type, text, text, text, jsonb, text, text) to service_role;
grant execute on function public.documents_due_for_purge(integer)      to service_role;
grant execute on function public.mark_document_purged(uuid)            to service_role;
grant execute on function public.orphaned_registrations()              to service_role;
grant execute on function public.check_rate_limit(text, integer, integer) to service_role;
grant execute on function public.bootstrap_super_admin(uuid)           to service_role;
