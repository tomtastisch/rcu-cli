# Arbeitsprotokoll – RCU Remote Control Unit

Dieses Protokoll ist versioniert und beschreibt ausschließlich nachweislich
ausgeführte Schritte. `macOS-Host` und `Debian-VM` kennzeichnen den
Ausführungsort. Geheimnisse, Schlüsselmaterial und private Logdaten werden
nicht aufgenommen.

## Master-Fortschrittsliste

| Phase | Status | Stand |
|---|---|---|
| 1 Diagnose | PASS | Ausgangszustand erfasst; Root Cause für direkten Einstieg reproduziert |
| 2 Minimale Implementierung | PASS | Direkter Launcher und nachvollziehbare SSH-Warteanzeige umgesetzt |
| 3 Testgetriebene Umsetzung | PASS | Regressionstests ergänzt; vollständige isolierte Suite 40/0 |
| 4 Reale Abnahme | PASS | UTM-/SSH-/TTY-Abnahme und produktive Installation bestanden |
| 5 Veröffentlichung | PASS | PR gemerged; alle verfügbaren GitHub-Checks abgeschlossen |

## Einträge

### Schritt 1 – Governance und Repository-Ausgangszustand

- **Zeitpunkt:** 2026-11-03T11:18:01+01:00
- **Phase:** Diagnose
- **Ort:** macOS-Host
- **Ausgangszustand und Ziel:** Governance, Git-Stand, Branch, Remote und lokale Version vor Änderungen verifizieren.
- **Aktion:** Kanonisches Governance-Bootstrap und Manifest geladen; SHA-256 der beiden Dateien geprüft. `git status --short --branch`, `git rev-parse HEAD`, Branch-/Remote-Abfrage und `git ls-remote origin refs/heads/main` ausgeführt.
- **Betroffene Komponenten:** Governance-Bundle; Git-Repository.
- **Ergebnis/Nachweis:** Governance- und Manifest-Prüfsummen entsprechen den erwarteten Werten. Arbeitsbaum war sauber, Branch `main`, lokaler HEAD und `origin/main` waren `492a971f7a35d67fe5d55774e9a94ac6f104d470`. Repository-Version: `0.2.0`.
- **Status:** PASS
- **Nächster Schritt:** Projektdateien und Tests analysieren.

### Schritt 2 – Host- und Installationszustand

- **Zeitpunkt:** 2026-11-03T11:18:01+01:00
- **Phase:** Diagnose
- **Ort:** macOS-Host
- **Ausgangszustand und Ziel:** Relevante Werkzeuge, installierten Launcher und UTM-Zustand feststellen.
- **Aktion:** `command -v rcu`, `rcu --version`, UTM-/`gum`-/SSH-Prüfung, UTM-Prozessprüfung, installierte RCU-Pfade und Konfigurationsdatei-Metadaten gelesen.
- **Betroffene Komponenten:** `/Users/tomtastisch/.local/bin/rcu`; `~/.local/share/utm/rcu`; `~/.config/rcu/config`; UTM.
- **Ergebnis/Nachweis:** Installierter Launcher ist vorhanden und meldet ohne Unterbefehl `ERROR: Usage: rcu {help|update|rollback|uninstall|utm}`. Installierte Version ist `0.2.0`; Konfiguration hat restriktive Berechtigungen. `gum` und OpenSSH sind vorhanden. UTM lief als Anwendung; `utmctl list` meldete VM `stopped`.
- **Status:** PASS
- **Nächster Schritt:** Direkten Einstieg und vorhandene Lifecycle-Implementierung gegen Anforderungen abgleichen.

### Schritt 3 – Bestehende Implementierung und isolierte Tests

