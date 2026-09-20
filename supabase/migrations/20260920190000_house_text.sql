begin;
alter table public."case" add column if not exists house_text text not null default '';
-- The public Campanelli presentation shows only the real houses belonging to
-- the two project administrators. Keep the allow-list inside this
-- security-definer function so anonymous clients cannot inspect auth.users or
-- enumerate any other house.

drop function public.get_public_admin_campanelli();
create function public.get_public_admin_campanelli()
returns table (
  admin_email text,
  campanello_hinoo_id uuid,
  owner_id uuid,
  house_image_url text,
  house_text text,
  house_bg_transform jsonb,
  created_at timestamptz,
  pages jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $$
  with requested(email, position) as (
    values
      ('venceslao.cembalo@gmail.com'::text, 1),
      ('mariandreealavric@gmail.com'::text, 2)
  )
  select
    requested.email as admin_email,
    houses.campanello_hinoo_id,
    houses.owner_id,
    houses.house_image_url,
    houses.house_text,
    houses.bg_transform as house_bg_transform,
    houses.created_at,
    campanelli.pages
  from requested
  join auth.users accounts
    on lower(accounts.email) = requested.email
  join public."case" houses
    on houses.owner_id = accounts.id
  join public.hinoo campanelli
    on campanelli.id = houses.campanello_hinoo_id
  order by requested.position;
$$;

revoke all on function public.get_public_admin_campanelli() from public;
grant execute on function public.get_public_admin_campanelli() to anon, authenticated;

commit;
