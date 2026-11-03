# RCU – Remote Control Unit

Version 0.4.0 · Terminal-Launcher für eine vorhandene UTM-VM unter macOS.

RCU wählt eine tatsächlich registrierte VM aus, startet sie bei Bedarf, ermittelt ihre Adresse und öffnet eine SSH-Shell. `exit` kehrt zum Mac zurück und lässt die VM laufen. Keine IDE, keine vorgegebene VM, kein bestimmter Benutzer und kein mitgelieferter SSH-Schlüssel erforderlich.

## Installation

Das GitHub-ZIP entpacken und im entpackten Projektverzeichnis auf dem Mac ausführen:

```sh
/bin/bash install.sh
"$HOME/.local/bin/rcu"
```

Alternativ das Repository klonen und dort denselben Installer ausführen. Der Installer prüft UTM, Homebrew und `gum`. Fehlendes Homebrew kann einen nativen Installations-/Berechtigungsdialog öffnen; fehlendes `gum` wird darüber installiert. Bestehende Benutzerkonfiguration wird beim Update erhalten. Bei Bedarf ein neues Terminal öffnen, damit der verwaltete PATH-Eintrag aus `~/.zshrc` greift.

UTM wird über `utmctl` im PATH, `/Applications/UTM.app` oder `~/Applications/UTM.app` gefunden. Ein anderer Installationsort kann explizit über `RCU_UTMCTL_PATH` angegeben werden.

## Einmalige Einrichtung

Beim ersten `rcu` oder ausdrücklich mit `rcu setup`:

1. Registrierte UTM-VM wählen. Bei genau einer VM übernimmt RCU deren UUID; bei mehreren erscheint eine Auswahl mit den aktuellen Namen. Die Einrichtung startet keine VM.
2. Den Benutzernamen innerhalb des Gasts eingeben.
3. Passwort über macOS-Keychain oder einen vorhandenen SSH-Agenten/Schlüssel auswählen. Das Passwort wird verdeckt durch den nativen `security`-Prompt eingegeben und bestätigt. Es erscheint weder in Argumenten, Umgebungsvariablen, Konfigurationsdatei noch RCU-Ausgaben.
4. Beim ersten SSH-Kontakt die angezeigten Host-Fingerprints mit `/etc/ssh/ssh_host_*_key.pub` im Gast vergleichen und ausdrücklich mit `yes` bestätigen. Ohne Bestätigung erfolgt kein Login.

Spätere Starts verwenden das gespeicherte Profil und den Keychain-Eintrag. macOS darf weiterhin eine Keychain-/Automation-Freigabe verlangen. Eine Passwortänderung wird mit `rcu setup` übernommen. SSH-Agenten und Schlüssel werden nicht erzeugt, kopiert oder im Gast autorisiert.

Ein Server mit ausschließlich `publickey`-Authentifizierung verlangt einen dort autorisierten Schlüssel auf dem Mac oder im SSH-Agenten. Ein Keychain-Passwort aktiviert keine Passwortanmeldung auf dem Server. RCU verändert keine Gast-SSH-Konfiguration.

Alte Profile ohne `CONFIG_VERSION=1` werden beim nächsten Start durch die Einrichtung ersetzt. Frühere VM-, IP-, Benutzer- und Schlüsselvorgaben werden dabei nicht übernommen. Alte Klartext-Passwortwerte werden nicht verwendet; die erneute Einrichtung ersetzt die Datei ohne eine Klartext-Sicherung anzulegen. Bei ungültigen alten Profilen bleibt `rcu setup` zur Neuerfassung erreichbar.

Explizite Einrichtung ohne Auswahlfragen, beispielsweise mit vorhandenem Schlüssel:

```sh
rcu setup --vm <registrierte-UUID> --user <Gastbenutzer> --auth agent --key <absoluter-Schlüsselpfad>
```

Ohne `--key` verwendet RCU native OpenSSH-Identitäten und den SSH-Agenten. `--auth keychain` benötigt weiterhin die verdeckte Passworteingabe im Terminal. Passwort-Flags werden abgelehnt.

## Netzwerkerkennung

Die UUID identifiziert die VM. Der aktuelle Anzeigename dient ausschließlich der Darstellung; Umbenennungen unterbrechen den Zugang nicht. Eine entfernte UUID führt zum Fehler und niemals zum stillen Start einer anderen VM.

Nach dem Start wird die IP erneut ermittelt:

1. `utmctl ip-address <UUID>` über den QEMU Guest Agent, mit Zeitlimit.
2. Ohne Agent: MAC-Adressen ausschließlich der ausgewählten VM aus der lesenden UTM-Scripting-Konfiguration; Abgleich mit gültigen macOS-DHCP-Leases.
3. Falls keine passende Lease vorliegt: vorhandene ARP-Zuordnung derselben VM-Netzwerkkarte.

Keine feste IP, kein geratenes Subnetz und kein Netzwerkscan. Gast-Loopback und Link-Local-Adressen werden ausgeschlossen. Mehrere Adressen benötigen eine Auswahl; ohne Terminal bricht RCU ab. Kann UTM weder Gastadressen noch die Netzwerkkonfiguration liefern und besteht keine passende Host-Zuordnung, wird dies als Timeout mit Einrichtungsoption ausgegeben. Der Gast muss SSH betreiben und vom Host erreichbar sein.

