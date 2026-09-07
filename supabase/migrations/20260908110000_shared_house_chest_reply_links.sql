-- Keep replies to shared chest content linked to the original conversation.
create or replace function public.get_shared_house_chest(p_owner_id uuid)
returns table(kind text, data jsonb, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  allowed_modes text[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct granted.mode), '{}'::text[])
  into allowed_modes
  from public.house_access ha
  join public."case" c
    on c.campanello_hinoo_id::text = ha.target_house_tag
  cross join lateral unnest(ha.share_modes) as granted(mode)
  where ha.visitor_id = auth.uid()
    and ha.granted_at is not null
    and c.owner_id = p_owner_id;

  if coalesce(array_length(allowed_modes, 1), 0) = 0 then
    raise exception 'House access not granted' using errcode = '42501';
  end if;

  return query
  select shared.kind, shared.data, shared.created_at
  from (
    select
      'honoo'::text as kind,
      jsonb_build_object(
        'id', h.id,
        'conversation_id', h.conversation_id,
        'text', h.text,
        'image_url', h.image_url,
        'destination', h.destination,
        'created_at', h.created_at,
        'updated_at', h.updated_at,
        'user_id', h.user_id,
        'is_from_moon_saved', h.is_from_moon_saved
      ) as data,
      h.created_at
    from public.honoo h
    where h.user_id = p_owner_id
      and h.destination = 'chest'
      and (
        'all' = any(allowed_modes)
        or ('home' = any(allowed_modes) and not coalesce(h.is_from_moon_saved, false))
        or ('moon' = any(allowed_modes) and coalesce(h.is_from_moon_saved, false))
      )

    union all

    select
      'hinoo'::text as kind,
      jsonb_build_object(
        'id', h.id,
        'conversation_id', h.conversation_id,
        'pages', h.pages,
        'type', h.type,
        'created_at', h.created_at,
        'user_id', h.user_id,
        'is_from_moon_saved', h.is_from_moon_saved
      ) as data,
      h.created_at
    from public.hinoo h
    where h.user_id = p_owner_id
      and h.type = 'personal'::public.hinoo_type
      and (
        'all' = any(allowed_modes)
        or ('home' = any(allowed_modes) and not coalesce(h.is_from_moon_saved, false))
        or ('moon' = any(allowed_modes) and coalesce(h.is_from_moon_saved, false))
      )
  ) shared
  order by shared.created_at desc;
end;
$$;

revoke all on function public.get_shared_house_chest(uuid) from public;
grant execute on function public.get_shared_house_chest(uuid)
  to authenticated;
