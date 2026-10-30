"""ATLAS offline readiness audit. No model calls, no network, no secret reads."""
from __future__ import annotations
import argparse
import json
from pathlib import Path


def audit(root: Path) -> dict:
    root = root.resolve()
    checks = []
    def check(name, path, token=None):
        target = root / path
        exists = target.is_file()
        present = exists and (token is None or token in target.read_text(encoding='utf-8', errors='replace'))
        checks.append({'name': name, 'passed': bool(present), 'path': path})
    check('Swift conversation engine', 'ATLAS/Core/Conversation/ConversationEngine.swift', 'handleBargeIn')
    check('Swift speech recognition', 'ATLAS/Core/Speech/SpeechRecognizer.swift')
    check('Swift audio hub', 'ATLAS/Core/Speech/AudioHub.swift')
    check('Local Ollama provider', 'ATLAS/Core/AI/LocalAtlasProvider.swift', '127.0.0.1')
    check('Python local model connector', 'Backend/atlas/llm.py', 'is_local_model')
    check('Optional Claude cloud integration', 'Backend/atlas/cloud.py', 'class Cloud:')
    check('Cloud tests', 'Backend/tests/test_cloud.py')
    check('Memory module', 'Backend/atlas/memory.py')
    check('Tool execution module', 'Backend/atlas/agent.py')
    check('Local model benchmark', 'Backend/atlas/intelligence_benchmark.py', 'safe_local_url')
    check('macOS build script', 'BAUEN.command')
    return {'checks': checks, 'passed': sum(c['passed'] for c in checks), 'total': len(checks),
            'disclaimer': 'Static file checks only. No macOS build, voice test, model benchmark, or capability validation.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = audit(args.root)
    rendered = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output: args.output.write_text(rendered + '\n', encoding='utf-8')
    print(rendered)
    return 0 if result['passed'] == result['total'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
