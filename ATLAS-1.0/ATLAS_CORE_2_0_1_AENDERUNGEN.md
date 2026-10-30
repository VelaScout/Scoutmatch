# ATLAS Core 2.0.1 – Sicherheits- und Regressionserweiterung

## Implementiert
- Zentrale Ollama-Clientklasse validiert die Modellserveradresse vor dem ersten Netzwerkaufruf.
- Nur HTTP auf 127.0.0.1, localhost oder ::1 mit explizitem Port ist erlaubt.
- Entfernte Hosts, Zugangsdaten in URLs, URL-Pfade, Query-Parameter, Fragmente und fehlerhafte Ports werden abgewiesen.
- Keine API-Abonnements oder Cloud-Dienste wurden aktiviert.
- Neue Regressionstests: `Backend/tests/test_ollama_endpoint_guard_20.py`.

## Tests in dieser Entwicklungsumgebung
- 2 neue Tests bestanden.
- 34 vorhandene Agententests bestanden.
- Gesamte Testsuite angestoßen, aber innerhalb des Zeitlimits nicht abgeschlossen; **kein vollständiger Testnachweis**.
- macOS-Build, Mikrofon, Barge-in, echte Ollama-Modellantworten und Mac-Berechtigungen hier nicht überprüfbar.

## Nächster Mac-Test
`cd Backend && PYTHONPATH=. python3 -m unittest discover -s tests -p 'test_ollama_endpoint_guard_20.py' -v`
Danach App mit Xcode bauen und die Live-Funktionen testen. Bestehende App nicht überschreiben.
