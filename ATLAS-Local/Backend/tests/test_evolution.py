"""Learning & Evolution: Wissensaufbau, Verbesserungsmotor, Code-Werkstatt, Lernplaner, Anbindung.

Echt: SQLite, Dateien, Testläufe in isolierten Kopien (eigene Python-Prozesse), Sicherung/Rücksetzen,
Agentenablauf. Simuliert: das Sprachmodell (FakeOllama), Websuche und Webseiten (feste Texte).
"""
import contextlib
import json
import sqlite3
import sys
import tempfile
import threading
import unittest
from pathlib import Path

from atlas import agent as a
from atlas import llm
from atlas.approvals import Approvals
from atlas.evolution import Evolution, Scheduler, learning_intent
from atlas.improvement import Improvement
from atlas.knowledge import Knowledge, grounded
from atlas.learning import Learning
from atlas.tools import Environment, build_tools
from atlas.workshop import Workshop, WorkshopError
from fake_ollama import FakeOllama, answer


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.ollama = FakeOllama()
        self.addCleanup(self.ollama.close)
        self.llm = llm.Ollama(base=self.ollama.url)

    @contextlib.contextmanager
    def connect(self):
        db = sqlite3.connect(self.root / 'atlas.db')
        try:
            with db:
                yield db
        finally:
            db.close()


def failure(tool='read_file', output='Datei nicht gefunden'):
    return a.Action(tool, tool, tool, False, False, output)


# ---------------------------------------------------------------------------------------------
# Wissensaufbau
# ---------------------------------------------------------------------------------------------
PAGE_A = ('Die Unternehmensbewertung ermittelt den Wert eines Unternehmens. Das Discounted-Cashflow-Verfahren '
          'diskontiert zukünftige freie Cashflows mit den Kapitalkosten (WACC). Das Multiplikatorverfahren vergleicht '
          'Kennzahlen wie EBIT mit ähnlichen börsennotierten Unternehmen. ' * 3)
PAGE_B = ('Beim Discounted-Cashflow-Verfahren werden zukünftige freie Cashflows mit den Kapitalkosten diskontiert. '
          'Das Ertragswertverfahren nach IDW S1 ist in Deutschland für gutachterliche Bewertungen üblich. '
          'Multiplikatoren sind für Gutachten ungeeignet, meint der Autor. ' * 3)


