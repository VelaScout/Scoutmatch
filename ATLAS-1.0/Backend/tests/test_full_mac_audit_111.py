import tempfile, unittest
from pathlib import Path
from atlas.full_mac_audit import audit

class FullMacAuditTests(unittest.TestCase):
    def test_offline_does_not_fake_success(self):
        with tempfile.TemporaryDirectory() as d:
            r=audit(d,skip_live=True,skip_unit=True)
            self.assertEqual(r['domain_counts']['PASS'],0)
            self.assertEqual(r['domain_counts']['BLOCKED'],12)
            self.assertEqual(r['domain_counts']['REVIEW'],28)
            self.assertTrue((Path(d)/'GESAMTBERICHT.md').is_file())
            self.assertIn('Keine ChatGPT-Gleichwertigkeit',r['comparison'])

if __name__=='__main__':unittest.main()
