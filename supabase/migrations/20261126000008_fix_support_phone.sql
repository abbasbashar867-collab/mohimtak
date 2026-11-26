-- تصحيح رقم الإدارة إلى 07826849259
insert into public.settings (key, value, is_public)
values ('support.whatsapp', '"+9647826849259"', true)
on conflict (key) do update set value = excluded.value, updated_at = now();
