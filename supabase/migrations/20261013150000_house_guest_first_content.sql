-- Use the visitor's first addressed content, including legacy approvals that
-- did not store a content id on house_access. Keep the permission row identity.
create or replace function public.get_house_guests(p_house_tag text)
returns table(id bigint, share_modes text[], honoo jsonb, hinoo jsonb)
language sql stable security definer set search_path = public, pg_temp
as $$
  select ha.id, ha.share_modes, first_content.honoo, first_content.hinoo
  from public.house_access ha
  join public."case" c on c.campanello_hinoo_id::text = ha.target_house_tag
  left join lateral (
    select sent.honoo, sent.hinoo
    from (
      select h.created_at, h.id, to_jsonb(h) as honoo, null::jsonb as hinoo
      from public.honoo h
      where h.user_id = ha.visitor_id and h.recipient_tag = ha.target_house_tag
      union all
      select x.created_at, x.id, null::jsonb, to_jsonb(x)
      from public.hinoo x
      where x.user_id = ha.visitor_id and x.recipient_tag = ha.target_house_tag
    ) sent
    order by sent.created_at asc nulls last, sent.id, (sent.honoo is null)
    limit 1
  ) first_content on true
  where c.owner_id = auth.uid() and ha.target_house_tag = p_house_tag
    and ha.granted_at is not null
  order by ha.created_at desc, ha.id desc;
$$;
revoke all on function public.get_house_guests(text) from public;
grant execute on function public.get_house_guests(text) to authenticated;
