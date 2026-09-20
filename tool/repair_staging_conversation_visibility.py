"""Explicit manual repair of participant SELECT policies on the E2E database.

Uses the management API because staging has no configured direct DB password.
Never prints tokens, URLs, row data, or SQL response bodies on failure.
"""
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request


def main():
    url = os.environ['HONOO_SUPABASE_URL']
    match = re.fullmatch(r'https://([a-z0-9]+)\.supabase\.co/?', url)
    if not match:
        raise SystemExit('Expected a hosted Supabase staging URL')
    token = os.environ['SUPABASE_ACCESS_TOKEN']
    endpoint = f'https://api.supabase.com/v1/projects/{match[1]}/database/query'

    def query(sql):
        request = urllib.request.Request(endpoint,
            data=json.dumps({'query': sql}).encode(),
            headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise SystemExit(f'Staging management query failed: HTTP {error.code}') from None

    diagnostic = """select tablename, policyname, permissive, cmd
        from pg_policies where schemaname = 'public'
        and tablename in ('honoo', 'hinoo') and cmd in ('SELECT', 'ALL')
        order by tablename, policyname"""
    print('SELECT policies before repair:', json.dumps(query(diagnostic)))
    migration = Path(__file__).resolve().parent.parent / 'supabase/migrations/20260805120000_restore_conversation_participant_visibility.sql'
    query('begin;\n' + migration.read_text() + '\ncommit;')
    print('SELECT policies after repair:', json.dumps(query(diagnostic)))
    print('Participant policies restored. The live CRUD/RLS/Realtime test must now pass.')


if __name__ == '__main__':
    main()