class KnowledgeTests(Base):
    def make(self, pages=None, search_error=None):
        pages = pages or {'https://a.example/bewertung': PAGE_A, 'https://b.example/dcf': PAGE_B}

        def search(query):
            if search_error:
                raise search_error
            return [{'title': url.split('/')[2], 'url': url, 'snippet': ''} for url in pages]
        return Knowledge(self.connect, self.llm, search=search, fetch=lambda url: pages[url])

    def extract(self, *facts, questions=()):
        return answer(json.dumps({'facts': [{'statement': s, 'kind': k} for s, k in facts], 'open_questions': list(questions)}))

    def test_learns_with_sources_rejects_unsupported_and_finds_agreement_and_conflict(self):
        knowledge = self.make()
        self.ollama.script = [
            self.extract(('Das Discounted-Cashflow-Verfahren diskontiert zukünftige freie Cashflows mit den Kapitalkosten.', 'methode'),
                         ('Das Multiplikatorverfahren vergleicht Kennzahlen wie EBIT mit börsennotierten Unternehmen.', 'methode'),
                         ('Die Bewertung dauert immer genau drei Wochen und kostet 5000 Euro.', 'zahl'),    # steht nicht im Text
                         questions=['Wie wird der Kapitalisierungszins bestimmt?']),
            self.extract(('Beim Discounted-Cashflow-Verfahren werden zukünftige freie Cashflows mit den Kapitalkosten diskontiert.', 'methode'),
                         ('Das Ertragswertverfahren nach IDW S1 ist in Deutschland für gutachterliche Bewertungen üblich.', 'fakt'),
                         ('Multiplikatoren sind für Gutachten ungeeignet.', 'meinung')),
            answer(json.dumps({'conflicts': [[2, 4]]})),
        ]
        result = knowledge.learn('Unternehmensbewertung', 'qwen3:4b')
        self.assertEqual((result['status'], result['sources'], result['rejected']), ('gelernt', 2, 1))
        facts = {f['statement']: f for f in knowledge.facts(result['topic_id'])}
        self.assertFalse(any('drei Wochen' in s for s in facts))                         # erfundene Aussage verworfen
        dcf = facts['Das Discounted-Cashflow-Verfahren diskontiert zukünftige freie Cashflows mit den Kapitalkosten.']
        self.assertEqual((dcf['status'], dcf['support']), ('mehrfach_belegt', 2))
        self.assertEqual(facts['Multiplikatoren sind für Gutachten ungeeignet.']['status'], 'widerspruch')
        self.assertEqual(facts['Das Multiplikatorverfahren vergleicht Kennzahlen wie EBIT mit börsennotierten Unternehmen.']['status'],
                         'widerspruch')
        self.assertEqual(facts['Das Ertragswertverfahren nach IDW S1 ist in Deutschland für gutachterliche Bewertungen üblich.']['source_url'],
                         'https://b.example/dcf')
        self.assertIn('Wie wird der Kapitalisierungszins bestimmt?', knowledge.topics()[0]['gaps'])
        context = knowledge.context_for('Wie funktioniert das Discounted-Cashflow-Verfahren bei der Unternehmensbewertung?')
        self.assertIn('Quelle: a.example', context)
        self.assertIn('abgerufen', context)
        self.assertEqual(knowledge.context_for('Wie wird das Wetter morgen?'), '')

    def test_offline_is_reported_not_invented(self):
        knowledge = self.make(search_error=OSError('offline'))
        result = knowledge.learn('Photovoltaik', 'qwen3:4b')
        self.assertEqual(result['status'], 'fehlgeschlagen')
        self.assertIn('offline', result['note'])
        self.assertEqual(self.ollama.chat_requests(), [])

    def test_facts_can_be_corrected_and_deleted(self):
        knowledge = self.make()
        self.ollama.script = [self.extract(('Die Unternehmensbewertung ermittelt den Wert eines Unternehmens.', 'definition')),
                              self.extract(), answer('{"conflicts": []}')]
        topic = knowledge.learn('Unternehmensbewertung', 'qwen3:4b')['topic_id']
        fact = knowledge.facts(topic)[0]
        self.assertTrue(knowledge.edit_fact(fact['id'], status='vermutung'))
        self.assertEqual(knowledge.facts(topic)[0]['edited'], 1)
        self.assertTrue(knowledge.delete('topic', topic))
        self.assertEqual(knowledge.topics(), [])
        self.assertGreater(grounded('Wert eines Unternehmens', PAGE_A), 0.9)


