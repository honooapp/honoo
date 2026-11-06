import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const uid = '00000000-0000-0000-0000-000000000001';
const other = '00000000-0000-0000-0000-000000000002';
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
try {
  await db.exec(`
    create role authenticated;
    create schema auth;
    create function auth.uid() returns uuid language sql as $$ select '${uid}'::uuid $$;
    create function public.is_admin() returns boolean language sql as $$ select false $$;
    create table honoo(id uuid primary key, user_id uuid, destination text, is_from_moon_saved boolean default false, conversation_id text, reply_to uuid, created_at timestamptz default now());
    create table hinoo(id uuid primary key, user_id uuid, type text, is_from_moon_saved boolean default false, conversation_id text, reply_to uuid references hinoo(id), created_at timestamptz default now());
    create table conversation_tombstones(content_id uuid primary key, conversation_id text, source_kind text, original_created_at timestamptz);
    create table chest_hidden_conversations(user_id uuid, conversation_id text, primary key(user_id,conversation_id));
    create table house_access(hinoo_id uuid references hinoo(id), honoo_id uuid references honoo(id));
    alter table chest_hidden_conversations enable row level security;
    create policy read_hidden on chest_hidden_conversations for select to authenticated using (user_id=auth.uid());
    grant usage on schema public,auth to authenticated;
    grant select,delete on honoo,hinoo to authenticated;
    grant select,insert,update on chest_hidden_conversations to authenticated;
  `);
  for (const table of ['honoo','hinoo']) {
    const type = table === 'honoo' ? 'destination' : 'type';
    await db.exec(`alter table ${table} enable row level security;
      create policy read_content on ${table} for select to authenticated using (true);
      insert into ${table}(id,user_id,${type},conversation_id) values
      ('${id(11)}','${uid}','personal','thread'),
      ('${id(12)}','${other}','personal','thread'),
      ('${id(13)}','${uid}','moon','thread'),
      ('${id(14)}','${uid}','personal',null);
      insert into ${table}(id,user_id,${type},is_from_moon_saved,conversation_id)
      values ('${id(15)}','${uid}','personal',true,'saved');`);
  }
  // Use disjoint ids across kinds, like the production UUIDs.
  await db.exec(`update hinoo set id = case right(id::text,2) when '11' then '${id(21)}'::uuid when '12' then '${id(22)}'::uuid when '13' then '${id(23)}'::uuid when '14' then '${id(24)}'::uuid else '${id(25)}'::uuid end;
    update hinoo set reply_to='${id(21)}' where id='${id(22)}';
    insert into house_access values ('${id(21)}','${id(11)}');`);
  await db.exec(await readFile(new URL('../supabase/migrations/20261106140000_allow_own_chest_honoo_deletion.sql',import.meta.url),'utf8'));
  await db.exec(`
    create trigger protect_honoo before delete on honoo for each row execute function protect_conversation_content_deletion();
    create trigger protect_hinoo before delete on hinoo for each row execute function protect_conversation_content_deletion();
    set role authenticated;
    delete from honoo;
    delete from hinoo;
    insert into chest_hidden_conversations values ('${uid}','thread');
  `);
  await assert.rejects(() => db.exec(`insert into chest_hidden_conversations values ('${other}','thread')`), /row-level security/);
  await db.exec('reset role');
  for (const table of ['honoo','hinoo']) assert.equal((await db.query(`select * from ${table}`)).rows.length,2);
  const tombstones = (await db.query('select * from conversation_tombstones')).rows;
  assert.equal(tombstones.length,2, 'Only conversation content leaves placeholders');
  assert.ok(tombstones.every(t => t.deleted_by_owner));
  assert.equal((await db.query('select reply_to from hinoo where id=$1',[id(22)])).rows[0].reply_to,id(21),'Foreign reply survives with its parent link');
  assert.deepEqual((await db.query('select * from house_access')).rows,[{hinoo_id:null,honoo_id:null}]);
  // A permissive legacy policy must not bypass the ownership trigger.
  await db.exec('create policy legacy_delete on honoo for delete to authenticated using (true); set role authenticated;');
  await assert.rejects(() => db.exec(`delete from honoo where id='${id(12)}'`), /own chest content/);
  console.log('Chest deletion: both kinds, ownership, saved copies, Moon protection, placeholders, reply links, house links and private conversation removal passed');
} finally { await db.close(); }
