# Arbeitsprotokoll – RCU Remote Control Unit

Dieses Protokoll ist versioniert und beschreibt ausschließlich nachweislich
ausgeführte Schritte. `macOS-Host` und `Debian-VM` kennzeichnen den
Ausführungsort. Geheimnisse, Schlüsselmaterial und private Logdaten werden
nicht aufgenommen.

## Master-Fortschrittsliste

| Phase | Status | Stand |
|---|---|---|
| 1 Diagnose | PASS | Portabilitätsdefekte auf Basis 158bf949 nachgewiesen; siehe Schritt 12 |
| 2 Minimale Implementierung | PASS | 0.4.0: Einrichtung, UUID, dynamische Adresse, Keychain und Upload implementiert |
| 3 Testgetriebene Umsetzung | PASS | Isolierte Regressionen: 40 Lifecycle-, 30 Portabilitäts-, 8 Netzwerk- und 5 PTY-Prüfgruppen |
| 4 Reale Abnahme | BLOCKED | Aktueller 0.4.0-Stand ohne Zugriff auf macOS/UTM nicht real geprüft |
| 5 Veröffentlichung | BLOCKED | Feature-Branch und Draft-PR #5 veröffentlicht; kein Merge ohne aktuelle reale Pflichtabnahme |

Die Schritte 1–11 beschreiben den historischen 0.3.0-Stand. Dessen PASS-Werte
gelten nicht als Abnahme der aktuellen Portabilitätsreparatur.

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
- **Nächster Schritt:** Entfällt; der Follow-up-PR ist gemerged und der finale Remote-Stand verifiziert.

### Schritt 11 – Finalisierung des Arbeitsprotokolls

- **Zeitpunkt:** 2026-11-03T11:39:26+01:00
- **Phase:** Veröffentlichung
- **Ort:** macOS-Host mit GitHub CLI
- **Ausgangszustand und Ziel:** Der finale CI-Zustand musste im versionierten Arbeitsprotokoll nachgetragen werden, ohne den bereits gemergten Release-Commit zu verändern.
- **Aktion:** Nach Abschluss der GitHub-Checks Statuswerte erneut gelesen; den Protokollstatus von `BLOCKED` auf `PASS` aktualisiert und einen separaten Follow-up-Commit/PR vorbereitet.
- **Betroffene Komponenten:** `docs/ARBEITSPROTOKOLL.md`; GitHub PR- und Main-Stand.
- **Ergebnis/Nachweis:** Greptile Review `SUCCESS`, Socket Security Project Report `SUCCESS`, Socket Security Pull Request Alerts `SUCCESS`, Greptile TREX `NEUTRAL`/`skipping`; kein Check `FAILURE`.
- **Status:** PASS
- **Nächster Schritt:** Entfällt; Abschluss-Gate vollständig PASS.


### Schritt 12 – Portabilitätsreparatur: Ausgangszustand und RED

- Zeitpunkt: 2026-11-03T17:06:00+01:00
- Phase / Ort: Diagnose und Regression / isolierter Linux-Workspace, kein Zugriff auf macOS-Host oder Debian-VM.
- Ausgangszustand: Remote-main und Clone `158bf949b44da9fb5d08a6808018582ec0becef2`, VERSION 0.3.1, sauberer Working Tree. Produktiv installierte Version nicht zugänglich. Berichtete lokale 0.3.2–0.3.6-Patches liegen im Remote nicht vor und wurden nicht als Code übernommen.
- Ziel: Keine fremden VM-/SSH-Vorgaben; einmalige UUID-/Benutzer-/Authentifizierungseinrichtung; dynamische IP; sicherer Dateitransfer; klare Terminalanzeige.
- Aktion / Befund: `config/config.example`, `lib/core.sh`, `lib/backends/utm.sh`, Installer, CLI und Tests gelesen. Feste UUID, Namensgleichheit, IP, Benutzer und verpflichtender CLion-Schlüssel bestätigt. Bestehende Tests teilen diese Annahmen. Bereitschaftsprüfung erzwingt BatchMode und Schlüssel.
- Nachweis: `/bin/bash tests/smoke.sh` vor Änderung: Exit 0, 40 PASS / 0 FAIL. Neue Portabilitätstests vor Implementierung: Exit 1, 15 PASS / 16 FAIL, insbesondere unbekanntes CONFIG_VERSION, fehlendes Setup und Schlüsselzwang. Zwei unzutreffende neue Testannahmen vor Implementierungsabnahme korrigiert.
- Status: PASS (Diagnose); FAIL (erwartete RED-Regression).
- Änderungen / Plan: Module für Setup, Netzermittlung und Keychain-Askpass; Auswahl anhand UUID; Guest-Agent-IP oder NIC/DHCP-Abgleich; Passwort über nativen security-Prompt, keine Secret-Argumente; UUID-gebundener Host-Key; SCP -P und derselbe Zugang. Release 0.4.0 verhindert Kollision mit berichteter lokaler 0.3.6.
- Rollback: Ausgangscommit bleibt unverändert; Feature-Branch `fix/portable-vm-setup`. Keine produktive Installation geändert. Altes Installer-Rollback bleibt erhalten; alte Releases können die neue Profilsemantik nicht übernehmen und sind für die neuen Zugänge nicht freigegeben.
- Blocker: Reale UTM-/Keychain-/TTY-/Gast-Abnahme und produktive Installation sind ohne Mac-Zugriff BLOCKED. Kein Merge bei fehlender Live-Abnahme.
- Nächster Schritt: Implementierung und isolierte Regressionen; unabhängiger Review, PR als Draft mit expliziten Live-Gates.