# ---------------------------------------------------------------------------------------------
# Verbesserungsmotor
# ---------------------------------------------------------------------------------------------
class ImprovementTests(Base):
    def setUp(self):
        super().setUp()
        self.learning = Learning(self.connect)
        self.approvals = Approvals(self.connect)

    def fail_twice(self):
        for name in ('a.pdf', 'b.pdf'):
            self.learning.record(f'Lies {name}', 'agent', 'm', [failure()], True, 3.0)

    def test_repeated_error_becomes_proposal_and_rule_after_approval(self):
        engine = Improvement(self.connect, self.learning, self.approvals)
        self.fail_twice()
        [proposal] = engine.analyze()
        self.assertIn('bessere Methode', self.approvals.get(proposal)['title'])
        self.assertEqual(engine.analyze(), [])                                # kein doppelter Vorschlag
        self.assertNotIn('list_directory', self.learning.context_for('Hallo', rules_only=True))   # ohne Freigabe nicht aktiv
        self.assertEqual(self.approvals.decide(proposal, True)['status'], 'aktiv')
        self.assertIn('list_directory', self.learning.context_for('Hallo', rules_only=True))

    def test_failed_improvement_is_rolled_back_automatically(self):
        engine = Improvement(self.connect, self.learning, self.approvals)
        self.fail_twice()
        [proposal] = engine.analyze()
        self.approvals.decide(proposal, True)
        self.fail_twice()                                                     # Fehler tritt weiter auf
        self.assertEqual(engine.review(min_days=0), ['read_file:pfad'])
        self.assertEqual(engine.list()[0]['status'], 'zurueckgesetzt')
        self.assertEqual(self.approvals.get(proposal)['status'], 'zurueckgesetzt')
        self.assertEqual(self.learning.context_for('Hallo', rules_only=True), '')   # Regel ist wieder aus

    def test_helpful_improvement_stays(self):
        engine = Improvement(self.connect, self.learning, self.approvals)
        self.fail_twice()
        [proposal] = engine.analyze()
        self.approvals.decide(proposal, True)
        self.learning.record('Lies c.pdf', 'agent', 'm', [a.Action('read_file', 'r', 'r', True, True, 'ok')], True, 2.0)
        self.assertEqual(engine.review(min_days=0), [])
        self.assertEqual(engine.list()[0]['status'], 'aktiv')

    def test_hint_that_measures_worse_is_not_proposed_and_rejected_stays_rejected(self):
        engine = Improvement(self.connect, self.learning, self.approvals, evaluate=lambda hint: 0.5 if hint else 0.75)
        self.fail_twice()
        self.assertEqual(engine.analyze(), [])
        engine.evaluate = lambda hint: 0.8 if hint else 0.75
        [proposal] = engine.analyze()
        self.assertEqual(self.approvals.get(proposal)['detail']['evaluation'], {'ohne': 0.75, 'mit': 0.8})
        self.approvals.decide(proposal, False)
        self.assertEqual(engine.analyze(), [])
        self.assertEqual(engine.list()[0]['status'], 'abgelehnt')


