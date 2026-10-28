"""ATLAS-Optimierung: das Beste aus diesem Mac herausholen – gemessen, nicht geraten.

Ablauf
1. Mac prüfen: Arbeitsspeicher, freier Platz, Ollama, installierte Modelle.
2. Passende Modelle für diesen Arbeitsspeicher vorschlagen (Denkmodelle, Bildmodell) und – nur nach Zustimmung –
   herunterladen. Kostenlos; es wird nur Speicherplatz belegt.
3. Jedes Denkmodell auf denselben schweren Aufgaben (Rechnen, Logik, Übersetzen) über ATLAS messen:
   richtige Antworten, Antwortzeit und ob der Mac dabei in den Auslagerungsspeicher muss (dann zu groß).
4. Das beste Modell, das auf diesem Mac flüssig läuft, in ~/.atlas-ai/settings.json eintragen
   (alte Einstellungen werden gesichert). Optional auch das Arbeitsmodell neu wählen (atlas.realtests --compare).
5. Bericht OPTIMIERUNG.md.

Es wird nichts gelöscht; Modelle bleiben installiert, bis Sie sie selbst entfernen (`ollama rm <name>`).
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import statistics
import subprocess
import sys
import time
import urllib.request

import atlas_gesamtpruefung as g

OLLAMA = os.environ.get('OLLAMA_URL', 'http://127.0.0.1:11434')
SETTINGS = pathlib.Path.home() / '.atlas-ai' / 'settings.json'

# Ungefähre Downloadgröße (GB, Ollama-Standardquantisierung) und Speicherbedarf beim Laufen.
GROESSE = {'qwen3:4b': 2.6, 'qwen3:8b': 5.2, 'qwen3:14b': 9.3, 'qwen3:30b': 19.0, 'qwen3:32b': 20.0, 'gemma3:4b': 3.3,
           'gemma3:12b': 8.1, 'qwen2.5vl:7b': 6.0}

# Mess-Aufgaben: die schwersten des Katalogs (Denkfallen, Textaufgaben, Logik, Übersetzung, Wiederholung).
MESSUNG = ['r01', 'r05', 'r06', 'r07', 'l04', 'l06', 'l10', 'e03', 'z02']


def plan_fuer(ram_gb: float) -> dict:
    """Welche Modelle auf diesem Mac sinnvoll sind (Ollama braucht neben dem Modell Platz für macOS und Apps)."""
    if ram_gb < 12:
        return {'denken': ['qwen3:4b'], 'bild': 'gemma3:4b'}
    if ram_gb < 24:          # z. B. MacBook Pro M4 mit 16 GB
        return {'denken': ['qwen3:4b', 'qwen3:8b', 'qwen3:14b'], 'bild': 'gemma3:4b'}
    if ram_gb < 48:
        return {'denken': ['qwen3:8b', 'qwen3:14b', 'qwen3:30b'], 'bild': 'qwen2.5vl:7b'}
    return {'denken': ['qwen3:14b', 'qwen3:30b', 'qwen3:32b'], 'bild': 'gemma3:12b'}


def ram_gb() -> float:
    try:
        return int(subprocess.run(['sysctl', '-n', 'hw.memsize'], capture_output=True, text=True, timeout=5).stdout) / 2**30
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return 0.0


def frei_gb() -> float:
    return shutil.disk_usage(pathlib.Path.home()).free / 1e9


def swap_mb() -> float:
    """Belegter Auslagerungsspeicher (macOS). Steigt er beim Messen stark, ist das Modell zu groß für den Mac."""
    try:
        text = subprocess.run(['sysctl', '-n', 'vm.swapusage'], capture_output=True, text=True, timeout=5).stdout
        found = re.search(r'used\s*=\s*([\d.,]+)([MG])', text)
        if not found:
            return 0.0
        value = float(found.group(1).replace(',', '.'))
        return value * (1024 if found.group(2) == 'G' else 1)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return 0.0


def dienst_version() -> str:
    try:
        with urllib.request.urlopen(g.BASE + '/api/native/session', timeout=5) as response:
            return str(json.load(response).get('version', ''))
    except (OSError, ValueError):
        return ''


def mindestens(version: str, needed: str = '1.0.3') -> bool:
    try:
        return tuple(int(x) for x in version.split('.')) >= tuple(int(x) for x in needed.split('.'))
    except ValueError:
        return False


def installiert() -> list[str]:
    try:
        with urllib.request.urlopen(OLLAMA + '/api/tags', timeout=5) as response:
            return [m['name'] for m in json.load(response).get('models', [])]
    except (OSError, ValueError):
        return []


def vorhanden(name: str, names: list[str]) -> bool:
    return name in names or f'{name}:latest' in names


def laden(name: str) -> bool:
    print(f'Lade {name} (ca. {GROESSE.get(name, "?")} GB) …', flush=True)
    return subprocess.run(['ollama', 'pull', name]).returncode == 0


def einstellungen_lesen() -> dict:
    try:
        return json.loads(SETTINGS.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def einstellungen_schreiben(data: dict) -> None:
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    temp = SETTINGS.with_suffix('.json.neu')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(temp, SETTINGS)


def sichern() -> pathlib.Path | None:
    if not SETTINGS.exists():
        return None
    backup = SETTINGS.with_name(f'settings-vor-optimierung-{datetime.datetime.now():%Y%m%d-%H%M%S}.json')
    shutil.copy2(SETTINGS, backup)
    return backup


def messen(modell: str, quelle, runner=None, zeitlimit_s: float = 300, ausgabe=print) -> dict:
    """Ein Denkmodell über ATLAS auf den Mess-Aufgaben prüfen."""
    data = einstellungen_lesen()
    data['reasoning_model'] = modell
    einstellungen_schreiben(data)
    cases = {c['id']: c for c in g.KATALOG}
    ok = total = 0
    zeiten: list[float] = []
    vorher = swap_mb()
    abbruch = ''
    for ident in MESSUNG:
        case = cases[ident]
        for _ in range(case.get('wiederholungen', 1)):
            history = case['frage'] if isinstance(case['frage'], list) else [{'role': 'user', 'content': case['frage']}]
            result = quelle.frage(history)
            total += 1
            zeiten.append(result['gesamt_s'])
            status = g.STATUS_SKIP if (result['fehler'] and not result['antwort']) else g.bewerten(case, result['antwort'], runner)[0]
            ok += status == g.STATUS_OK
            ausgabe(f'  [{modell}] {status:<16} {ident} ({result["gesamt_s"]} s)')
            if result['gesamt_s'] > zeitlimit_s:
                abbruch = f'zu langsam ({result["gesamt_s"]:.0f} s für eine Aufgabe)'
                break
        if abbruch:
            break
    nachher = swap_mb()
    return {'modell': modell, 'bestanden': ok, 'gefragt': total, 'aufgaben': sum(cases[i].get('wiederholungen', 1) for i in MESSUNG),
            'median_s': round(statistics.median(zeiten), 1) if zeiten else None, 'max_s': round(max(zeiten), 1) if zeiten else None,
            'swap_zuwachs_mb': round(nachher - vorher), 'abbruch': abbruch}


def geeignet(r: dict) -> bool:
    return (not r['abbruch'] and r['gefragt'] == r['aufgaben'] and (r['median_s'] or 0) <= 90
            and r['swap_zuwachs_mb'] < 1500)


def waehlen(ergebnisse: list[dict]) -> dict | None:
    passend = [r for r in ergebnisse if geeignet(r)]
    if not passend:
        return None
    return max(passend, key=lambda r: (r['bestanden'], -(r['median_s'] or 0)))


def bericht(folder: pathlib.Path, info: dict, ergebnisse: list[dict], gewaehlt: dict | None, bild: dict | None,
            arbeitsmodell: str | None, backup: pathlib.Path | None) -> str:
    lines = ['# ATLAS-Optimierung', '', f'Erstellt: {datetime.datetime.now():%d.%m.%Y %H:%M}',
             f'Mac: {info["ram"]:.0f} GB Arbeitsspeicher, {info["frei"]:.0f} GB frei', '',
             '## Denkmodelle im Vergleich (schwere Aufgaben: Rechnen, Logik, Übersetzen, 3× Wiederholung)', '',
             '| Modell | richtig | Median | längste Antwort | Auslagerung | geeignet |', '|---|---|---|---|---|---|']
    for r in ergebnisse:
        mark = 'ja' if geeignet(r) else ('nein – ' + (r['abbruch'] or ('Speicher zu knapp' if r['swap_zuwachs_mb'] >= 1500 else 'zu langsam')))
        lines.append(f'| {r["modell"]} | {r["bestanden"]}/{r["aufgaben"]} | {r["median_s"]} s | {r["max_s"]} s | '
                     f'{r["swap_zuwachs_mb"]} MB | {mark} |')
    lines += ['', f'**Eingestellt: {gewaehlt["modell"]}** – bestes Ergebnis, das auf diesem Mac flüssig läuft.' if gewaehlt
              else '**Kein Modell eingestellt** – keines lief zuverlässig; die bisherige Einstellung bleibt.']
    if arbeitsmodell:
        lines.append(f'Arbeitsmodell (Gespräch und Mac-Aufgaben): {arbeitsmodell}')
    lines += ['', '## Bilder verstehen', '']
    if bild:
        lines.append(f'{bild["status"]}: Testbild mit {bild["modell"]} – Antwort „{bild["antwort"][:80]}“ ({bild["gesamt_s"]} s)')
    else:
        lines.append('NICHT AUSGEFÜHRT: kein Bildmodell installiert.')
    if backup:
        lines += ['', f'Alte Einstellungen gesichert: `{backup}`']
    lines += ['', '## Ehrlich',
              '- Gemessen auf Ihrem Mac, über ATLAS selbst – keine Herstellerangaben.',
              '- Ein größeres Modell ist klüger, aber langsamer. ATLAS nimmt es nur für Rechen-, Logik- und Übersetzungsaufgaben;',
              '  einfache Fragen bleiben beim schnellen Modell.',
              '- 16 GB setzen eine Grenze: Modelle über ca. 10 GB lassen zu wenig Platz für macOS und Ihre Apps.',
              '- Nächster Schritt: die Gesamtprüfung laufen lassen und mit dem letzten Bericht vergleichen.']
    text = '\n'.join(lines) + '\n'
    (folder / 'OPTIMIERUNG.md').write_text(text, encoding='utf-8')
    return text


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description='ATLAS auf diesem Mac optimieren')
    parser.add_argument('--out', default=str(pathlib.Path.home() / 'Downloads' / 'ATLAS-OPTIMIERUNG'))
    parser.add_argument('--backend', required=True)
    parser.add_argument('--laden', action='store_true', help='Fehlende empfohlene Modelle herunterladen.')
    parser.add_argument('--arbeitsmodell', action='store_true', help='Auch das Arbeitsmodell neu wählen (dauert ca. 1 Stunde).')
    args = parser.parse_args(argv)
    folder = pathlib.Path(args.out).expanduser()
    folder.mkdir(parents=True, exist_ok=True)
    backend = pathlib.Path(args.backend).resolve()
    sys.path.insert(0, str(backend))

    info = {'ram': ram_gb(), 'frei': frei_gb()}
    plan = plan_fuer(info['ram'])
    names = installiert()
    print(f'Mac: {info["ram"]:.0f} GB Arbeitsspeicher, {info["frei"]:.0f} GB frei. Installiert: {", ".join(names) or "nichts"}')
    if not names:
        print('Ollama antwortet nicht. Bitte die Ollama-App starten.')
        return 2
    fehlend = [m for m in plan['denken'] + [plan['bild']] if not vorhanden(m, names)]
    if fehlend and args.laden:
        need = sum(GROESSE.get(m, 5) for m in fehlend)
        if need + 10 > info['frei']:
            print(f'Zu wenig Platz: {need:.0f} GB nötig (plus 10 GB Reserve), {info["frei"]:.0f} GB frei. Lade nur, was passt.')
        for m in fehlend:
            if GROESSE.get(m, 5) + 10 <= frei_gb():
                laden(m)
        names = installiert()

    quelle = g.AtlasQuelle()
    ready, problem = quelle.bereit()
    if not ready:
        print(problem)
        return 2
    if not mindestens(dienst_version()):
        print(f'Der laufende ATLAS-Dienst ist Version {dienst_version() or "unbekannt"}. Die Optimierung braucht 1.0.3 – '
              'bitte zuerst ATLAS_UPDATE.command ausführen.')
        return 2
    backup = sichern()
    original = einstellungen_lesen()
    ergebnisse = []
    for modell in [m for m in plan['denken'] if vorhanden(m, names)]:
        print(f'== Messe Denkmodell {modell}')
        ergebnisse.append(messen(modell, quelle))
    gewaehlt = waehlen(ergebnisse)
    data = einstellungen_lesen()
    if gewaehlt:
        data['reasoning_model'] = gewaehlt['modell']
    elif 'reasoning_model' in original:
        data['reasoning_model'] = original['reasoning_model']
    else:
        data.pop('reasoning_model', None)
    einstellungen_schreiben(data)

    bild = None
    if vorhanden(plan['bild'], names):
        print(f'== Prüfe Bildverständnis mit {plan["bild"]}')
        g.bild_vorbereiten(folder)
        case = next(c for c in g.KATALOG if c['id'] == 'b01')
        result = quelle.frage([{'role': 'user', 'content': case['frage'].replace('{BILD}', g.TESTBILD['pfad'])}])
        status = g.STATUS_SKIP if (result['fehler'] and not result['antwort']) else g.bewerten(case, result['antwort'])[0]
        bild = {'modell': plan['bild'], 'status': status, 'antwort': result['antwort'] or result['fehler'], 'gesamt_s': result['gesamt_s']}

    arbeitsmodell = None
    if args.arbeitsmodell:
        print('== Arbeitsmodell wählen (24 Arbeitsaufgaben je Modell, dauert lange)')
        subprocess.run([sys.executable, '-m', 'atlas.realtests', '--compare', '--apply', '--output',
                        str(folder / 'arbeitsmodell.json')], cwd=backend, env={**os.environ, 'PYTHONPATH': str(backend)})
        arbeitsmodell = einstellungen_lesen().get('agent_model')

    text = bericht(folder, info, ergebnisse, gewaehlt, bild, arbeitsmodell, backup)
    print(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
