-- Server-owned statistics. Legacy anonymous daily totals cannot be attributed.
create table public.analytics_activity (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null default now()
);
create table public.analytics_visits (
  user_id uuid not null references auth.users(id) on delete cascade,
  visit_date date not null,
  count bigint not null default 1,
  primary key (user_id, visit_date)
);
-- Preserve creation/send events even when the source content is later deleted.
-- Backfill can only recover source rows that still exist.
create table public.analytics_content_events (
  kind text not null check (kind in ('honoo', 'hinoo')),
  content_id uuid not null,
  destination text not null,
  user_id uuid not null,
  occurred_at timestamptz not null,
  primary key (kind, content_id, destination)
);
alter table public.analytics_content_events enable row level security;
revoke all on public.analytics_content_events from anon, authenticated;
create index analytics_content_events_date on public.analytics_content_events(occurred_at);

create function public.record_content_event() returns trigger
language plpgsql security definer set search_path = public as $$
declare dest text; payload jsonb := to_jsonb(new);
begin
  if new.user_id is null or exists (
    select 1 from public.users where auth_user_id = new.user_id and is_admin is true
  ) then return new; end if;
  dest := case when tg_table_name = 'honoo' then payload->>'destination'
    when payload->>'type' = 'personal' then 'chest'
    when payload->>'type' = 'answer' then 'reply' else payload->>'type' end;
  if dest is null or coalesce((payload->>'is_from_moon_saved')::boolean, false) then return new; end if;
  if tg_op = 'UPDATE' then
    if (to_jsonb(old)->>'destination') is not distinct from (payload->>'destination')
      and (to_jsonb(old)->>'type') is not distinct from (payload->>'type') then return new; end if;
  end if;
  insert into public.analytics_content_events(kind, content_id, destination, user_id, occurred_at)
  values (tg_table_name, new.id, dest, new.user_id, now())
  on conflict do nothing;
  return new;
end;
$$;
revoke all on function public.record_content_event() from public;
create trigger record_honoo_event after insert or update on public.honoo
for each row execute function public.record_content_event();
create trigger record_hinoo_event after insert or update on public.hinoo
for each row execute function public.record_content_event();
insert into public.analytics_content_events
select 'honoo', id, destination::text, user_id, created_at from public.honoo h
where user_id is not null and destination is not null and created_at is not null
  and not coalesce((to_jsonb(h)->>'is_from_moon_saved')::boolean, false)
  and not exists (select 1 from public.users u where u.auth_user_id = h.user_id and u.is_admin is true)
union all
select 'hinoo', id, case when type::text = 'personal' then 'chest' when type::text = 'answer' then 'reply' else type::text end, user_id, created_at from public.hinoo h
where user_id is not null and type is not null and created_at is not null
  and not coalesce((to_jsonb(h)->>'is_from_moon_saved')::boolean, false)
  and not exists (select 1 from public.users u where u.auth_user_id = h.user_id and u.is_admin is true)
on conflict do nothing;

create table public.admin_stats_signal (
  id boolean primary key default true check (id),
  revision bigint not null default 0,
  tracking_started_at timestamptz not null default now()
);
insert into public.admin_stats_signal(id) values (true);
alter table public.analytics_activity enable row level security;
alter table public.analytics_visits enable row level security;
alter table public.admin_stats_signal enable row level security;
revoke all on public.analytics_activity, public.analytics_visits, public.admin_stats_signal from anon, authenticated;
grant select on public.admin_stats_signal to authenticated;
create policy admin_stats_signal_read on public.admin_stats_signal for select to authenticated
using (public.admin_is_admin());

create function public.notify_admin_stats_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.admin_stats_signal set revision = revision + 1 where id;
  return null;
end;
$$;
revoke all on function public.notify_admin_stats_change() from public;
create trigger admin_stats_auth_changed after insert or update or delete on auth.users
for each statement execute function public.notify_admin_stats_change();
DO $$
declare source text;
begin
  foreach source in array array['honoo', 'hinoo', 'users', 'analytics_activity', 'analytics_visits', 'house_invites', 'case'] loop
    execute format('create trigger admin_stats_changed after insert or update or delete on public.%I for each statement execute function public.notify_admin_stats_change()', source);
  end loop;
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.admin_stats_signal;
  end if;
end;
$$;

create function public.record_activity() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.admin_is_admin() then return; end if;
  insert into public.analytics_activity(user_id) values (auth.uid())
  on conflict (user_id) do update set last_seen_at = now()
  where analytics_activity.last_seen_at < now() - interval '20 seconds';
end;
$$;
revoke all on function public.record_activity() from public;
grant execute on function public.record_activity() to authenticated;

