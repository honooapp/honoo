-- Secure email invite claims and keep one active house authorization per user.

-- Reconcile legacy duplicates before enforcing the invariant. Prefer an
-- accepted invitation, then a pending invitation, then a user request.
with ranked as (
  select id,
         row_number() over (
           partition by user_id
           order by case status
             when 'accepted' then 0
             when 'pending' then 1
             else 2
           end, created_at, id
         ) as position
  from public.house_invites
  where user_id is not null
    and status in ('requested', 'pending', 'accepted')
)
update public.house_invites invite
set status = 'declined'
from ranked
where invite.id = ranked.id
  and ranked.position > 1;

with ranked as (
  select id,
         row_number() over (
           partition by lower(btrim(email))
           order by case status when 'accepted' then 0 else 1 end,
                    created_at, id
         ) as position
  from public.house_invites
  where user_id is null
    and nullif(btrim(email), '') is not null
    and status in ('pending', 'accepted')
)
update public.house_invites invite
set status = 'declined'
from ranked
where invite.id = ranked.id
  and ranked.position > 1;

create unique index if not exists house_invites_one_active_per_user
  on public.house_invites (user_id)
  where user_id is not null
    and status in ('requested', 'pending', 'accepted');

create unique index if not exists house_invites_one_open_email
  on public.house_invites (lower(btrim(email)))
  where user_id is null
    and nullif(btrim(email), '') is not null
    and status in ('pending', 'accepted');

create or replace function public.claim_house_invite_by_email(p_email text)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  requester_id uuid := auth.uid();
  authenticated_email text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
  requested_email text := lower(btrim(coalesce(p_email, '')));
  target_id uuid;
begin
  if requester_id is null then
    raise exception 'Not authenticated';
  end if;
  if authenticated_email = '' then
    raise exception 'Authenticated email is required';
  end if;
  if requested_email = '' or requested_email <> authenticated_email then
    raise exception 'Invite email does not match authenticated user';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(requester_id::text, 0));
  perform pg_advisory_xact_lock(
    hashtextextended('house-invite-email:' || authenticated_email, 0)
  );

  select id into target_id
  from public.house_invites
  where user_id is null
    and lower(btrim(email)) = authenticated_email
    and status in ('pending', 'accepted')
  order by case status when 'accepted' then 0 else 1 end, created_at, id
  limit 1
  for update;

  if target_id is null then
    return 0;
  end if;

  -- An administrator's invitation supersedes the user's earlier request.
  update public.house_invites
  set status = 'declined'
  where user_id = requester_id
    and status = 'requested';

  if exists (
    select 1 from public.house_invites
    where user_id = requester_id
      and status in ('pending', 'accepted')
  ) then
    update public.house_invites set status = 'declined' where id = target_id;
    return 0;
  end if;

  update public.house_invites
  set user_id = requester_id,
      email = authenticated_email
  where id = target_id;

  return 1;
end;
$$;

revoke all on function public.claim_house_invite_by_email(text) from public;
grant execute on function public.claim_house_invite_by_email(text) to authenticated;

create or replace function public.request_house_invite(p_email text default null)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  requester_id uuid := auth.uid();
  authenticated_email text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
  requested_email text := lower(btrim(coalesce(p_email, '')));
begin
  if requester_id is null then
    raise exception 'Not authenticated';
  end if;
  if authenticated_email = '' then
    raise exception 'Authenticated email is required';
  end if;
  if requested_email <> '' and requested_email <> authenticated_email then
    raise exception 'Request email does not match authenticated user';
  end if;
  if public.is_admin() then
    raise exception 'Administrators cannot request a house invitation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(requester_id::text, 0));
  perform pg_advisory_xact_lock(
    hashtextextended('house-invite-email:' || authenticated_email, 0)
  );

  if exists (select 1 from public."case" where owner_id = requester_id) then
    return false;
  end if;

  -- Claim an invitation that was sent before this account requested access.
  perform public.claim_house_invite_by_email(authenticated_email);

  if exists (
    select 1 from public.house_invites
    where user_id = requester_id
      and status in ('requested', 'pending', 'accepted')
  ) then
    return false;
  end if;

  insert into public.house_invites (user_id, email, invited_by, status)
  values (requester_id, authenticated_email, null, 'requested');
  return true;
end;
$$;

revoke all on function public.request_house_invite(text) from public;
grant execute on function public.request_house_invite(text) to authenticated;

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
    where id = p_invite_id;
    return true;
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

-- Clear any stale request after the house was successfully created so it can
-- never remain in the administrator badge.
create or replace function public.clear_house_requests_after_creation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.house_invites
  set status = 'declined'
  where user_id = new.owner_id
    and status = 'requested';
  return new;
end;
$$;

revoke all on function public.clear_house_requests_after_creation() from public;
drop trigger if exists clear_house_requests_after_creation on public."case";
create trigger clear_house_requests_after_creation
after insert on public."case"
for each row execute function public.clear_house_requests_after_creation();
