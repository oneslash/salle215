#!/usr/bin/env python3
"""Read-only Langfuse API checks. Credentials are loaded from .env, never printed."""
import datetime as dt
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
env = os.environ.copy()
for line in (root / '.env').read_text().splitlines():
    line = line.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    name, value = line.removeprefix('export ').split('=', 1)
    parts = shlex.split(value, comments=True)
    env[name.strip()] = parts[0] if parts else ''
env['LANGFUSE_HOST'] = env.get('LANGFUSE_BASE_URL', env.get('LANGFUSE_HOST', ''))
secrets = [env.get(name, '') for name in ('LANGFUSE_PUBLIC_KEY', 'LANGFUSE_SECRET_KEY')]

def run(resource, action, *args):
    result = subprocess.run(['npx', '--yes', 'langfuse-cli', 'api', resource, action, *args, '--json'],
                            env=env, capture_output=True, text=True, timeout=90)
    if result.returncode:
        message = result.stderr or result.stdout
        for secret in secrets:
            if secret:
                message = message.replace(secret, '[redacted]')
        print(message[:1500], file=sys.stderr)
        sys.exit(result.returncode)
    payload = json.loads(result.stdout)
    # The CLI returns an envelope; unwrap it without printing project data.
    if 'data' in payload and isinstance(payload['data'], dict):
        payload = payload['data']
    if payload.get('status', 200) >= 400:
        print('HTTP', payload['status'], 'Retry-After:', payload.get('headers', {}).get('retry-after'))
        sys.exit(1)
    return payload.get('body', payload)

now = dt.datetime.now(dt.timezone.utc)
query = dict(view='observations', dimensions=[dict(field='level')],
             metrics=[dict(measure='count', aggregation='count'), dict(measure='totalCost', aggregation='sum')],
             filters=[], fromTimestamp=(now-dt.timedelta(days=7)).isoformat(), toTimestamp=now.isoformat(),
             config=dict(row_limit=1000))
queries = [('activity', dict(query, timeDimension=dict(granularity='day'), orderBy=[dict(field='time_dimension', direction='asc')])),
 ('roots', dict(query, dimensions=[], metrics=[dict(measure='count',aggregation='count'),dict(measure='latency',aggregation='p95')], filters=[dict(column='isRootObservation', type='boolean', operator='=', value=True)])),
 ('trend', dict(query, dimensions=[], metrics=[dict(measure='count',aggregation='count'),dict(measure='latency',aggregation='p95')], filters=[dict(column='isRootObservation', type='boolean', operator='=', value=True)],timeDimension=dict(granularity='day'))),
 ('scores', dict(query, view='scores-numeric', dimensions=[dict(field='name'),dict(field='dataType')], metrics=[dict(measure='value',aggregation='avg'),dict(measure='count',aggregation='count')]))]
for name, query in queries:
    payload = run('metrics','get','--query',json.dumps(query))
    rows = payload['data']
    print(name, 'rows', len(rows), 'columns', sorted(rows[0]) if rows else [], 'types', {k:type(v).__name__ for k,v in rows[0].items()} if rows else {})
    if rows and 'time_dimension' in rows[0]:
        print('Time bucket format:', rows[0]['time_dimension'])
for resource, args in [('observations',['--limit','2','--fields','core,basic,io,usage,prompt,trace_context','--from-start-time',(now-dt.timedelta(days=7)).isoformat(),'--to-start-time',now.isoformat()]),('scores',['--limit','2','--fields','details,subject']),('prompts',['--page','1','--limit','2'])]:
    body=run(resource,'list',*args)
    rows=body['data']
    print(resource, 'rows',len(rows),'columns', sorted(rows[0]) if rows else [],'meta',list(body.get('meta',{})))
    if resource=='prompts' and rows:
        prompt=run('prompts','get',rows[0]['name'],'--version',str(max(rows[0]['versions'])),'--no-resolve')
        print('prompt version columns',sorted(prompt),'prompt type',type(prompt['prompt']).__name__)

# The narrower presets and lazy breakdowns have different SQL shapes.
base = queries[0][1]
for granularity, seconds in [('minute',3600),('hour',86400)]:
    query=dict(base,fromTimestamp=(now-dt.timedelta(seconds=seconds)).isoformat(),timeDimension=dict(granularity=granularity))
    rows=run('metrics','get','--query',json.dumps(query))['data']
    print(granularity, 'rows',len(rows),'bucket',rows[0]['time_dimension'] if rows else 'empty')
for dimension, measure, aggregation in [('name','count','count'),('traceName','latency','p95'),('providedModelName','totalCost','sum')]:
    query=dict(base,dimensions=[dict(field=dimension)],metrics=[dict(measure=measure,aggregation=aggregation)])
    query.pop('timeDimension',None);query.pop('orderBy',None)
    rows=run('metrics','get','--query',json.dumps(query))['data']
    print('breakdown',dimension,'rows',len(rows))