create or replace function public.increment_site_visit() returns integer
language plpgsql security definer set search_path = public as $$
declare result bigint;
begin
  if auth.uid() is null or public.admin_is_admin() then return 0; end if;
  insert into public.analytics_visits(user_id, visit_date)
  values (auth.uid(), (now() at time zone 'Europe/Rome')::date)
  on conflict (user_id, visit_date) do update set count = analytics_visits.count + 1
  returning count into result;
  return least(result, 2147483647)::integer;
end;
$$;

create function public.admin_statistics_snapshot() returns jsonb
language plpgsql security definer set search_path = public as $$
declare result jsonb;
begin
  if not public.admin_is_admin() then raise exception 'Not authorized'; end if;
  with bounds as (
    select (now() at time zone 'Europe/Rome')::date as today,
      date_trunc('day', now() at time zone 'Europe/Rome') at time zone 'Europe/Rome' as start_at
  ), excluded as (
    select auth_user_id as id from public.users where is_admin is true
  ), content as (
    select kind, destination, occurred_at as created_at, user_id from public.analytics_content_events
  ), counts as (
    select kind, destination, count(*) as n from content, bounds
    where created_at >= start_at and created_at <= now()
      and user_id is not null and not exists (select 1 from excluded where id = user_id)
    group by kind, destination
  )
  select jsonb_build_object(
    'generated_at', now(),
    'tracking_started_at', (select tracking_started_at from public.admin_stats_signal where id),
    'tracking_started_date', (select (tracking_started_at at time zone 'Europe/Rome')::date from public.admin_stats_signal where id),
    'today', bounds.today,
    'active_users', (select count(*) from public.analytics_activity a where last_seen_at > now() - interval '2 minutes' and not exists (select 1 from excluded where id = a.user_id)),
    'registered_users', (select count(*) from auth.users u where not exists (select 1 from excluded where id = u.id)),
    'houses', (select count(*) from public."case" c where owner_id is not null and not exists (select 1 from excluded where id = c.owner_id)),
    'visits', (select coalesce(jsonb_object_agg(d::date::text, coalesce(v.n,0)), '{}'::jsonb)
      from generate_series(bounds.today - 2, bounds.today, interval '1 day') d
      left join (select visit_date, sum(count) n from public.analytics_visits a
        where not exists (select 1 from excluded where id = a.user_id) group by visit_date) v on v.visit_date = d::date),
    'daily', (select coalesce(jsonb_object_agg(destination || '_' || kind, n), '{}'::jsonb) from counts)
  ) into result from bounds;
  return result;
end;
$$;
revoke all on function public.admin_statistics_snapshot() from public;
grant execute on function public.admin_statistics_snapshot() to authenticated;

-- Older clients use the same filtered source, never the legacy anonymous totals.
create or replace function public.admin_daily_content_counts()
returns table (chest_honoo integer, chest_hinoo integer, moon_honoo integer, moon_hinoo integer, reply_honoo integer, reply_hinoo integer)
language plpgsql security definer set search_path = public as $$
declare daily jsonb := public.admin_statistics_snapshot()->'daily';
begin
  return query select
    coalesce((daily->>'chest_honoo')::integer,0), coalesce((daily->>'chest_hinoo')::integer,0),
    coalesce((daily->>'moon_honoo')::integer,0), coalesce((daily->>'moon_hinoo')::integer,0),
    coalesce((daily->>'reply_honoo')::integer,0), coalesce((daily->>'reply_hinoo')::integer,0);
end;
$$;
create or replace function public.admin_moon_counts_today()
returns table (honoo_count integer, hinoo_count integer)
language plpgsql security definer set search_path = public as $$
declare daily jsonb := public.admin_statistics_snapshot()->'daily';
begin
  return query select coalesce((daily->>'moon_honoo')::integer,0), coalesce((daily->>'moon_hinoo')::integer,0);
end;
$$;
create or replace function public.admin_list_site_visits(p_days int default 3)
returns table (visit_date date, count integer)
language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_is_admin() then raise exception 'Not authorized'; end if;
  return query select v.visit_date, least(sum(v.count),2147483647)::integer
  from public.analytics_visits v
  where v.visit_date >= (now() at time zone 'Europe/Rome')::date - (greatest(1, least(p_days, 365)) - 1)
    and not exists (select 1 from public.users u where u.auth_user_id = v.user_id and u.is_admin is true)
  group by v.visit_date order by v.visit_date desc;
end;
$$;

create or replace function public.admin_pending_invite_count()
returns bigint language plpgsql security definer set search_path = public as $$
begin
  if not public.admin_is_admin() then raise exception 'Not authorized'; end if;
  return (select count(*) from public.house_invites i
    where i.status = 'requested'
      and not exists (select 1 from public.users u where u.auth_user_id = i.user_id and u.is_admin is true));
end;
$$;
revoke all on function public.admin_pending_invite_count() from public;
grant execute on function public.admin_pending_invite_count() to authenticated;