### Schritt 13 – Wiederaufnahme und isolierte Verifikation

- Zeitpunkt: 2026-11-03T18:23:00+01:00
- Phase / Ort: Test und Review / isolierter Linux-Workspace; kein macOS-Host und keine Debian-VM.
- Ausgangszustand und Ziel: Vorhandene uncommittete 0.4.0-Änderungen auf `fix/portable-vm-setup` erhalten und die zuletzt offenen Dialog-/Upload-Prüfungen neu ausführen.
- Aktion: Working Tree, Historie und Remote gelesen. `git ls-remote origin refs/heads/main` liefert weiterhin `158bf949b44da9fb5d08a6808018582ec0becef2`. `/bin/bash tests/smoke.sh`, `/bin/bash tests/portable.sh`, `/bin/bash tests/network.sh` und `python3 tests/interactive.py` erneut ausgeführt, jeweils Exit 0.
- Ergebnis: 40/0 Lifecycle, 30/0 Portabilität, 4 Netzwerk-Prüfgruppen und 5 PTY-Prüfgruppen. PTY umfasst verdeckte Erfassung, explizite Host-Vertrauensprüfung, wiederholten Start ohne Neuanlage, Upload mit Leerzeichen und Fehlercode 9 sowie verweigerte Askpass-Fremdprompts. Nur simulierte Dienste; kein Nachweis nativer Integration.
- Fehlversuch / Reaktion: ShellCheck zunächst nicht installiert. Isoliert unter `/tmp/rcu-shellcheck` bereitgestellt, keine Projektabhängigkeit. Erster Lintlauf Exit 1: SC2154 für modulübergreifend erzeugtes `ssh_opts`. Im Upload lokal initialisiert, damit Übergabe und Zuständigkeit ausdrücklich sind. Kein globales Unterdrücken des Befunds.
- Schnittstellenprüfung: Offizielle UTM-Scripting-Referenz bestätigt `network interfaces` und `address` als MAC. UTM-Quellcode bestätigt zeilenweise `ip-address`-Ausgabe und erforderliches `stop --request`. Aktueller Apple-Security-Quellcode bestätigt den verdeckten Bestätigungsdialog bei argumentlosem abschließendem `-w`. Quellen: https://docs.getutm.app/scripting/reference/ ; https://github.com/utmapp/UTM/blob/main/utmctl/UTMCtl.swift ; https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/keychain_add.c (Blob 960718596e4c8dfe8d515f3b84079f06c8ef1db4).
- Komponenten: `lib/backends/utm.sh`, Tests, dieses Protokoll. Historische Master-Tabelle ausdrücklich auf die aktuelle Reparatur umgestellt, ohne frühere Einträge umzudeuten.
- Status: PASS für isolierte Funktionsprüfungen; Lint-Nachprüfung und unabhängiger QA-/Security-Review ausstehend. Native Pflichtabnahme BLOCKED.
- Nächster Schritt: Unabhängigen Review auswerten, Befunde reproduzieren, abschließende Checks ausführen und geprüften Stand als Entwurfs-PR bereitstellen. Keine produktive Installation geändert; Rollbackbasis bleibt 158bf949.

### Schritt 14 – Unabhängige QA/Security und reproduzierte Korrekturen