# ---------------------------------------------------------------------------------------------
# Code-Werkstatt
# ---------------------------------------------------------------------------------------------
class WorkshopTests(Base):
    def setUp(self):
        super().setUp()
        self.project = self.root / 'Backend'
        (self.project / 'atlas').mkdir(parents=True)
        (self.project / 'tests').mkdir()
        (self.project / 'atlas' / '__init__.py').write_text('')
        (self.project / 'atlas' / 'rechnen.py').write_text('def brutto(netto):\n    return netto * 1.19\n')
        (self.project / 'atlas' / 'tools.py').write_text('ERLAUBT = ["ls"]\n')
        (self.project / 'tests' / 'test_rechnen.py').write_text(
            'import unittest\nfrom atlas.rechnen import brutto\n\nclass T(unittest.TestCase):\n'
            '    def test_brutto(self):\n        self.assertAlmostEqual(brutto(100), 119)\n\n'
            '    def test_null(self):\n        self.assertEqual(brutto(0), 0)\n')
        self.approvals = Approvals(self.connect)
        self.checks = []
        self.workshop = Workshop(self.connect, self.project, self.root / 'werkstatt', self.approvals,
                                 verify=self.verify, allow_unsandboxed=True, timeout=60)
        self.original = (self.project / 'atlas' / 'rechnen.py').read_text()

    def verify(self, root):
        self.checks.append(root)
        return self.verify_problem if hasattr(self, 'verify_problem') else ''

    def good_edit(self):
        return [{'file': 'atlas/rechnen.py', 'old': 'return netto * 1.19', 'new': 'return round(netto * 1.19, 2)'}]

    def test_tested_change_is_applied_only_after_approval_and_can_be_rolled_back(self):
        change = self.workshop.propose('Brutto runden', self.good_edit())
        self.assertEqual(change['status'], 'getestet', change['output'])
        self.assertEqual((self.project / 'atlas' / 'rechnen.py').read_text(), self.original)    # noch unverändert
        self.assertEqual(self.approvals.decide(change['proposal'], True)['status'], 'aktiv')
        self.assertIn('round(', (self.project / 'atlas' / 'rechnen.py').read_text())
        self.assertIn('wiederhergestellt', self.workshop.rollback(change['id']))
        self.assertEqual((self.project / 'atlas' / 'rechnen.py').read_text(), self.original)

    def test_change_with_failing_tests_is_discarded(self):
        change = self.workshop.propose('Falsch', [{'file': 'atlas/rechnen.py', 'old': '1.19', 'new': '1.07'}])
        self.assertEqual(change['status'], 'verworfen')
        self.assertIn('FAILED', change['output'])
        self.assertEqual(self.approvals.pending(), [])
        self.assertEqual((self.project / 'atlas' / 'rechnen.py').read_text(), self.original)

    def test_removing_or_skipping_tests_is_refused(self):
        tests = (self.project / 'tests' / 'test_rechnen.py').read_text()
        removed = self.workshop.propose('Test weg', [{'file': 'tests/test_rechnen.py', 'old': tests, 'new': tests.split('    def test_null')[0]}])
        self.assertEqual(removed['status'], 'verworfen')
        skipped = self.workshop.propose('Test aus', [{'file': 'tests/test_rechnen.py', 'old': '    def test_brutto',
                                                      'new': '    @unittest.skip("egal")\n    def test_brutto'}])
        self.assertEqual(skipped['status'], 'verworfen')
        self.assertIn('nicht entfernt oder übersprungen', skipped['output'])

    def test_failed_check_after_apply_restores_automatically(self):
        change = self.workshop.propose('Brutto runden', self.good_edit())
        self.verify_problem = 'ImportError: kaputt'
        decided = self.approvals.decide(change['proposal'], True)
        self.assertEqual(decided['status'], 'fehlgeschlagen')
        self.assertIn('automatisch zurückgesetzt', decided['result'])
        self.assertEqual((self.project / 'atlas' / 'rechnen.py').read_text(), self.original)

    def test_security_files_are_flagged_and_need_extra_confirmation(self):
        evolution = Evolution(self.connect, Learning(self.connect), self.llm, self.root / 'data', self.project)
        evolution.workshop = self.workshop
        change = self.workshop.propose('Mehr Befehle', [{'file': 'atlas/tools.py', 'old': '["ls"]', 'new': '["ls", "rm"]'}])
        self.assertTrue(change['security_relevant'])
        with self.assertRaises(ValueError):
            evolution.decide(change['proposal'], True)                 # ohne ausdrückliche Sicherheitsbestätigung
        self.assertEqual((self.project / 'atlas' / 'tools.py').read_text(), 'ERLAUBT = ["ls"]\n')
        self.assertIn('Sicherheitsbereiche', evolution.announcements()[0]['text'])

    def test_only_backend_files_are_editable_and_sandbox_is_required(self):
        with self.assertRaises(WorkshopError):
            self.workshop.propose('x', [{'file': '../../etc/passwd', 'new': 'x'}])
        with self.assertRaises(WorkshopError):
            self.workshop.propose('x', [{'file': 'Scripts/install.sh', 'new': 'x'}])
        strict = Workshop(self.connect, self.project, self.root / 'w2', self.approvals, allow_unsandboxed=False)
        if not __import__('shutil').which('sandbox-exec'):
            result = strict.propose('Brutto runden', self.good_edit())
            self.assertEqual(result['status'], 'verworfen')
            self.assertIn('Sandbox', result['output'])


