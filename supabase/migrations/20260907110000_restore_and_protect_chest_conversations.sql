begin;

-- User deletion only hid the thread. Restore those threads without changing
-- content or undoing moderation/admin choices.
delete from public.chest_hidden_conversations hidden
where not exists (
  select 1 from public.users u
  where u.auth_user_id = hidden.user_id and u.is_admin = true
);

drop policy "users hide their chest conversations"
  on public.chest_hidden_conversations;
drop policy "users update their hidden chest conversations"
  on public.chest_hidden_conversations;

create policy "admins hide their chest conversations"
on public.chest_hidden_conversations for insert to authenticated
with check (auth.uid() = user_id and public.is_admin());

create policy "admins update their hidden chest conversations"
on public.chest_hidden_conversations for update to authenticated
using (auth.uid() = user_id and public.is_admin())
with check (auth.uid() = user_id and public.is_admin());

-- Also protect content from older clients or direct DELETE requests. Checking
-- both tables preserves mixed Honoo/Hinoo threads and legacy parent rows.
create or replace function public.protect_conversation_content_deletion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return old;
  end if;

  if nullif(old.conversation_id, '') is not null
     or old.reply_to is not null
     or exists (select 1 from public.honoo h
                where h.reply_to = old.id or h.conversation_id = old.id::text)
     or exists (select 1 from public.hinoo h
                where h.reply_to = old.id or h.conversation_id = old.id::text)
  then
    raise exception 'Only admins can delete conversation content'
      using errcode = '42501';
  end if;
  return old;
end;
$$;

revoke all on function public.protect_conversation_content_deletion() from public;

create trigger protect_honoo_conversation_deletion
before delete on public.honoo
for each row execute function public.protect_conversation_content_deletion();

create trigger protect_hinoo_conversation_deletion
before delete on public.hinoo
for each row execute function public.protect_conversation_content_deletion();

commit;
