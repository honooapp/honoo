// Isolated PostgreSQL regression test. Install @electric-sql/pglite outside the
// repo, then set PGLITE_MODULE to its dist/index.js and run this script.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();

const admin = '00000000-0000-0000-0000-000000000001';
const alice = '00000000-0000-0000-0000-000000000002';
const bob = '00000000-0000-0000-0000-000000000003';
const carol = '00000000-0000-0000-0000-000000000004';
const dave = '00000000-0000-0000-0000-000000000005';

try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create table auth.users (id uuid primary key, email text);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.jwt() returns jsonb language sql stable as
      $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
    create table public.users(auth_user_id uuid primary key, is_admin boolean not null default false);
    create function public.is_admin() returns boolean language sql security definer as
      $$ select exists(select 1 from public.users where auth_user_id = auth.uid() and is_admin is true) $$;
    create table public.house_invites(
      id uuid primary key default gen_random_uuid(),
      email text,
      user_id uuid,
      invited_by uuid,
      status text not null,
      created_at timestamptz not null default now()
    );
    create table public."case"(
      id uuid primary key default gen_random_uuid(),
      owner_id uuid not null unique
    );
  `);

  await db.exec(`
    insert into auth.users values
      ('${admin}', 'admin@example.test'),
      ('${alice}', 'alice@example.test'),
      ('${bob}', 'bob@example.test'),
      ('${carol}', 'carol@example.test'),
      ('${dave}', 'dave@example.test');
    insert into public.users values
      ('${admin}', true),
      ('${alice}', false),
      ('${bob}', false),
      ('${carol}', false),
      ('${dave}', false);

    insert into public.house_invites(email, user_id, status, created_at) values
      ('alice@example.test', '${alice}', 'requested', now() - interval '2 days'),
      ('alice@example.test', null, 'pending', now() - interval '1 day'),
      ('carol@example.test', null, 'pending', now() - interval '2 days'),
      (' CAROL@example.test ', null, 'pending', now() - interval '1 day');
  `);

  await db.exec(await readFile(
    new URL('../supabase/migrations/20260914120000_secure_house_invite_flow.sql', import.meta.url),
    'utf8',
  ));

  const login = async (id, email) => {
    await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id]);
    await db.query("select set_config('request.jwt.claims', $1, false)", [
      JSON.stringify({ sub: id, email }),
    ]);
  };
  const scalar = async (sql, params = []) => (await db.query(sql, params)).rows[0];

  assert.equal(
    (await scalar(`select count(*)::int n from public.house_invites
      where lower(btrim(email)) = 'carol@example.test' and user_id is null
        and status in ('pending', 'accepted')`)).n,
    1,
    'legacy open-email duplicates must be reconciled',
  );

  await login(bob, 'bob@example.test');
  await assert.rejects(
    () => db.query("select public.claim_house_invite_by_email('alice@example.test')"),
    /does not match authenticated user/,
  );

  await login(alice, 'alice@example.test');
  assert.equal(
    (await scalar("select public.claim_house_invite_by_email('ALICE@example.test') n")).n,
    1,
  );
  assert.equal(
    (await scalar(`select count(*)::int n from public.house_invites
      where user_id = $1 and status in ('requested', 'pending', 'accepted')`, [alice])).n,
    1,
    'claiming an admin invitation must close the stale request',
  );
  assert.equal(
    (await scalar(`select count(*)::int n from public.house_invites
      where user_id = $1 and status = 'requested'`, [alice])).n,
    0,
  );

  await login(carol, 'carol@example.test');
  assert.equal(
    (await scalar("select public.request_house_invite('carol@example.test') n")).n,
    false,
    'a request must claim an existing email invitation instead of inserting another row',
  );
  assert.equal(
    (await scalar(`select count(*)::int n from public.house_invites
      where user_id = $1 and status in ('pending', 'accepted')`, [carol])).n,
    1,
  );

  await login(bob, 'bob@example.test');
  assert.equal((await scalar('select public.request_house_invite() n')).n, true);
  assert.equal((await scalar('select public.request_house_invite() n')).n, false);
  await assert.rejects(
    () => db.exec(`insert into public.house_invites(email, user_id, status)
      values ('bob@example.test', '${bob}', 'pending')`),
    /house_invites_one_active_per_user/,
  );

  await login(dave, 'dave@example.test');
  assert.equal((await scalar('select public.request_house_invite() n')).n, true);
  const daveRequest = await scalar(
    `select id from public.house_invites where user_id = $1 and status = 'requested'`,
    [dave],
  );
  await login(admin, 'admin@example.test');
  assert.equal(
    (await scalar('select public.admin_review_house_request($1, true) n', [daveRequest.id])).n,
    true,
  );
  assert.equal(
    (await scalar('select status from public.house_invites where id = $1', [daveRequest.id])).status,
    'pending',
  );

  const carolInvite = await scalar(
    `select id from public.house_invites where user_id = $1 and status = 'pending'`,
    [carol],
  );
  await db.query('update public.house_invites set status = $1 where id = $2', [
    'requested',
    carolInvite.id,
  ]);
  await db.query('insert into public."case"(owner_id) values ($1)', [carol]);
  assert.equal(
    (await scalar('select status from public.house_invites where id = $1', [carolInvite.id])).status,
    'declined',
    'house creation must clear a stale request from the admin counter',
  );

  console.log('House invite SQL: identity binding, deduplication, review and request cleanup passed.');
} finally {
  await db.close();
}