# ---------------------------------------------------------------------------------------------
# Lernplaner
# ---------------------------------------------------------------------------------------------
class SchedulerTests(Base):
    def setUp(self):
        super().setUp()
        self.busy = False
        self.scheduler = Scheduler(self.connect, busy=lambda: self.busy)
        self.calls = []
        self.scheduler.register('analyse', lambda p, stop: self.calls.append('analyse') or {'ok': True})
        self.scheduler.register('topic', lambda p, stop: self.calls.append(p['topic']) or {'ok': True}, network=True)

    def test_cycles_only_when_enabled(self):
        self.assertFalse(self.scheduler.cycle())
        self.scheduler.update(enabled=True)
        self.assertTrue(self.scheduler.cycle())
        self.assertFalse(self.scheduler.cycle())                      # erst nach cycle_hours wieder
        self.assertEqual(self.scheduler.run_next()['status'], 'fertig')
        self.assertEqual(self.calls, ['analyse'])

    def test_pause_busy_network_and_budget_limits(self):
        self.scheduler.submit('topic', {'topic': 'A'})
        self.scheduler.update(paused=True)
        self.assertIsNone(self.scheduler.run_next())
        self.scheduler.update(paused=False)
        self.busy = True
        self.assertIsNone(self.scheduler.run_next())                  # ATLAS antwortet gerade → warten
        self.busy = False
        self.scheduler.update(allow_network=False)
        self.assertIsNone(self.scheduler.run_next())
        self.assertEqual(self.scheduler.jobs()[0]['status'], 'blockiert')
        self.assertEqual(self.calls, [])
        with self.connect() as db:                                     # Tagesbudget der Zyklen aufgebraucht
            db.execute("INSERT INTO evolution_jobs(kind,payload,origin,status,created_at,started_at,seconds) "
                       "VALUES ('analyse','{}','zyklus','fertig',datetime('now'),?,?)",
                       (__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(), 99999))
        self.scheduler.submit('analyse', {'x': 1}, origin='zyklus')
        self.assertIsNone(self.scheduler.run_next())
        with self.assertRaises(ValueError):
            self.scheduler.update(max_minutes_per_day=100000)

    def test_errors_and_restarts_are_recorded_honestly(self):
        self.scheduler.register('skill', lambda p, stop: 1 / 0)
        self.scheduler.submit('skill', {'description': 'x'})
        self.assertEqual(self.scheduler.run_next()['status'], 'fehlgeschlagen')
        self.assertIn('ZeroDivisionError', self.scheduler.jobs()[0]['result']['error'])
        with self.connect() as db:
            db.execute("UPDATE evolution_jobs SET status='läuft'")
        Scheduler(self.connect)                                         # Neustart
        self.assertEqual(self.scheduler.jobs()[0]['status'], 'abgebrochen')