- Zeitpunkt: 2026-11-03T18:30:00+01:00
- Phase / Ort: Review, RED/GREEN / isolierter Linux-Workspace; keine Host-/Gaständerung.
- Ausgangszustand und Ziel: Unabhängiger read-only Review des vollständigen Diffs durch separaten Kontext; native Grenzen und Fehlerpfade prüfen.
- Befunde / Reproduktion: `bounded 2 cat` mit Heredoc liefert leer, weil asynchrone Prozesse ohne explizite Eingabe `/dev/null` erhalten. Damit ging das Skript für die UTM-MAC-Ermittlung verloren. `output=$(bounded 1 /bin/bash -c 'sleep 4; printf late')` endete erst nach 4s mit 124: Nachkomme hielt stdout offen. `WAIT_SECONDS=08` bestand die Validierung, scheiterte danach an oktaler Bash-Arithmetik.
- RED-Nachweis: Neue Regressionen in `tests/network.sh`, vor Korrektur ausgeführt: Exit 1, genau diese drei FAIL-Ausgaben einschließlich arithmetischer Fehlermeldung und gemessenen 4s bei 1s-Limit. Die vier bisherigen Netzwerkprüfungen bestanden weiterhin.
- Korrektur / Dateien: `lib/core.sh` erhält explizites `<&0`, eine ausschließlich im Funktions-Subshell aktivierte eigene Job-Prozessgruppe und deren Cleanup einschließlich Nachkommen und `wait` bei Timeout, Signal und normalem Ende. Monitor-Modus wird direkt nach dem Start deaktiviert. Validierte numerische Werte werden dezimal normalisiert. `lib/backends/utm.sh` validiert und normalisiert das Shutdown-Wartefenster vor dem Shutdown-Request. `tests/network.sh` prüft auch einen bereits beendeten Worker mit verbleibendem stdout-haltendem Nachkommen.
- Review-Nachprüfung: Separater Reviewer bestätigte Heredoc- und Prozessgruppenlösung mit realen Linux-Prozessen. Keine weiteren bestätigten Befunde in UUID-Auswahl, Pfadübergabe, regulärem Stop oder Releaseverwaltung. Bash-3.2-/macOS-Verhalten bleibt separat abzunehmen.
- Einschränkung: Positiver Askpass-/Keychain-Abruf ist unter Linux nicht nativ prüfbar. Der PTY-SSH-Ersatz prüft Umgebungsübergabe, führt aber keinen realen Passwortabruf aus. Negative Askpass-Prompts sind tatsächlich ausgeführt. Nicht als vollständige Keychain-/SFTP-Integration bewerten.
- Status: PASS für reproduzierte Ursachen und implementierte Korrektur; vollständige abschließende Suite folgt. Reale macOS-/UTM-/Keychain-Abnahme BLOCKED.
- Nächster Schritt: Vollständige Tests, Lint, Syntax-/Diff-/Secret-Gate; Commit und Draft-PR mit offenen Pflichtabnahmen. Merge bleibt gesperrt.

### Schritt 15 – Abschluss-Gate für den Entwurfsstand

- Zeitpunkt: 2026-11-03T18:35:00+01:00
- Phase / Ort: Verifikation vor Commit / isolierter Linux-Workspace, Bash 5; kein macOS-Host oder Gast.
- Ausgangszustand und Ziel: Korrigierten integrierten 0.4.0-Stand prüfen; ausschließlich auftragsbezogene Änderungen sichern.
- Aktion / Ergebnis: Vollständige Befehle `/bin/bash tests/smoke.sh` (40 PASS / 0 FAIL), `/bin/bash tests/portable.sh` (30 PASS / 0 FAIL), `/bin/bash tests/network.sh` (8 PASS-Gruppen) und `python3 tests/interactive.py` (5 PASS-Gruppen), jeweils Exit 0. ShellCheck mit `-x -S warning -e SC2034` über CLI, alle Laufzeit-/Installer-/Testskripte: Exit 0. Bash-Syntax separat für jede Shell-Datei und `git diff --check`: Exit 0.
- Fehlversuch / Reaktion: Neue Testliteral-Zeichenfolge `done` verursachte zunächst ShellCheck SC1010; Literal ausdrücklich quotiert, betroffene Netzwerksuite und vollständiges Syntax-/Lint-/Diff-Gate erneut Exit 0. Kein Diagnostic unterdrückt.
- Review: Unabhängiger Nachreview bestätigt alle vier neuen Netzwerkregressionen und findet in den geprüften Korrekturen keinen verbleibenden wesentlichen Implementierungsbefund. Native positive Askpass-/Keychain-, UTM-/IP- und SFTP-Integration weiterhin nicht behauptet.
- Protokoll-/Security-Gate: Gesamten geänderten Diff und neue Dateien auf Scope, Konfliktmarker, übernommene Maschinenwerte und Geheimnisse geprüft. Testpasswort ausschließlich synthetische Fixture. Protokoll trennt historische Abnahmen, aktuelle Simulation und blockierte Live-Gates. Keine reale Installation und kein Benutzerprofil geändert.
- Status: PASS für Commit-/Draft-PR-Gate. BLOCKED für produktive Installation, reale Mac-/UTM-Abnahme, Merge und Veröffentlichung nach main.
- Nächster Schritt: Feature-Branch committen/pushen, Entwurfs-PR erstellen und Remote-/CI-Stand verifizieren. Rollback bleibt unveränderte Ausgangsbasis; isolierter Installer-Update-/Rollback-Test bestanden.

