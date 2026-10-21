# ATLAS – Learning & Evolution (ab 0.6.0)

ATLAS lernt aus seiner Arbeit, aus Ihren Korrekturen und aus Quellen. Er entwickelt fehlende Fähigkeiten selbst und schlägt Verbesserungen vor.

Er verändert sich aber **nie still**:
- Alles Dauerhafte wartet auf Ihre Freigabe.
- Alles bleibt sichtbar, korrigierbar und rücksetzbar.
- Die Gewichte des Sprachmodells bleiben unverändert. Gelerntes ist gespeichertes Wissen, kein Training.

## Bausteine

| Baustein | Datei | Was er tut |
|---|---|---|
| Experience Memory | `atlas/learning.py` | Speichert je Aufgabe: Ziel, Vorgehen, Werkzeuge, Ergebnis, Fehler, Lehre, Dauer. |
| Task Outcome Evaluator | `learning.py` (`evaluate`) | Bewertet ohne Modell: erfolg / teilweise / fehlgeschlagen / abgebrochen. „Bewährt“ ist nur, was Werkzeuge nachweislich bestätigt haben und Sie nicht korrigiert haben. |
| Reflection Engine | `learning.py` (`reflect`) | Formuliert die Lehre deterministisch, z. B. „Statt write_file hat create_spreadsheet funktioniert“. |
| User Preference Learning | `learning.py` (`learn_correction`) | Macht aus „Nein, …“ / „Das war nicht richtig …“ eine Regel. Mit „ab jetzt“, „immer“ usw. gilt sie überall, sonst nur bei ähnlichen Aufgaben. Sie überlebt Neustarts. |
| Semantic Knowledge Retrieval | `atlas/knowledge.py` | Baut Wissen aus Webquellen auf, mit Quelle und Abrufdatum je Aussage, Status und Wissenslücken. |
| Skill Registry + Skill Development Sandbox | `atlas/skills.py`, `skill_harness.py` | Entwickelt neue Fähigkeiten mit Tests, isoliert ausgeführt. Aktiv werden sie erst nach Freigabe, jede Version bleibt erhalten. |
| Automated Test & Evaluation Engine | `skill_harness.py`, `workshop.py`, `realtests.py` | Tests in eigenen, begrenzten Prozessen und Echtaufgaben auf dem Mac. |
| Improvement Engine | `atlas/improvement.py` | Erkennt wiederkehrende Fehler und langsame Aufgabenarten und schlägt Arbeitsanweisungen vor. Wirkungslose nimmt sie automatisch zurück. |
| Code-Werkstatt (Versioning & Rollback) | `atlas/workshop.py` | Ändert eigenen Code nur in einer Kopie und nur, wenn alle Tests bestehen. Übernimmt erst nach Freigabe, mit Sicherung und automatischem Rücksetzen. |
| Human Approval System | `atlas/approvals.py` | Hält alle Vorschläge fest. Ausführung nur nach Freigabe, die Entscheidung ist endgültig. |
| Improvement Scheduler | `atlas/evolution.py` | Führt Lernaufträge im Hintergrund aus. Pausierbar, mit Tageslimit und Netzwerkschalter. |

## So nutzen Sie es

| Sie sagen | Was passiert |
|---|---|
| „Atlas, das war nicht richtig. Du solltest die Datei in Dokumente speichern.“ | 1. ATLAS merkt sich die Korrektur als Regel für ähnliche Aufgaben.<br>2. Er markiert die letzte Erfahrung als korrigiert.<br>3. Er erledigt die Aufgabe sofort richtig. |
| „Nein, antworte ab jetzt immer kürzer.“ | Dauerhafte Vorliebe; sie gilt in jedem Gespräch. |
| „Lerne, wie man PowerPoint-Präsentationen erstellt.“ | Lernauftrag im Hintergrund:<br>1. Das Modell schreibt Code und Tests.<br>2. Statische Prüfung.<br>3. Test in der Sandbox; bei Fehlern bis zu 3 Versuche mit Fehlermeldung.<br>4. Danach: „Ich habe eine neue Fähigkeit entwickelt und getestet … Möchtest du sie aktivieren?“ |
| „Lerne alles über Unternehmensbewertung.“ | Lernauftrag im Hintergrund:<br>1. Websuche, bis zu 4 Quellen lesen.<br>2. Aussagen herausziehen.<br>3. Jede Aussage gegen ihren Quelltext prüfen.<br>4. Quellen abgleichen und Lücken festhalten.<br>Später fließt das Wissen mit Quelle in Antworten ein. |
| Learning & Evolution öffnen (Gehirn-Symbol oben, Einstellungen oder „Öffne Learning“) | Zeigt Freigaben, Kennzahlen mit Verlauf, Regeln, Fähigkeiten, Wissen, Verbesserungen, Code-Änderungen, Erfahrungen und Lernaufträge. Alles ist korrigier-, abschalt- und löschbar. |