Für eine bewusst konfigurierte Portweiterleitung oder einen anderweitig bekannten Zugang gibt es eine ausdrückliche Ausnahme vom Automatikmodus:

```sh
rcu setup --vm <registrierte-UUID> --user <Gastbenutzer> --auth agent --host <Hostadresse> --port <Port>
```

Nur dieses `--host` wird als manuell vorgegebener Zugang gespeichert. Automatisch ermittelte IPs werden nicht persistiert. Host-Keys sind an die VM-UUID gebunden und werden bei geänderter IP weiterhin geprüft; geänderte Schlüssel werden niemals automatisch akzeptiert.

## Dateien vom Mac kopieren

`rcu upload` im macOS-Terminal ausführen. Falls du gerade in der Gast-Shell bist, zuerst `exit` eingeben. Ein lokaler Download liegt auf dem Mac, nicht automatisch im Gast.

```sh
rcu upload "$HOME/Downloads/Beispiele-20261103" '~/'
```

Das Beispielziel kann durch `~/` oder einen anderen Gastpfad ersetzt werden; der Zielordner muss gegebenenfalls bereits existieren. Verzeichnisse werden rekursiv kopiert. Leerzeichen bleiben als Teil des Pfads erhalten. Der Transfer startet die VM bei Bedarf und verwendet dieselbe Netzermittlung, Keychain-/Agent-Anmeldung und Host-Key-Prüfung wie der Terminalstart. SCP verwendet ausdrücklich SFTP und die Portoption `-P`. Ein Gast ohne SFTP-Unterstützung führt zu einem Fehler; es gibt keinen stillen Rückfall auf Remote-Shell-Interpolation.

## Befehle

| Befehl | Wirkung |
| --- | --- |
| `rcu` | VM starten, SSH prüfen, Terminal öffnen |
| `rcu setup` | VM und Gastzugang erfassen oder ersetzen |
| `rcu --version` | Release anzeigen |
| `rcu help` | Hilfe |
| `rcu utm status` | Inventar lesen; kein VM-Start, Setup oder SSH-Login |
| `rcu utm start` | Bei Bedarf starten und SSH prüfen |
| `rcu utm connect` | Laufende VM und SSH prüfen |
| `rcu utm shell` | Terminal einer laufenden VM öffnen |
| `rcu utm health` | UTM und authentifizierten SSH-Zugang prüfen |
| `rcu utm stop` | Ausschließlich regulären Shutdown anfordern |
| `rcu upload SRC DEST` | Datei/Verzeichnis vom Mac in den Gast übertragen |
| `rcu update DIR` | Vertrauenswürdigen lokalen Quellstand installieren |
| `rcu rollback` | Vorherigen verwalteten Release aktivieren |
| `rcu uninstall` | Installation archivieren; Profil und Keychain behalten |

Die Oberfläche verwendet kompakte `gum`-Karten und Auswahldialoge sowie eine aktualisierte Statusanzeige mit verstrichener Zeit, VM-Zustand und SSH-Status. Ohne TTY gibt es einfache Textausgabe. Es werden keine Boot-Prozentwerte erfunden.

## Speicherung und Rollback

- Launcher: `~/.local/bin/rcu`
- Unveränderliche Releases: `~/.local/share/utm/rcu/releases/<version>`
- Aktiver/vorheriger Release: `current` / `previous` im selben Verzeichnis
- Profil: `${XDG_CONFIG_HOME:-~/.config}/rcu/config`, Modus 0600
- Host-Keys: `known_hosts` neben dem Profil, Modus 0600
- Passwort: macOS-Keychain, Service `rcu.vm.<UUID>`, Account `<Gastbenutzer>`

Der Parser interpretiert Daten ohne `source` oder `eval`. Unbekannte Konfigurationsschlüssel, unsichere Werte und Symlinks werden abgelehnt. Installationen prüfen das Bundle vor atomarer Umschaltung. Geänderte Inhalte dürfen keine bestehende Release-Version überschreiben. Uninstall entfernt nur verwaltete Installationsartefakte und archiviert Releases.

Rollback schaltet den Code zurück und verändert keine Zugangsdaten. Releases vor 0.4.0 verstehen die neue Profilsemantik nicht: Ein erfolgreicher Versionswechsel ist kein Nachweis, dass ein alter Release mit dem neuen Profil funktioniert. Für die Portabilitätsreparatur ist ein erneutes Update auf den geprüften neuen Stand der sichere Wiederanlauf; keine automatische Klartext-Konfigurationssicherung.

## Prüfungen

```sh
/bin/bash tests/smoke.sh
/bin/bash tests/portable.sh
/bin/bash tests/network.sh
python3 tests/interactive.py
```

Die Tests isolieren HOME und externe Dienste. Die PTY-Suite prüft den echten CLI-Dialog mit simuliertem UTM, Keychain, OpenSSH und gum, inklusive Erststart, Wiederverwendung, Dateitransfer und Fehlercodes. Sie ersetzt weder native Keychain-Integration noch einen realen UTM-/Gast-Test. Python wird nur für diesen Entwicklungstest benötigt, nicht für RCU.

Reale macOS-/UTM-, Guest-Agent-/DHCP-/ARP-, Keychain-, SFTP- und Shutdown-Abnahmen sind separat im [Arbeitsprotokoll](docs/ARBEITSPROTOKOLL.md) ausgewiesen. Ein Mock-Test belegt keine produktive Installation.
