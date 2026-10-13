-- Only a visitor's own, addressed content can introduce a new knock.
-- Existing knocks without content remain readable and manageable.
drop policy if exists "House access insert" on public.house_access;
create policy "House access insert" on public.house_access
for insert to authenticated with check (
  visitor_id = auth.uid()
  and granted_at is null
  and cardinality(share_modes) = 0
  and exists (
    select 1 from public."case" c
    where c.campanello_hinoo_id::text = target_house_tag
      and c.owner_id <> auth.uid()
  )
  and (
    (honoo_id is not null and hinoo_id is null and exists (
      select 1 from public.honoo h where h.id = honoo_id
        and h.user_id = auth.uid() and h.recipient_tag = target_house_tag
    ))
    or (hinoo_id is not null and honoo_id is null and exists (
      select 1 from public.hinoo h where h.id = hinoo_id
        and h.user_id = auth.uid() and h.recipient_tag = target_house_tag
    ))
  )
);

create or replace function public.get_house_guests(p_house_tag text)
returns table(id bigint, share_modes text[], honoo jsonb, hinoo jsonb)
language sql stable security definer set search_path = public, pg_temp
as $$
  select ha.id, ha.share_modes, to_jsonb(h), to_jsonb(x)
  from public.house_access ha
  join public."case" c on c.campanello_hinoo_id::text = ha.target_house_tag
  left join public.honoo h on h.id = ha.honoo_id
  left join public.hinoo x on x.id = ha.hinoo_id
  where c.owner_id = auth.uid() and ha.target_house_tag = p_house_tag
    and ha.granted_at is not null
  order by ha.created_at desc, ha.id desc;
$$;
revoke all on function public.get_house_guests(text) from public;
grant execute on function public.get_house_guests(text) to authenticated;

create or replace function public.update_house_guest_access(
  p_knock_id bigint, p_share_modes text[]
)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_share_modes is null or array_position(p_share_modes, null) is not null
    or not (p_share_modes <@ array['home', 'moon', 'all']::text[]) then
    raise exception 'Invalid house share modes' using errcode = '22023';
  end if;
  -- Keep granted_at as the approval history, including when all access is revoked.
  update public.house_access ha
  set share_modes = array(select distinct unnest(p_share_modes))
  where ha.id = p_knock_id and ha.granted_at is not null
    and exists (
      select 1 from public."case" c
      where c.campanello_hinoo_id::text = ha.target_house_tag
        and c.owner_id = auth.uid()
    );
  if not found then
    raise exception 'Guest not found or not owned by user' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public.update_house_guest_access(bigint, text[]) from public;
grant execute on function public.update_house_guest_access(bigint, text[]) to authenticated;