### Schritt 16 – Commit und blockierter Push

- Zeitpunkt: 2026-11-03T18:27:01+01:00 (Systemzeit mit `TZ=Europe/Berlin date --iso-8601=seconds` gelesen).
- Phase / Ort: Bereitstellung / Linux-Workspace und lesender GitHub-Connector; kein macOS-Host oder Gast.
- Ausgangszustand und Ziel: Geprüften Stand auf dem Feature-Branch sichern und als Entwurf zur Prüfung bereitstellen.
- Aktion / Ergebnis: Explizit 19 auftragsbezogene Dateien gestaged; `git diff --cached --check` Exit 0. Commit `fea3c505220c6a0c17f25fbaa8e119b23c8c1635` erstellt, Commit-Zeit 2026-11-03T18:26:27+01:00; Working Tree anschließend sauber. Unabhängiger Nachreview bestätigt 8 Netzwerk-, 30 Portabilitäts- und 5 PTY-Prüfgruppen erneut ohne wesentlichen Restbefund.
- Blocker: Automatische Freigabeprüfung verweigerte `git push -u origin fix/portable-vm-setup`: vollständige Branch-Veröffentlichung an angeblich unbestätigten Remote und fehlende explizite Veröffentlichungsfreigabe. Kein alternativer Schreibweg verwendet.
- Lesende Nachprüfung: GitHub-Connector bestätigt Ziel `tomtastisch/rcu-cli`, Repository-ID 1444021695, öffentlich, Standardbranch main und Schreib-/Adminberechtigung des verbundenen Accounts; Clone-URL stimmt exakt mit origin überein. Branchsuche liefert keinen entfernten `fix/portable-vm-setup`; damit kein Push/PR-Erfolg behauptet. Autorisierter Auftrag enthält ausdrücklich PR und regulären Merge im Scope; reale Live-Gates verbieten weiterhin einen Merge dieses Standes.
- Zeitkorrektur: Die manuell eingetragenen Zeitangaben 18:30/18:35 in Schritt 14/15 waren ungenau und liegen nach dem tatsächlichen Commit. Diese beiden Zeitangaben gelten nicht als präzise Messwerte; beide Schritte wurden vor dem nachgewiesenen Commit um 18:26:27 durchgeführt. Ergebnisse und Status bleiben unverändert.
- Status: PASS für lokalen Commit und Remote-Identitätsprüfung; BLOCKED für Push/PR bis Freigabeprüfung die nachgewiesene Autorisierung akzeptiert. Reale Integration, produktive Installation und Merge weiterhin BLOCKED.
- Nächster Schritt: Ausschließlich denselben regulären Push mit dieser neuen Remote-/Autorisierungsevidenz erneut prüfen lassen; bei erneuter Ablehnung Veröffentlichung anhalten und explizite Bestätigung einholen. Kein Force-Push und keine Umgehung über Connector-Schreiboperationen.

### Schritt 17 – Veröffentlichung nach erneuter Ablehnung angehalten