# ---------------------------------------------------------------------------------------------
# Anbindung an den Agenten und den Server
# ---------------------------------------------------------------------------------------------
class IntegrationTests(Base):
    def setUp(self):
        super().setUp()
        self.home = self.root / 'home'
        (self.home / 'Documents').mkdir(parents=True)
        env = Environment(home=self.home, roots=[self.home], is_mac=False)
        self.learning = Learning(self.connect)
        self.evolution = Evolution(self.connect, self.learning, self.llm, self.root / 'data', self.root,
                                   model=lambda: 'qwen3:4b')
        self.agent = a.Agent(self.llm, build_tools(env), a.Bridge(), learning=self.learning,
                             limits=a.Limits(max_rounds=4, seconds=20, native_timeout=2))
        self.agent.evolution = self.evolution
        self.agent.dynamic_tools = lambda: self.evolution.tools(env)

    def ask(self, text):
        request = a.Request(system='Du bist ATLAS.', history=[{'role': 'user', 'content': text}])
        return list(self.agent.run(request, threading.Event()))

    def test_intents(self):
        self.assertEqual(learning_intent('Atlas, lerne alles über Unternehmensbewertung.'),
                         ('learn_topic', {'topic': 'Unternehmensbewertung'}))
        self.assertEqual(learning_intent('Lerne, wie man PowerPoint-Präsentationen erstellt')[0], 'learn_skill')
        self.assertEqual(learning_intent('Informiere dich über das Thema Photovoltaik')[1], {'topic': 'Photovoltaik'})
        self.assertIsNone(learning_intent('Wie geht es dir?'))
        self.assertIsNone(learning_intent('Lerne Spanisch'))

    def test_learning_request_queues_job_and_does_not_claim_the_skill(self):
        events = self.ask('Lerne, wie man PowerPoint-Präsentationen erstellt')
        text = ''.join(e.get('text', '') for e in events if e['type'] == 'delta')
        self.assertIn('Bis dahin beherrsche ich sie noch nicht', text)
        job = self.evolution.scheduler.jobs()[0]
        self.assertEqual((job['kind'], job['status']), ('skill', 'wartet'))
        self.assertEqual(self.ollama.chat_requests(), [])              # kein Modellaufruf nötig

    def test_knowledge_flows_into_answers_with_source(self):
        with self.connect() as db:
            topic = db.execute("INSERT INTO knowledge_topics(topic,status,created_at,updated_at) VALUES "
                               "('Unternehmensbewertung','gelernt','x','x')").lastrowid
            db.execute("INSERT INTO knowledge_facts(topic_id,statement,kind,status,source_url,source_title,retrieved_at) VALUES "
                       "(?,?,?,?,?,?,?)", (topic, 'Das Ertragswertverfahren nach IDW S1 ist in Deutschland üblich.', 'fakt',
                                           'belegt', 'https://b.example/idw', 'IDW-Leitfaden', '2026-10-21'))
        self.ollama.stream_text = ['Nach IDW S1 …']
        self.ask('Welches Verfahren ist bei der Unternehmensbewertung in Deutschland üblich?')
        prompt = [r for p, r in self.ollama.requests if p == '/api/chat' and r.get('stream')][-1]['messages'][0]['content']
        self.assertIn('IDW-Leitfaden', prompt)
        self.assertIn('[belegt]', prompt)

    def test_overview_and_announcements(self):
        self.learning.record('Lies a.pdf', 'agent', 'm', [failure()], True, 3.0)
        self.learning.record('Lies b.pdf', 'agent', 'm', [failure()], True, 3.0)
        self.evolution.scheduler.submit('analyse', {})
        self.assertEqual(self.evolution.scheduler.run_next()['status'], 'fertig')
        overview = self.evolution.overview()
        json.dumps(overview)
        self.assertEqual(overview['history'][-1]['tasks'], 2)
        self.assertTrue(overview['announcements'][0]['text'].startswith('Ich habe eine bessere Methode gefunden'))
        self.assertFalse(overview['settings']['enabled'])               # Lernzyklen sind anfangs aus


class ServerRouteTests(Base):
    def test_learning_api(self):
        from atlas import server as s
        saved = (s.DATA, s.DB, s._LEARNING, s._EVOLUTION, s._ENV)
        s.DATA, s.DB, s._LEARNING, s._EVOLUTION, s._ENV = self.root, self.root / 'atlas.db', None, None, \
            Environment(home=self.root, roots=[self.root], is_mac=False)
        try:
            self.assertFalse(s.learning_route('overview', {})['settings']['enabled'])
            self.assertTrue(s.learning_route('settings', {'enabled': True, 'unbekannt': 1})['enabled'])
            job = s.learning_route('job', {'kind': 'topic', 'text': 'Photovoltaik'})['job']
            self.assertTrue(s.learning_route('cancel', {'id': job})['ok'])
            rule = s.learning().learn_correction('Nein, speichere ab jetzt immer in Dokumente.')['rule']
            self.assertTrue(s.learning_route('rule', {'id': rule, 'active': False})['ok'])
            self.assertTrue(s.learning_route('delete', {'kind': 'rules', 'id': rule})['ok'])
            for bad in [('decide', {'id': 'x', 'approved': True}), ('delete', {'kind': 'sqlite_master', 'id': 1}),
                        ('settings', {'paused': 'ja'}), ('gibtsnicht', {})]:
                with self.subTest(bad=bad[0]), self.assertRaises(ValueError):
                    s.learning_route(*bad)
        finally:
            s.DATA, s.DB, s._LEARNING, s._EVOLUTION, s._ENV = saved


if __name__ == '__main__':
    unittest.main()