- **Zeitpunkt:** 2026-11-03T11:18:36+01:00
- **Phase:** Diagnose
- **Ort:** macOS-Host mit isoliertem Test-HOME
- **Ausgangszustand und Ziel:** Launcher, UTM-/SSH-Wartefunktionen, `gum`, Installer, Rollback/Uninstall und Tests prüfen und Baseline herstellen.
- **Aktion:** `bin/rcu`, `lib/core.sh`, `lib/backends/utm.sh`, Installerdateien, `config/config.example`, `README.md` und `tests/smoke.sh` gelesen; `/bin/bash tests/smoke.sh` ausgeführt.
- **Betroffene Komponenten:** Repository-Dateien unter `bin/`, `lib/`, `installer/`, `tests/`.
- **Ergebnis/Nachweis:** `bin/rcu` behandelt nur `help`, Lifecycle-Unterbefehle und Verwaltung; kein Default-Fall für direkten Shell-Einstieg. `utm_start` startet nur bei nicht laufender VM, wartet auf authentifiziertes SSH und verwendet `gum spin` mit Exit-Code-Weitergabe. Die Baseline-Suite meldete `RESULT: 35 PASS, 0 FAIL`. Kein Repository-Code wurde vor diesem Protokolleintrag verändert.
- **Status:** PASS
- **Nächster Schritt:** Reproduzierbaren Regressionstest für `rcu` ohne Unterbefehl ergänzen; danach kleinste Implementierung.

### Schritt 4 – Regressionstest und reproduzierter Root Cause

- **Zeitpunkt:** 2026-11-03T11:19:06+01:00
- **Phase:** Testgetriebene Umsetzung
- **Ort:** macOS-Host mit isoliertem Test-HOME
- **Ausgangszustand und Ziel:** Das gewünschte Verhalten `rcu` ohne Unterbefehl muss eine gestoppte VM starten, SSH abwarten und die Shell öffnen; eine laufende VM darf nicht erneut gestartet werden.
- **Aktion:** Regressionstest in `tests/smoke.sh` ergänzt und `/bin/bash tests/smoke.sh` gegen den unveränderten Launcher ausgeführt.
- **Betroffene Komponenten:** `tests/smoke.sh`; `bin/rcu`.
- **Ergebnis/Nachweis:** Der Testlauf endete mit `RESULT: 32 PASS, 6 FAIL`. Der direkte Aufruf beendete sich zwar erfolgreich, führte aber keinen `utmctl start` aus und ließ den simulierten Zustand `stopped`; die Folgefehler waren dadurch erwartete Testkaskaden. Root Cause: `case "${1:-help}"` routet einen fehlenden Unterbefehl in `show_help` statt in den UTM-Start-/Shell-Pfad.
- **Status:** PASS
- **Nächster Schritt:** Kleinste Korrektur für den Default-Launcher implementieren und den Regressionstest erneut ausführen.

### Schritt 5 – Implementierung und isolierte Verifikation

- **Zeitpunkt:** 2026-11-03T11:20:22+01:00
- **Phase:** Minimale Implementierung / Testgetriebene Umsetzung
- **Ort:** macOS-Host mit isoliertem Test-HOME
- **Ausgangszustand und Ziel:** Direkter Einstieg und transparente SSH-Warteanzeige fehlten; bestehende Lifecycle- und Sicherheitsgrenzen mussten erhalten bleiben.
- **Aktion:** `bin/rcu` routet einen fehlenden Unterbefehl zu `utm_start` und anschließend `utm_shell`. `lib/core.sh` erhielt `wait_for_ssh` mit verstrichener Zeit, UTM-Zustand, SSH-Zustand und Timeoutstatus. Die drei SSH-Wartepfade in `lib/backends/utm.sh` verwenden diese Funktion. `README.md` dokumentiert `rcu` und `exit`; `VERSION` wurde gemäß Release-Strategie auf `0.3.0` erhöht. Regressionen in `tests/smoke.sh` prüfen gestoppte und laufende VM sowie Statuszeile.
- **Betroffene Komponenten:** `bin/rcu`, `lib/core.sh`, `lib/backends/utm.sh`, `tests/smoke.sh`, `README.md`, `VERSION`.
- **Ergebnis/Nachweis:** `/bin/bash tests/smoke.sh` endete mit `RESULT: 40 PASS, 0 FAIL`. Die Ausgabe enthielt nachweislich `SSH_WAIT elapsed=0s UTM=started SSH=authenticated`; Start wird bei laufender VM nicht erneut ausgeführt.
- **Status:** PASS
- **Nächster Schritt:** Reale UTM-/SSH-Abnahme mit der derzeit gestoppten VM; keine erzwungene Abschaltung.

### Schritt 6 – Gum-Design und reale TTY-Abnahme

