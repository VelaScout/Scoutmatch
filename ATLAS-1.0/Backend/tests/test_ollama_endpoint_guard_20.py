"""Local privacy boundary: Ollama must never silently send prompts off-device."""
import unittest
from atlas.llm import Ollama, ModelError, require_loopback_ollama


class LocalEndpointTests(unittest.TestCase):
    def test_accept_loopback(self):
        for url in ('http://127.0.0.1:11434', 'http://localhost:9999/', 'http://[::1]:11434'):
            self.assertEqual(Ollama(base=url).base, url.rstrip('/'))

    def test_reject_remote_or_ambiguous(self):
        urls = ('https://127.0.0.1:11434', 'http://example.com:11434',
                'http://192.168.1.5:11434', 'http://127.0.0.1.evil.com:11434',
                'http://user:pass@localhost:11434', 'http://localhost:11434/api',
                'http://localhost:11434/?key=secret', 'http://localhost:11434/#fragment',
                'http://localhost', 'http://localhost:99999', 'http://localhost:0',
                'file:///tmp/ollama.sock', 'http://localhost:11434@evil.com:80')
        for url in urls:
            with self.subTest(url=url), self.assertRaises(ModelError):
                require_loopback_ollama(url)


if __name__ == '__main__':
    unittest.main()
