-- Keep initial knocks addressed to the house; subsequent outgoing messages
-- must target its owner so normal reply badges and Realtime filters see them.
-- Both tables use the same routing for Honoo/Hinoo cross-type continuations.
create or replace function public.route_house_followup_recipient()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  house_owner uuid;
begin
  if new.recipient_tag is null or new.reply_to is null
     or new.reply_to::text = new.recipient_tag then
    return new;
  end if;

  select c.owner_id into house_owner
  from public."case" c
  where c.campanello_hinoo_id::text = new.recipient_tag;

  if house_owner is not null and house_owner <> new.user_id and (
    exists (
      select 1 from public.honoo h
      where h.id::text = new.reply_to::text and h.user_id = new.user_id
        and h.recipient_tag in (new.recipient_tag, house_owner::text)
    ) or exists (
      select 1 from public.hinoo h
      where h.id::text = new.reply_to::text and h.user_id = new.user_id
        and h.recipient_tag in (new.recipient_tag, house_owner::text)
    )
  ) then
    new.recipient_tag := house_owner::text;
  end if;
  return new;
end;
$$;

revoke all on function public.route_house_followup_recipient() from public;

create trigger route_house_followup_recipient
before insert or update of recipient_tag, reply_to on public.honoo
for each row execute function public.route_house_followup_recipient();

create trigger route_house_followup_recipient
before insert or update of recipient_tag, reply_to on public.hinoo
for each row execute function public.route_house_followup_recipient();

-- Repair existing follow-ups too, leaving initial requests and access grants
-- untouched. The trigger checks the parent and sender before changing a row.
update public.honoo h set recipient_tag = h.recipient_tag
where h.reply_to is not null and h.reply_to::text <> h.recipient_tag
  and exists (select 1 from public."case" c where c.campanello_hinoo_id::text = h.recipient_tag);
update public.hinoo h set recipient_tag = h.recipient_tag
where h.reply_to is not null and h.reply_to::text <> h.recipient_tag
  and exists (select 1 from public."case" c where c.campanello_hinoo_id::text = h.recipient_tag);