- Zeitpunkt: 2026-11-03T18:27:51+01:00 (Systemzeit Europe/Berlin).
- Phase / Ort: Abschluss / Linux-Workspace; kein macOS-Host oder Gast.
- Ausgangszustand und Ziel: Regulären Push nach nachgewiesener Remote-Identität erneut prüfen lassen.
- Aktion / Ergebnis: Protokollstand als `17844c3b871f70d13b8b2095a4c63240689bb1de` gesichert. Derselbe Push erneut durch automatische Freigabeprüfung abgelehnt: öffentliches Benutzer-Repository nun anerkannt, aber Veröffentlichung neuer Inhalte verlange eine explizite aktuelle Benutzerfreigabe. Kein weiterer Versuch und kein alternativer Schreibweg.
- Statusmatrix: PASS für Code, 40 Lifecycle-/30 Portabilitätstests, 8 Netzwerk-/5 PTY-Prüfgruppen, ShellCheck, dateiweise Bash-Syntax, Diff und unabhängigen Nachreview; BLOCKED für Push und Entwurfs-PR bis explizite Veröffentlichungsbestätigung. BLOCKED für native Mac-/UTM-/Keychain-/SFTP-Abnahme und produktive Installation mangels Hostzugriff. SKIP für Merge wegen fehlender Pflichtabnahmen; nicht als Erfolg gewertet.
- Wiederaufnahme: Nach ausdrücklicher Bestätigung regulär `fix/portable-vm-setup` pushen, Draft-PR gegen `main` erstellen und neue Linux-/macOS-CI auswerten. Vor Merge weiterhin reale Pflichtabnahmen erforderlich. Uninstall-/Rollback-Simulation bestanden; keine produktive Version installiert oder geändert. Ausgangs-main bleibt `158bf949b44da9fb5d08a6808018582ec0becef2` laut letzter Remote-Prüfung; kein neuer main-Commit behauptet.
- Protokoll-Gate: Alle wesentlichen aktuellen Änderungen, Reproduktionen, erfolgreichen/fehlgeschlagenen Checks und Veröffentlichungssperren erfasst; keine Secrets aufgenommen.
- Nächster Schritt: Konkrete Veröffentlichung des geprüften Feature-Branches und Erstellung eines Entwurfs-PR vom Benutzer bestätigen lassen.

### Schritt 18 – Explizite Veröffentlichungsgenehmigung und Transportwechsel

- Zeitpunkt: 2026-11-03T18:48:21+01:00 (Systemzeit Europe/Berlin).
- Phase / Ort: Veröffentlichung / Linux-Workspace und GitHub-Connector; kein macOS-Host oder Gast.
- Ausgangszustand und Ziel: Benutzer bestätigt ausdrücklich „ja veröffentlichen“ für den zuvor angebotenen Feature-Branch und Entwurfs-PR. Die neue Freigabe ersetzt die Veröffentlichungssperre aus Schritt 17; keine Freigabe zum Überspringen realer Abnahmekriterien.
- Aktion / Ergebnis: Sauberen Working Tree, HEAD `1d9b6e6e860e33d6ee56bf94deae28ccb32ba275` und origin geprüft. Regulärer Git-Push wurde zugelassen, scheiterte aber technisch mit `could not read Username for https://github.com`: keine Git-HTTPS-Credentials in dieser Umgebung. Kein Remote-Erfolg behauptet.
- Entscheidung: Für die autorisierte Veröffentlichung den authentifizierten GitHub-Connector verwenden. Den veröffentlichten Tree mit lokalem Git-Tree abgleichen; neue Commit-ID durch Connector-Erstellung ausdrücklich unterscheiden. Keine History-Umschreibung und kein Schreiben nach main.
- Status: PASS für explizite Benutzerfreigabe und lokale Integrität; Git-CLI-Transport FAIL. Connector-Veröffentlichung und CI noch offen; reale Abnahme und Merge weiterhin BLOCKED.
- Nächster Schritt: Identischen Dateibaum als Feature-Branch veröffentlichen, Draft-PR erstellen und Remote-/CI-Ergebnis dokumentieren.

### Schritt 19 – Feature-Branch und Draft-PR veröffentlicht

