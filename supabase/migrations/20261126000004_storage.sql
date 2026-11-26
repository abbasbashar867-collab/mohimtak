-- تخزين خاص: لا رابط عام ولا أي سياسة وصول للمستخدمين. القراءة عبر الخادم فقط بعد التسجيل في سجل التدقيق.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('identity-documents', 'identity-documents', false, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- سياسة مانعة: تبقى سارية حتى لو أُضيفت لاحقاً سياسة سماح عامة بالخطأ
create policy identity_documents_server_only on storage.objects
  as restrictive for all to anon, authenticated
  using (bucket_id <> 'identity-documents')
  with check (bucket_id <> 'identity-documents');