- **Zeitpunkt:** 2026-11-03T11:24:00+01:00
- **Phase:** Reale Abnahme
- **Ort:** macOS-Host; SSH-Shell innerhalb der Debian-VM nur als lesender Interaktionstest
- **Ausgangszustand und Ziel:** Die Anzeige sollte `gum` nutzen, minimalistisch wiedererkennbar sein und nur tatsächlich messbare Fortschritte visualisieren.
- **Aktion:** Homebrew-/gum-Versionen und verfügbare `gum`-Kommandos geprüft. `lib/core.sh` erhielt gerahmte `gum style`-Karten und einen an das reale SSH-Wartefenster gekoppelten ASCII-Balken; `gum progress` wurde nicht verwendet, weil es in gum 2.0.2 nicht existiert. TTY-Prüfung mit `script` und anschließend `expect` gegen `bin/rcu` ausgeführt.
- **Betroffene Komponenten:** `lib/core.sh`; reale UTM-VM; `gum` 2.0.2; Homebrew 7.0.12.
- **Ergebnis/Nachweis:** Homebrew und gum sind installiert und ausführbar; Colima war vorhanden, aber nicht erforderlich. TTY-Ausgabe zeigte die Karten `PHASE 1/4` bis `PHASE 4/4`, `VM: started`, `SSH: authenticated`, `Wartefenster: [########################] 100%` und verstrichene Zeit. Der direkte Launcher öffnete die Debian-Shell; `expect` sendete `exit`, SSH meldete `Abgemeldet`, und `utmctl list` bestätigte anschließend weiterhin `started`. Ein vorheriger `script`-Versuch konnte `exit` nicht zuverlässig weiterreichen und wurde als lokaler Prüfprozess beendet; die VM blieb dabei unverändert `started`.
- **Status:** PASS
- **Nächster Schritt:** Geprüften 0.3.0-Release über den vorgesehenen Updateweg installieren und danach den installierten Launcher erneut prüfen.

### Schritt 7 – Finales lokales Gate vor Installation

- **Zeitpunkt:** 2026-11-03T11:26:32+01:00
- **Phase:** Veröffentlichung
- **Ort:** macOS-Host mit isoliertem Test-HOME für die Suite
- **Ausgangszustand und Ziel:** Vor einer produktiven Aktualisierung mussten Syntax, Diff und vollständige Regressionen auf dem Release-Stand bestanden sein.
- **Aktion:** Bash-Syntaxprüfung für alle relevanten Skripte, `git diff --check` und `/bin/bash tests/smoke.sh` ausgeführt.
- **Betroffene Komponenten:** gesamter geänderter RCU-Release; Test-Harness.
- **Ergebnis/Nachweis:** Syntax und Diff-Gate bestanden. Die Suite endete mit `RESULT: 40 PASS, 0 FAIL`. Der Worktree enthält ausschließlich die auftragsbezogenen Änderungen plus `docs/ARBEITSPROTOKOLL.md`.
- **Status:** PASS
- **Nächster Schritt:** Release 0.3.0 über den produktiven `rcu update`-Weg installieren.

### Schritt 8 – Produktive Installation, globale Abnahme und Rollback

- **Zeitpunkt:** 2026-11-03T11:26:12+01:00
- **Phase:** Veröffentlichung
- **Ort:** macOS-Host; Debian-VM nur über authentifizierte SSH-Shell
- **Ausgangszustand und Ziel:** Der getestete Release musste produktiv aktiv sein; globaler Launcher, read-only Status, direkter Shell-Einstieg, `exit` und Rollback mussten nachgewiesen werden.
- **Aktion:** `rcu update "$PWD"` ausgeführt; aktiven Link und Launcher-Link gelesen. In einer frischen zsh-Umgebung `command -v rcu`, `rcu utm status` und den direkten `rcu`-Einstieg mit echtem PTY/`expect` geprüft. `exit` gesendet. Danach `rcu rollback` auf den vorherigen Release und anschließende Wiederherstellung per `rcu update "$PWD"` ausgeführt.
- **Betroffene Komponenten:** produktive `~/.local/bin/rcu`; verwaltete Releases 0.2.0/0.3.0; laufende UTM-VM.
- **Ergebnis/Nachweis:** Produktiver Link zeigte auf `releases/0.3.0`; frische zsh fand `/Users/tomtastisch/.local/bin/rcu`. `rcu utm status` meldete `started` und führte keinen Start aus. Der direkte Launcher öffnete die Debian-Shell; `exit` schloss SSH, und die VM blieb `started`. Rollback schaltete nachweislich auf 0.2.0, danach wurde 0.3.0 wieder installiert und `rcu help` erfolgreich geprüft.
- **Status:** PASS
- **Nächster Schritt:** Security-Review abwarten, Protokoll-/Diff-Gate durchführen, Feature-Branch/Commit/PR erstellen.

