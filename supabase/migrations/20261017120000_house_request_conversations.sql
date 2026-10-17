create or replace function public.is_conversation_participant(
  target_conversation_id text
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.honoo h
    where h.conversation_id = target_conversation_id
      and (
        h.user_id = auth.uid()
        or h.recipient_tag = auth.uid()::text
        or h.recipient_tag in (select c.campanello_hinoo_id::text from public."case" c where c.owner_id = auth.uid())
        or h.recipient_tag in (
          select u.address
          from public.users u
          where u.auth_user_id = auth.uid()
        )
      )
    union all
    select 1
    from public.hinoo x
    where x.conversation_id = target_conversation_id
      and (
        x.user_id = auth.uid()
        or x.recipient_tag = auth.uid()::text
        or x.recipient_tag in (select c.campanello_hinoo_id::text from public."case" c where c.owner_id = auth.uid())
        or x.recipient_tag in (
          select u.address
          from public.users u
          where u.auth_user_id = auth.uid()
        )
      )
  );
$$;

revoke all on function public.is_conversation_participant(text) from public;
grant execute on function public.is_conversation_participant(text)
  to authenticated;


-- Pending requests use their exact content; approved guests retain their first message.
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
       and (ha.granted_at is not null or h.id = ha.honoo_id)
     union all
     select h.created_at, h.id, null::jsonb, to_jsonb(h)
     from public.hinoo h where h.user_id = ha.visitor_id
       and h.recipient_tag = ha.target_house_tag
       and (ha.granted_at is not null or h.id = ha.hinoo_id)
   ) sent order by sent.created_at asc nulls last, sent.id, (sent.honoo is null) limit 1
 ) content on true
 where c.owner_id = auth.uid()
   and (p_house_tag is null or ha.target_house_tag = p_house_tag)
 order by (ha.granted_at is not null), ha.created_at asc, ha.id asc;
$$;
revoke all on function public.get_house_inbox(text) from public;
grant execute on function public.get_house_inbox(text) to authenticated;