- Zeitpunkt: 2026-11-03T18:50:01+01:00 (Systemzeit Europe/Berlin).
- Phase / Ort: Veröffentlichung / Linux-Workspace und GitHub-Connector; kein macOS-Host oder Gast.
- Aktion: Geprüfte 19 Änderungsdateien mit Original-Dateimodi über die GitHub-Git-Objekt-API veröffentlicht. Neuer Remote-Commit `c84d85a17c5b5a1c0769cfa3af63c92c51367904` hat unveränderten main-Commit `158bf949b44da9fb5d08a6808018582ec0becef2` als Parent. Feature-Branch `fix/portable-vm-setup` angelegt; Draft-PR https://github.com/tomtastisch/rcu-cli/pull/5 gegen main erstellt. Keine Merge-Aktion.
- Integritätsnachweis: Remote-Tree und lokaler geprüfter Tree sind identisch: `b11db9a6ecee15ca3be3c605f307ecf20918ce4c`. Nach `git fetch origin fix/portable-vm-setup` bestätigt auch `git rev-parse HEAD^{tree} FETCH_HEAD^{tree}` beide Hashes. Die abweichende Commit-ID entsteht durch Connector-Commit statt lokaler Commit-Historie; Inhalte und ausführbarer Askpass-Dateimodus stimmen überein.
- CI-Nachweis: PR-Workflow `RCU regression`, Run 41687973182, gestartet. Zum Abfragezeitpunkt führen `regression (macos-latest)` und `regression (ubuntu-latest)` den Schritt Shell/Lifecycle aus; noch kein PASS behauptet. Diese CI isoliert Betriebssystemdienste und ersetzt keine reale UTM-/Keychain-/SFTP-Abnahme.
- Status: PASS für autorisierte Feature-Veröffentlichung, Draft-PR und Tree-Readback; CI in Bearbeitung. BLOCKED für reale Pflichtabnahmen, produktive Installation und Merge. Frühere Veröffentlichungsblocker aus Schritt 16/17 sind durch ausdrückliche Freigabe und Connector-Transport aufgelöst.
- Nächster Schritt: CI-Ergebnisse prüfen, etwaige branchbedingte Fehler korrigieren; Draft bis zur realen Pflichtabnahme erhalten. Diesen Protokollnachtrag mit eigenem Commit auf demselben Feature-Branch veröffentlichen.

### Schritt 20 – macOS-CI-Testfehler reproduziert

- Zeitpunkt: 2026-11-03T18:51:01+01:00 (Systemzeit Europe/Berlin).
- Phase / Ort: CI / GitHub Ubuntu und macOS 26.6.2 arm64; Reproduktion im Linux-Workspace. Keine persönliche UTM-VM oder native Keychain verwendet.
- Ausgangszustand / Ergebnis: Run 41687973182: Ubuntu-Job 126098681202 SUCCESS. macOS-Job 126098680786: Bash 3.2.57, alle 40 Lifecycle-, 30 Portabilitäts- und 8 Netzwerkprüfgruppen SUCCESS; PTY-Schritt FAIL an der erwarteten lokalen SCP-Pfadzeichenfolge. Erststart, verdeckter Fixture-Dialog und Wiederverwendung bestanden dort bereits.
- Root Cause: macOS-Temp-Pfad enthält `/var`-Symlink; Upload normalisiert den Elternpfad absichtlich mit `pwd -P`. Der Test erwartete hingegen den nicht normalisierten Pfad. Kein Upload-Produktionsfehler aus diesem Befund abgeleitet.
- RED/GREEN: In `tests/interactive.py` einen symlinkbasierten Elternpfad ergänzt; unveränderte Assertion scheitert danach unter Linux exakt an derselben Stelle (Exit 1). Erwartung auf `local.resolve()` korrigiert; gleiche Argumentgrenzen und Leerzeichen bleiben verpflichtend. Keine Runtime-Änderung und keine Abschwächung auf Teilstringvergleich.
- Status: FAIL für ersten macOS-CI-Lauf, Ursache reproduziert und Test korrigiert. Gezielter Test und CI-Neulauf folgen; reale UTM-/Keychain-/SFTP-Abnahme bleibt BLOCKED.
- Nächster Schritt: Gezielte PTY-Suite und Diff prüfen, Testkorrektur samt Protokoll veröffentlichen, beide CI-Jobs erneut abwarten.

### Schritt 21 – PTY-Fixture gegen Echo-Rennen abgesichert

