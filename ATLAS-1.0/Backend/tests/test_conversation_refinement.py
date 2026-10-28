import sqlite3
import unittest
from atlas.memory import MemoryIndex

class ConversationRefinementTests(unittest.TestCase):
    def test_context_enforces_answer_discipline(self):
        from atlas.agent import Agent, Request
        from unittest.mock import Mock
        agent = Agent(Mock(), {}, Mock())
        req = Request(system='Du bist Atlas.', history=[])
        context = agent.context(req, 'Nur die Reihenfolge')
        system = context[0]['content']
        self.assertIn('ausschließlich die Reihenfolge', system)
        self.assertIn('höchstens zwei Sätzen', system)
        self.assertIn('widersprüchlich', system)


    def test_unrelated_memories_not_inserted(self):
        idx = MemoryIndex(lambda: sqlite3.connect(':memory:'))
        selected, method = idx.relevant('Wie funktioniert ein Fahrrad?', ['Ich studiere Statistik', 'Ich spiele Fußball'], 8)
        self.assertEqual(selected, [])
        self.assertEqual(method, 'lexikalisch')

    def test_related_memory_still_available(self):
        idx = MemoryIndex(lambda: sqlite3.connect(':memory:'))
        selected, _ = idx.relevant('Wie läuft mein Statistik Studium?', ['Ich studiere Statistik', 'Ich spiele Fußball'], 8)
        self.assertEqual(selected, ['Ich studiere Statistik'])

if __name__ == '__main__': unittest.main()