### Schritt 9 – Unabhängiger Security-Review

- **Zeitpunkt:** 2026-11-03T11:27:00+01:00
- **Phase:** Veröffentlichung / Security-Gate
- **Ort:** Getrennter Review-Kontext; Repository als Prüfstand
- **Ausgangszustand und Ziel:** Vor Commit, Pull Request und Merge musste ein unabhängiger Review der geänderten Shell-, Installer-, SSH- und UI-Pfade erfolgen.
- **Aktion:** Read-only Security-Review des aktuellen Repositorys und Working-Tree-Diffs mit Fokus auf Shell-Injection, Konfigurationsparser, SSH-Trust, Installer-/Rollback-Integrität, Symlinks/Pfade, externe Befehle und `gum`-UI gestartet und abgeschlossen.
- **Betroffene Komponenten:** Geänderte RCU-Dateien und bestehende Installations-/SSH-Pfade.
- **Ergebnis/Nachweis:** Der Review meldete: `No security vulnerabilities found in the reviewed changes.` Es wurden keine Findings mit Schweregrad oder Proof-of-Concept ausgegeben.
- **Status:** PASS
- **Nächster Schritt:** Vollständiges Protokoll-/Diff-Gate, Commit mit Co-Author-Trailer, PR gegen `main`, CI prüfen und nur bei PASS regulär mergen.

### Schritt 10 – Pull Request, Merge und Remote-Verifikation

- **Zeitpunkt:** 2026-11-03T11:30:19+01:00
- **Phase:** Veröffentlichung
- **Ort:** macOS-Host mit GitHub CLI
- **Ausgangszustand und Ziel:** Die geprüften Änderungen mussten ausschließlich auf einem Feature-Branch veröffentlicht, als Pull Request geprüft und regulär nach `main` gemerged werden.
- **Aktion:** Feature-Branch `feat/rcu-direct-launcher-ui` gepusht; Pull Request `tomtastisch/rcu-cli#2` erstellt und regulär gemerged. `gh pr view`, `gh pr checks` und `git ls-remote origin` ausgeführt.
- **Betroffene Komponenten:** Git-Remote; Pull Request; Remote-Branch `main`.
- **Ergebnis/Nachweis:** PR `https://github.com/tomtastisch/rcu-cli/pull/2` ist `MERGED`. Remote-`main` zeigt auf `823a7ddc80bf10d159160fce7fab878a24b1f454`. Greptile Review sowie beide Socket-Security-Checks sind PASS; Greptile TREX ist abgeschlossen mit `NEUTRAL`/`skipping` und nicht fehlgeschlagen.
- **Status:** PASS
- **Nächster Schritt:** Arbeitsprotokolländerung als Follow-up-PR nach `main` veröffentlichen und dessen finalen Remote-Stand verifizieren.

### Schritt 11 – Finalisierung des Arbeitsprotokolls

- **Zeitpunkt:** 2026-11-03T11:39:26+01:00
- **Phase:** Veröffentlichung
- **Ort:** macOS-Host mit GitHub CLI
- **Ausgangszustand und Ziel:** Der finale CI-Zustand musste im versionierten Arbeitsprotokoll nachgetragen werden, ohne den bereits gemergten Release-Commit zu verändern.
- **Aktion:** Nach Abschluss der GitHub-Checks Statuswerte erneut gelesen; den Protokollstatus von `BLOCKED` auf `PASS` aktualisiert und einen separaten Follow-up-Commit/PR vorbereitet.
- **Betroffene Komponenten:** `docs/ARBEITSPROTOKOLL.md`; GitHub PR- und Main-Stand.
- **Ergebnis/Nachweis:** Greptile Review `SUCCESS`, Socket Security Project Report `SUCCESS`, Socket Security Pull Request Alerts `SUCCESS`, Greptile TREX `NEUTRAL`/`skipping`; kein Check `FAILURE`.
- **Status:** PASS
- **Nächster Schritt:** Follow-up committen, PR erstellen/mergen und finalen `main`-Commit erneut prüfen.
