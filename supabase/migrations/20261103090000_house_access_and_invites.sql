-- A doorbell message and its access request share one database transaction.
create function public.record_doorbell_knock() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if new.reply_to::text = new.recipient_tag and exists (
    select 1 from public."case" c where c.campanello_hinoo_id::text = new.recipient_tag
    and c.owner_id <> new.user_id
  ) then
    insert into public.house_access(target_house_tag, visitor_id, honoo_id, hinoo_id)
    values (new.recipient_tag, new.user_id,
      case when tg_table_name = 'honoo' then new.id end,
      case when tg_table_name = 'hinoo' then new.id end);
  end if;
  return new;
end;
$$;
create trigger record_doorbell_knock after insert on public.honoo
for each row execute function public.record_doorbell_knock();
create trigger record_doorbell_knock after insert on public.hinoo
for each row execute function public.record_doorbell_knock();

-- Older clients explicitly register the knock a second time after saving.
create function public.skip_recorded_knock() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if new.visitor_id = auth.uid() and exists (
    select 1 from public.house_access a where a.visitor_id = new.visitor_id
    and a.target_house_tag = new.target_house_tag
    and (a.honoo_id = new.honoo_id or a.hinoo_id = new.hinoo_id)
  ) then return null; end if;
  return new;
end;
$$;
create trigger skip_recorded_knock before insert on public.house_access
for each row execute function public.skip_recorded_knock();

-- Keep the permissions already effective for historical guests.
with permissions as (
  select a.visitor_id, a.target_house_tag,
         coalesce(array_agg(distinct mode) filter (where mode is not null), '{}'::text[]) modes
  from public.house_access a left join lateral unnest(a.share_modes) mode on true
  where a.granted_at is not null group by a.visitor_id, a.target_house_tag
)
update public.house_access a set share_modes = p.modes from permissions p
where a.visitor_id = p.visitor_id and a.target_house_tag = p.target_house_tag
and a.granted_at is not null and a.share_modes is distinct from p.modes;

create or replace function public.get_house_inbox(p_house_tag text default null)
returns table(id bigint, target_house_tag text, created_at timestamptz,
 granted_at timestamptz, share_modes text[], honoo jsonb, hinoo jsonb)
language sql stable security definer set search_path = public, pg_temp
as $$
 select ha.id, ha.target_house_tag, ha.created_at, ha.granted_at,
 ha.share_modes, content.honoo, content.hinoo
 from public.house_access ha
 join public."case" c on c.campanello_hinoo_id::text = ha.target_house_tag
 left join lateral (
   select sent.honoo, sent.hinoo from (
     select h.created_at, h.id, to_jsonb(h) honoo, null::jsonb hinoo
     from public.honoo h where h.user_id = ha.visitor_id
       and h.recipient_tag = ha.target_house_tag
       and h.id = ha.honoo_id
     union all
     select h.created_at, h.id, null::jsonb, to_jsonb(h)
     from public.hinoo h where h.user_id = ha.visitor_id
       and h.recipient_tag = ha.target_house_tag
       and h.id = ha.hinoo_id
   ) sent order by sent.created_at asc nulls last, sent.id, (sent.honoo is null) limit 1
 ) content on true
 where c.owner_id = auth.uid()
   and (p_house_tag is null or ha.target_house_tag = p_house_tag)
 order by (ha.granted_at is not null), ha.created_at asc, ha.id asc;
$$;
revoke all on function public.get_house_inbox(text) from public;
grant execute on function public.get_house_inbox(text) to authenticated;

