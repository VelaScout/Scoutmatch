"""Offline, auditable manual evidence ledger for the ATLAS ten-domain suite.

Never automatically promote subjective tests or trust a bare PASS assertion.
"""
from __future__ import annotations
import argparse, datetime, hashlib, json, pathlib, sys
from .equivalence_suite import CASES, DOMAINS, summarize

CASE_IDS={c[0] for c in CASES}

def review(results_path, ledger_path, output_path):
    results_path=pathlib.Path(results_path); ledger_path=pathlib.Path(ledger_path)
    report=json.loads(results_path.read_text(encoding='utf-8'))
    ledger=json.loads(ledger_path.read_text(encoding='utf-8'))
    entries=ledger.get('reviews', [])
    if not isinstance(entries,list): raise ValueError('reviews must be an array')
    seen=set(); changes=[]
    for entry in entries:
        cid=entry.get('id'); verdict=entry.get('verdict'); reviewer=str(entry.get('reviewer','')).strip()
        rationale=str(entry.get('rationale','')).strip(); path=str(entry.get('evidence_file','')).strip()
        if cid not in CASE_IDS or cid in seen: raise ValueError(f'Unknown or duplicate case: {cid}')
        seen.add(cid)
        if verdict not in ('PASS','FAIL'): raise ValueError(f'Invalid verdict for {cid}')
        if not reviewer or len(rationale)<20 or not path: raise ValueError(f'Missing reviewer, detailed rationale, or evidence for {cid}')
        target=(ledger_path.parent/pathlib.Path(path)).resolve()
        if not target.is_file() or not target.stat().st_size: raise ValueError(f'Evidence missing/empty for {cid}: {target}')
        row=next(r for r in report['results'] if r['id']==cid)
        if row['method']!='manual' or row['status']!='REVIEW':
            raise ValueError(f'{cid} is not an open manual case')
        digest=hashlib.sha256(target.read_bytes()).hexdigest()
        row['status']=verdict; row['reason']=rationale
        row['evidence']={'file':str(target),'sha256':digest,'reviewer':reviewer,'reviewed_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
        changes.append(cid)
    report['domains']=summarize(report['results'])
    report['manual_reviewed']=changes
    report['comparison']='No ChatGPT equivalence established: independent matched baseline and repeated blind assessments required.'
    output_path=pathlib.Path(output_path); output_path.parent.mkdir(parents=True,exist_ok=True)
    output_path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    return changes

def main(argv=None):
    p=argparse.ArgumentParser(description='Attach evidence-backed human judgments to open manual tests')
    p.add_argument('--results',required=True);p.add_argument('--ledger',required=True);p.add_argument('--out',required=True)
    a=p.parse_args(argv)
    print('Reviewed:', ', '.join(review(a.results,a.ledger,a.out)) or 'none')
    return 0
if __name__=='__main__':sys.exit(main())