Beim Start sagt ATLAS, wenn etwas auf Ihre Freigabe wartet. Freigeben können Sie **nur in der App**, nicht per Sprachbefehl. Das Sprachmodell kann die Freigabe-Schnittstelle nicht erreichen: Sie verlangt das Sitzungstoken der App, und Werkzeuge dürfen keine lokalen Adressen aufrufen.

## Feste Regeln (nicht abschaltbar, auch nicht von ATLAS selbst)

1. **Fähigkeiten:**
   - Nur erlaubte Bibliotheken. Keine Shell, kein `eval`/`exec`, keine Introspektion.
   - Prüfung zweimal: statisch vor dem Ausführen und zur Laufzeit.
   - Kein Netzwerk: Sockets sind gesperrt, auf dem Mac zusätzlich `sandbox-exec`.
   - Schreiben nur im Ausgabeordner und in einem eigenen Temp-Ordner.
   - Grenzen für CPU-Zeit, Dateigröße und offene Dateien.
   - Beim Aktivieren wird erneut getestet.
   - Ausführen nur mit Ihrer Bestätigung (Stufe CONFIRM).
2. **Bibliotheken** installiert ATLAS nur aus einer festen Liste und nur nach Freigabe.
3. **Code-Änderungen:**
   - Nur Backend-Dateien (`atlas/`, `tests/`, `web/`, `personality.txt`), nie Skripte oder die App.
   - Ablauf: Kopie anlegen, vollständige Testsuite ausführen. Tests dürfen nicht weniger oder übersprungen werden.
   - Erst danach entsteht ein Vorschlag.
   - Änderungen an Sicherheitsdateien (Werkzeuge/Berechtigungen, Sandbox, Freigaben, Werkstatt, Planer, Server, Agent) und an Tests sind „sicherheitsrelevant“. Sie brauchen eine zweite, ausdrückliche Bestätigung.
   - Übernahme mit Sicherung. Scheitert die Prüfung danach, wird automatisch zurückgesetzt. Jede Übernahme ist rücksetzbar.
4. **Verbesserungshinweise:**
   - Sie sind reiner Text für den Agenten. Sicherheitsregeln ändern sie nie.
   - Ist ein Bewerter angeschlossen, wird ein Hinweis, der schlechter misst, gar nicht vorgeschlagen.
5. **Eigenständige Lernzyklen:**
   - Anfangs **aus**. Einschalten unter Learning & Evolution → Lernzyklen.
   - Pausierbar, Rechenzeit pro Tag begrenzt (Standard 30 min).
   - Ohne Internet, wenn ausgeschaltet.
   - Sie laufen nur, wenn ATLAS gerade nicht antwortet.
6. **Kosten:** keine. Nur lokale Modelle und frei zugängliche Webseiten, keine bezahlten Dienste.
7. **Kein Modelltraining** ohne Daten, Eignungsprüfung und Ihre Freigabe, siehe `docs/FINE-TUNING-STUDIE.md`. Der Export enthält nur bestätigte Beispiele.

## Kennzahlen

Berechnet aus dem Erfahrungsspeicher (30 Tage); Tageswerte werden bei jeder Analyse gespeichert und als Verlauf gezeigt:

| Kennzahl | Bedeutung |
|---|---|
| Erfolgsquote komplexer Aufgaben | Anteil „erfolg“ bei Aufgaben mit Werkzeugen. |
| Zuverlässigkeit der Werkzeuge | Anteil erfolgreicher Werkzeugaufrufe. |
| Durchschnittliche Dauer | Dauer je Aufgabe. |
| Wiederholte Fehler | Gleiche Fehlerart beim gleichen Werkzeug, mindestens 2×. |
| Korrekturen | Wie oft Sie ATLAS korrigiert haben. |
| Gedächtnis korrekt | Anteil der Regeln, die Sie weder bearbeiten noch abschalten mussten. |
| Fähigkeiten aktiv / getestet | Wie viele selbst entwickelte Fähigkeiten aktiv sind und wie viele die Tests bestanden haben. |

## Ehrliche Grenzen

- **Code schreibt das lokale 4B-Modell.**
  - Einfache Fähigkeiten (PowerPoint, Word, Umrechnungen) sind realistisch.
  - Komplexe scheitern eher. Dann steht „fehlgeschlagen“ mit der Testausgabe in der Liste, und nichts wird aktiv.
- **Wissensaufbau:** Das Modell kann Aussagen falsch zusammenfassen. Die Belegprüfung verwirft nur Aussagen, deren Kernwörter nicht im Quelltext stehen. Sinnverdrehungen mit denselben Wörtern erkennt sie nicht. Deshalb steht bei jeder Aussage die Quelle.
- **Widersprüche** meldet das Modell. Es kann welche übersehen.
- **Die Code-Werkstatt** ändert das installierte Backend. Ein späteres `AKTUALISIEREN.command` ersetzt es wieder durch die ausgelieferte Version.
- **Sandbox-Profil der Code-Werkstatt** (Netz nur localhost) ist auf dem Mac noch nicht ausprobiert. Ohne funktionierende Sandbox laufen keine Werkstatt-Tests; es wird nichts unsandboxed ausgeführt.