-- Serialize permission changes per house, including approvals from older clients.
create function public.set_house_visitor_permissions(p_id bigint, p_modes text[], p_approve boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  request public.house_access%rowtype;
begin
  if auth.uid() is null or p_modes is null or array_position(p_modes,null) is not null
     or not (p_modes <@ array['home','moon','all']::text[])
     or (p_approve and cardinality(p_modes) = 0) then
    raise exception 'Invalid permissions' using errcode = '22023';
  end if;
  perform 1 from public."case" c join public.house_access a
    on c.campanello_hinoo_id::text = a.target_house_tag
    where c.owner_id = auth.uid() and a.id = p_id for update of c;
  if not found then raise exception 'House not owned' using errcode = '42501'; end if;
  select * into strict request from public.house_access where id = p_id for update;
  if p_approve <> (request.granted_at is null) then
    raise exception 'Request state changed' using errcode = '40001';
  end if;
  update public.house_access a
    set share_modes = array(select distinct unnest(p_modes)),
        granted_at = coalesce(a.granted_at, now())
    where a.id = request.id or (a.target_house_tag = request.target_house_tag
          and a.visitor_id = request.visitor_id and a.granted_at is not null);
end;
$$;
revoke all on function public.set_house_visitor_permissions(bigint,text[],boolean) from public;
create or replace function public.approve_house_knock(p_knock_id bigint,p_share_modes text[])
returns void language sql security definer set search_path = public, pg_temp as $$
  select public.set_house_visitor_permissions(p_knock_id,p_share_modes,true);
$$;
create or replace function public.update_house_guest_access(p_knock_id bigint,p_share_modes text[])
returns void language sql security definer set search_path = public, pg_temp as $$
  select public.set_house_visitor_permissions(p_knock_id,p_share_modes,false);
$$;

alter table public.house_invites add column email_delivery_pending boolean not null default false;

create or replace function public.admin_review_house_request(
  p_invite_id uuid,
  p_approved boolean
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  requester_id uuid;
begin
  if not public.is_admin() then
    raise exception 'Admin access required';
  end if;

  select user_id into requester_id
  from public.house_invites
  where id = p_invite_id and status = 'requested';
  if requester_id is null then
    return false;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(requester_id::text, 0));

  if p_approved and (
    exists (select 1 from public."case" where owner_id = requester_id)
    or exists (
      select 1 from public.house_invites
      where user_id = requester_id
        and id <> p_invite_id
        and status in ('pending', 'accepted')
    )
  ) then
    update public.house_invites
    set status = 'declined', invited_by = auth.uid()
    where id = p_invite_id and status = 'requested';
    return false;
  end if;

  update public.house_invites
  set status = case when p_approved then 'pending' else 'declined' end,
      invited_by = auth.uid()
  where id = p_invite_id
    and status = 'requested';
  return found;
end;
$$;

revoke all on function public.admin_review_house_request(uuid, boolean) from public;
grant execute on function public.admin_review_house_request(uuid, boolean)
  to authenticated;


-- Reserve a delivery before contacting Auth. A failed or abandoned attempt
-- can be retried without creating another invitation.
alter table public.house_invites add column delivery_lease_until timestamptz;
create function public.prepare_house_invite(p_user_id uuid, p_email text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  recipient text := lower(nullif(btrim(p_email), ''));
  invite public.house_invites%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  if p_user_id is null and recipient is null then raise exception 'Missing recipient'; end if;
  if p_user_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
    if exists(select 1 from public."case" where owner_id = p_user_id) then return null; end if;
  end if;
  if recipient is not null then
    perform pg_advisory_xact_lock(hashtextextended('house-invite-email:' || recipient,0));
  end if;
  select * into invite from public.house_invites i
  where (i.user_id = p_user_id or lower(btrim(i.email)) = recipient)
    and i.status in ('requested','pending','accepted')
  order by i.created_at limit 1 for update;
  if found then
    if invite.status <> 'pending' or not invite.email_delivery_pending
       or invite.delivery_lease_until > now() or lower(btrim(invite.email)) is distinct from recipient then return null; end if;
  else
    insert into public.house_invites(user_id,email,invited_by,status,email_delivery_pending)
    values (p_user_id,recipient,auth.uid(),'pending',recipient is not null)
    returning * into invite;
  end if;
  update public.house_invites set delivery_lease_until = now() + interval '2 minutes' where id = invite.id;
  return invite.id;
end;
$$;
revoke all on function public.prepare_house_invite(uuid,text) from public;
grant execute on function public.prepare_house_invite(uuid,text) to authenticated;
