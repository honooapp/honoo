begin;

create policy "owners delete chest honoo"
on public.honoo for delete to authenticated
using (auth.uid() = user_id and (destination::text <> 'moon' or is_from_moon_saved));
create policy "owners delete chest hinoo"
on public.hinoo for delete to authenticated
using (auth.uid() = user_id and (type::text not in ('moon', 'public') or is_from_moon_saved));

create policy "users hide their chest conversations"
on public.chest_hidden_conversations for insert to authenticated
with check (auth.uid() = user_id);
create policy "users update their hidden chest conversations"
on public.chest_hidden_conversations for update to authenticated
using (auth.uid() = user_id) with check (auth.uid() = user_id);

alter table public.conversation_tombstones
  add column if not exists deleted_by_owner boolean not null default false;

-- Replies are polymorphic (Honoo or Hinoo) and may now refer to a tombstone.
-- Keep their original ids so history ordering is preserved after deletion.
do $$
declare constraint_row record;
begin
  for constraint_row in
    select c.conrelid::regclass as relation, c.conname
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
    where c.contype = 'f' and c.conrelid in ('public.honoo'::regclass, 'public.hinoo'::regclass)
      and a.attname = 'reply_to'
  loop
    execute format('alter table %s drop constraint %I', constraint_row.relation, constraint_row.conname);
  end loop;
end $$;

-- House references must not prevent removal of the underlying content.
-- Clear only the content link; retain invitations, access and doorbells.
do $$
declare r record;
begin
  for r in select c.conrelid::regclass as relation, c.conname,
      a.attname, c.confrelid::regclass as target
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f' and cardinality(c.conkey) = 1
      and c.confrelid in ('public.honoo'::regclass, 'public.hinoo'::regclass)
      and c.conrelid in (coalesce(to_regclass('public.house_access'), 0::oid), coalesce(to_regclass('public.campanelli'), 0::oid))
  loop
    execute format('alter table %s drop constraint %I, add constraint %I foreign key (%I) references %s(id) on delete set null',
      r.relation, r.conname, r.conname, r.attname, r.target);
  end loop;
end $$;

create or replace function public.protect_conversation_content_deletion()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare is_moon boolean;
begin
  if auth.uid() is null then return old; end if;
  if tg_table_name = 'honoo' then
    is_moon := old.destination::text = 'moon';
  else
    is_moon := old.type::text in ('moon', 'public');
  end if;
  if not public.is_admin() and
     (old.user_id is distinct from auth.uid() or (is_moon and not coalesce(old.is_from_moon_saved, false))) then
    raise exception 'You can only delete your own chest content' using errcode = '42501';
  end if;
  if not coalesce(old.is_from_moon_saved, false) and (
       old.reply_to is not null
       or (nullif(old.conversation_id, '') is not null and old.conversation_id <> old.id::text)
       or exists (select 1 from public.honoo h where h.reply_to = old.id or (h.id <> old.id and h.conversation_id = old.id::text))
       or exists (select 1 from public.hinoo h where h.reply_to = old.id or (h.id <> old.id and h.conversation_id = old.id::text))) then
    insert into public.conversation_tombstones
      (content_id, conversation_id, source_kind, original_created_at, deleted_by_owner)
    values (old.id, coalesce(nullif(old.conversation_id, ''), old.reply_to::text, old.id::text),
            tg_table_name, old.created_at, old.user_id = auth.uid())
    on conflict (content_id) do nothing;
  end if;
  return old;
end;
$$;
commit;
