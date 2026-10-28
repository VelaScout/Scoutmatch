import json, tempfile, unittest
from pathlib import Path
from atlas.evidence_review import review
from atlas.equivalence_suite import CASES, summarize

class EvidenceReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.results=self.root/'results.json';self.ledger=self.root/'ledger.json';self.out=self.root/'reviewed.json'
        rows=[dict(id=c[0],domain=c[1],method=c[3],status='REVIEW' if c[3]=='manual' else 'BLOCKED') for c in CASES]
        self.results.write_text(json.dumps(dict(results=rows,domains=summarize(rows))))
        (self.root/'proof.txt').write_text('An actual test log recorded by the reviewer')
    def record(self,**kw):
        d=dict(id='s01',verdict='PASS',reviewer='QA reviewer',rationale='Audio recording was checked against the original sentence.',evidence_file='proof.txt')
        d.update(kw);self.ledger.write_text(json.dumps({'reviews':[d]}))
    def test_verified_manual_case(self):
        self.record();self.assertEqual(review(self.results,self.ledger,self.out),['s01'])
        data=json.loads(self.out.read_text());r=next(x for x in data['results'] if x['id']=='s01')
        self.assertEqual(r['status'],'PASS');self.assertEqual(len(r['evidence']['sha256']),64)
    def test_no_evidence(self):
        self.record(evidence_file='missing.wav')
        with self.assertRaises(ValueError):review(self.results,self.ledger,self.out)
    def test_no_bare_pass(self):
        self.record(rationale='passed')
        with self.assertRaises(ValueError):review(self.results,self.ledger,self.out)
    def test_no_auto_override(self):
        self.record(id='i01')
        with self.assertRaises(ValueError):review(self.results,self.ledger,self.out)
    def test_no_duplicate(self):
        self.record();data=json.loads(self.ledger.read_text());data['reviews'].append(data['reviews'][0]);self.ledger.write_text(json.dumps(data))
        with self.assertRaises(ValueError):review(self.results,self.ledger,self.out)
    def test_no_invalid_status(self):
        self.record(verdict='BLOCKED')
        with self.assertRaises(ValueError):review(self.results,self.ledger,self.out)
    def test_no_unknown_case(self):
        self.record(id='unknown')
        with self.assertRaises(ValueError):review(self.results,self.ledger,self.out)
    def test_no_empty_evidence(self):
        (self.root/'empty.txt').touch();self.record(evidence_file='empty.txt')
        with self.assertRaises(ValueError):review(self.results,self.ledger,self.out)

if __name__=='__main__':unittest.main()
