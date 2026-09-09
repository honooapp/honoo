// Isolated PostgreSQL regression test. Install @electric-sql/pglite outside the
// repo, then set PGLITE_MODULE to its dist/index.js and run this script.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create table auth.users (id uuid primary key);
    create function auth.uid() returns uuid language sql as
      $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
    create table public.users(auth_user_id uuid, is_admin boolean);
    create function public.admin_is_admin() returns boolean language sql security definer as
      $$ select exists(select 1 from public.users where auth_user_id = auth.uid() and is_admin is true) $$;
    create table public.honoo(id uuid primary key, user_id uuid, destination text, created_at timestamptz default now(), is_from_moon_saved boolean default false);
    create table public.hinoo(id uuid primary key, user_id uuid, type text, created_at timestamptz default now(), is_from_moon_saved boolean default false);
    create table public.house_invites(id uuid, user_id uuid, status text);
    create table public."case"(id uuid, owner_id uuid);
    create publication supabase_realtime;
  `);
  const admin = '00000000-0000-0000-0000-000000000001';
  const user = '00000000-0000-0000-0000-000000000002';
  const other = '00000000-0000-0000-0000-000000000003';
  await db.exec(`insert into auth.users values ('${admin}'),('${user}'),('${other}');
    insert into public.users values ('${admin}',true),('${user}',false),('${other}',false);`);
  const login = async id => db.query("select set_config('request.jwt.claim.sub', $1, false)", [id]);
  await db.exec(await readFile(new URL('../supabase/migrations/20260909160000_live_admin_statistics.sql', import.meta.url), 'utf8'));
  const snapshot = async () => (await db.query('select public.admin_statistics_snapshot() s')).rows[0].s;
  await login(user);
  await assert.rejects(snapshot, /Not authorized/);
  await db.exec('select public.record_activity(); select public.increment_site_visit();');
  await login(admin);
  await db.exec('select public.record_activity(); select public.increment_site_visit();');
  assert.equal((await db.query('select count(*) n from public.analytics_activity')).rows[0].n, 1);
  assert.equal((await db.query('select sum(count) n from public.analytics_visits')).rows[0].n, '1');
  await db.exec(`insert into public.honoo(id,user_id,destination) values
    ('10000000-0000-0000-0000-000000000001','${admin}','chest'),
    ('10000000-0000-0000-0000-000000000002','${user}','chest'),
    ('10000000-0000-0000-0000-000000000003','${user}','moon'),
    ('10000000-0000-0000-0000-000000000004','${user}','reply');
    insert into public.hinoo(id,user_id,type) values
    ('20000000-0000-0000-0000-000000000001','${admin}','personal'),
    ('20000000-0000-0000-0000-000000000002','${user}','personal'),
    ('20000000-0000-0000-0000-000000000003','${user}','moon'),
    ('20000000-0000-0000-0000-000000000004','${user}','answer');
    insert into public.honoo(id,user_id,destination,is_from_moon_saved) values
    ('10000000-0000-0000-0000-000000000005','${user}','chest',true);
    insert into public."case" values ('30000000-0000-0000-0000-000000000001','${user}'),('30000000-0000-0000-0000-000000000002','${admin}');`);
  await db.exec(`insert into public.house_invites select gen_random_uuid(), '${user}', 'requested' from generate_series(1,1200);
    insert into public.house_invites values (gen_random_uuid(),'${admin}','requested');`);
  assert.equal((await db.query('select public.admin_pending_invite_count() n')).rows[0].n, 1200);
  const romeDate = (await db.query("select (now() at time zone 'Europe/Rome')::date::text d")).rows[0].d;
  let stats = await snapshot();
  assert.equal(stats.today, romeDate);
  assert.equal((await db.query('select * from public.admin_moon_counts_today()')).rows[0].honoo_count, 1);
  assert.equal((await db.query('select * from public.admin_daily_content_counts()')).rows[0].reply_hinoo, 1);
  assert.equal(stats.active_users, 1);
  assert.equal(stats.registered_users, 2);
  assert.equal(stats.houses, 1);
  assert.equal(stats.visits[stats.today], 1);
  assert.deepEqual(stats.daily, {chest_honoo:1,chest_hinoo:1,moon_honoo:1,moon_hinoo:1,reply_honoo:1,reply_hinoo:1});
  await db.exec("delete from public.honoo where destination='reply'; update public.hinoo set created_at = now();");
  assert.deepEqual((await snapshot()).daily, stats.daily, 'deletion/edit must not undo or duplicate recorded events');
  await db.exec("update public.analytics_activity set last_seen_at = now() - interval '3 minutes'");
  assert.equal((await snapshot()).active_users, 0);
  await db.exec(`insert into public.honoo(id,user_id,destination)
    select gen_random_uuid(), '${user}', 'moon' from generate_series(1,1200)`);
  assert.equal((await snapshot()).daily.moon_honoo, 1201, 'SQL aggregation must not stop at the REST row limit');
  await db.exec(`update public.users set is_admin = true where auth_user_id='${user}'`);
  stats = await snapshot();
  assert.deepEqual(stats.daily, {});
  assert.equal(stats.visits[stats.today], 0);
  assert.equal(stats.registered_users, 1);
  assert.equal(stats.houses, 0);
  assert.ok((await db.query('select revision from public.admin_stats_signal')).rows[0].revision > 0);
  await db.exec('set role anon');
  await assert.rejects(snapshot, /permission denied/);
  await assert.rejects(() => db.exec('select * from public.analytics_visits'), /permission denied/);
  await db.exec('reset role');
  await login(other);
  await db.exec('set role authenticated');
  assert.equal((await db.query('select * from public.admin_stats_signal')).rows.length, 0);
  await assert.rejects(() => db.exec('insert into public.analytics_visits values (gen_random_uuid(),current_date,100)'), /permission denied/);
  console.log('Admin statistics SQL: counts, admin exclusion, activity expiry, event persistence and access controls passed.');
} finally {
  await db.close();
}
