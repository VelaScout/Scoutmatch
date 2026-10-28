# ATLAS 1.0.8 – Messbare Gesprächsqualität

Diese Version ergänzt den Live-Qualitätstest um nachvollziehbare Kennzahlen:
- Bestehensquote unter tatsächlich ausgeführten Tests.
- Testabdeckung, die blockierte Tests gesondert ausweist.
- Median der Gesamtdauer und Zeit bis zur ersten Ausgabe.
- Eine Vergleichsfreigabe erst ab mindestens zehn nicht blockierten Testfällen.

Die Bewertung bleibt regelbasiert; sie ist **kein** fairer Benchmark gegen ChatGPT oder Claude und beweist keine höhere Intelligenz. Der vorhandene Live-Test verwendet weiterhin einen separaten Test-Systemprompt.

## Auf dem Mac
Nach Installation und Start des ATLAS-Backends `ATLAS_103_LIVE_TEST.command` doppelklicken. Bericht: `Ergebnisse/ATLAS_103_QUALITAET.md` und `.json`.

## Ohne Mac
`PYTHONPATH=Backend python3 -m unittest discover -s Backend/tests -p 'test_benchmark_summary_108.py'`