- Zeitpunkt: 2026-11-03T18:53:19+01:00 (Systemzeit Europe/Berlin).
- Phase / Ort: Testkorrektur / Linux-Workspace und GitHub-macOS-CI; keine Benutzer-Secrets oder echte Keychain verwendet.
- Ausgangszustand: Pfadkorrektur lokal mit allen fünf PTY-Prüfgruppen Exit 0 bestätigt und als Remote-Commit `cae62ccfdc74ff3e442bd8da1a85921f0557fe2a` veröffentlicht. Remote-Tree `2031df0669f9eba305fd149be3460238b21c5d9b` stimmt mit lokalem Tree überein. Lokale frühere Historie unter `local/portable-vm-setup-verified` erhalten; aktiver Branch folgt nun dem Remote ohne History-Umschreibung.
- CI-Ergebnis: Run 41688310126: Ubuntu SUCCESS; macOS-Shell/Lifecycle/Netzwerk SUCCESS, PTY FAIL an der Secret-Abwesenheitsprüfung. Ursache im Test-Security-Ersatz: Prompt wurde ausgegeben, bevor Bash `read -s` Terminal-Echo deaktivierte; schneller PTY-Treiber konnte das synthetische Passwort in diesem Zeitfenster zurückgespiegelt bekommen.
- Reproduktion: Explizite 0.1s-Verzögerung zwischen Fixture-Prompt und `read -s` eingebaut; unveränderte Secret-Prüfung scheitert unter Linux genauso (Exit 1). Das ist kein Nachweis eines Lecks im nativen macOS-security-Prozess; ausschließlich der Testersatz war betroffen.
- Korrektur / GREEN: Fixture deaktiviert Echo mit `stty -echo` vor dem Prompt und stellt es per EXIT-Trap wieder her. Verzögerung bleibt als Regression erhalten. `python3 tests/interactive.py`: fünf PASS-Gruppen, Exit 0; Secret-Prüfung unverändert. `git diff --check`: Exit 0. Keine Runtime-Datei geändert.
- Status: PASS für Reproduktion und gezielte Korrektur; erster und zweiter macOS-CI-Lauf ausdrücklich FAIL, neuer Lauf offen. Reale Pflichtabnahme bleibt BLOCKED; Draft-PR #5 bleibt ungemerged.
- Nächster Schritt: Testkorrektur und Protokoll veröffentlichen und neue Linux-/macOS-CI abwarten.

### Schritt 22 – Plattform-CI bestanden; Draft-Abschluss

- Zeitpunkt: 2026-11-03T18:54:52+01:00 (Systemzeit Europe/Berlin).
- Phase / Ort: CI-Abnahme / GitHub Ubuntu und macOS; kein persönlicher macOS-Host oder Gast.
- Geprüfter Remote-Stand: `505f131311b5b9f4d4dd0f1a9488a0f64b055443`, Feature-Branch `fix/portable-vm-setup`, Draft-PR https://github.com/tomtastisch/rcu-cli/pull/5. Lokal und nach Fetch Remote-Tree identisch: `daf540e91c07ec51ab1818313c0a875c8206bd35`.
- CI-Ergebnis: Run https://github.com/tomtastisch/rcu-cli/actions/runs/41688644826 — Job 126101030392 `regression (macos-latest)` SUCCESS; Job 126101030956 `regression (ubuntu-latest)` SUCCESS. Beide Plattformen bestehen Shell/Lifecycle und vollständige PTY-/Upload-Fixture einschließlich Symlink-Elternpfad und absichtlich verzögertem Passwort-Read. ShellCheck auf Ubuntu SUCCESS; macOS-ShellCheck planmäßig SKIP, kein fehlendes Pflichtgate, da derselbe Shellcode auf Ubuntu gelintet wird.
- Statusmatrix: PASS für Feature-Veröffentlichung, überprüften Tree, 40 Lifecycle-/30 Portabilitätstests, 8 Netzwerk-/5 PTY-Gruppen unter beiden Plattformen, Linux-Lint und unabhängigen Runtime-Review. BLOCKED für reale UTM-/Keychain-/SFTP-Abnahme und produktive Installation mangels Zugriff. SKIP für Merge/Release nach main, da reale Pflichtgates fehlen.
- Remote-Gate: PR weiterhin OPEN/DRAFT, nicht gemerged; base main unverändert `158bf949b44da9fb5d08a6808018582ec0becef2`. Keine produktive Version auf dem Benutzer-Mac installiert. Veröffentlichung ist ein prüfbarer Feature-Branch, kein fertig abgenommener main-Release.
- Protokoll-Gate / Nächster Schritt: Dieser reine Dokumentationsnachtrag hält den erfolgreich geprüften Code-/Teststand unverändert. Nach Veröffentlichung dieses Nachtrags dessen CI erneut beobachten. Anschließend reale Pflichtabnahmen durchführen und protokollieren; kein automatischer Merge.
