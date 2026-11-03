# RCU – Remote Control Unit

Version 0.3.0 · modulares Kommandozeilenprogramm für die Steuerung einer vorhandenen UTM-VM unter macOS.

RCU läuft auf dem macOS-Host, nicht innerhalb der Debian-VM. Es nutzt UTM (`utmctl`) und OpenSSH, installiert keine VM und kopiert keine privaten SSH-Schlüssel. `rcu utm stop` fordert ausschließlich einen regulären Shutdown (`utmctl stop --request`) an.

## Direkt von GitHub laden und installieren (macOS-Host)

Voraussetzungen: macOS mit installierter UTM-App, GitHub CLI `gh` (bereits authentifiziert und mit Zugriff auf das **private** Repository `tomtastisch/rcu-cli`), eine vorhandene UTM-VM sowie konfigurierte SSH-Authentifizierung und verifizierter SSH-Host-Key. Die Installation prüft Homebrew und `gum`; fehlende Abhängigkeiten können eine interaktive, gegebenenfalls privilegierte Installation erfordern.

Im normalen **macOS-Terminal** exakt diesen Befehl ausführen:

```sh
rcu_src="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/rcu-from-git.XXXXXX")" && gh repo clone tomtastisch/rcu-cli "$rcu_src/rcu-cli" && /bin/bash "$rcu_src/rcu-cli/install.sh" && "$HOME/.local/bin/rcu" help
```

Der Befehl klont den aktuellen Standardbranch `main` in einen neuen temporären Quellordner und startet den überprüfbaren Installer aus dem lokalen Clone. Er führt **kein** Skript unmittelbar aus einer Netzwerkantwort aus. Anschließend wird der installierte CLI-Einstiegspunkt direkt geprüft. Der temporäre Quellordner wird nicht automatisch gelöscht. Auf dem Ziel-Mac werden ausschließlich die ausdrücklich für RCU vorgesehenen Installationspfade angelegt oder angepasst.

Hinweis: Der Installer verändert bei Bedarf `~/.zshrc`. Ein Kindprozess kann den `PATH` der bereits geöffneten Shell nicht verändern. Öffne bei Bedarf ein neues macOS-Terminal. Eine bestehende Installation wird über versionierte Releases aktualisiert; unbekannte Dateien und Launcher dürfen nicht überschrieben werden.

## Installationspfade

- Launcher: `~/.local/bin/rcu`
- Bundle: `~/.local/share/utm/rcu/releases/<version>`
- Aktiver Release: `~/.local/share/utm/rcu/current`
- Vorheriger Release: `~/.local/share/utm/rcu/previous`
- Private Konfiguration: `~/.config/rcu/config` (0600)
- Bestehende ältere RCU-Backups außerhalb dieses Bundles bleiben unverändert.

## Befehle (macOS-Host)

Der direkte Einstieg startet die VM bei Bedarf, wartet auf authentifizierte
SSH-Bereitschaft und öffnet anschließend die Debian-Shell:

```sh
rcu
```

`exit` beendet nur die SSH-Shell und kehrt zum macOS-Terminal zurück; die VM
bleibt laufen.

| Befehl | Funktion |
| --- | --- |
| `rcu help` | Hilfe |
| `rcu utm status` | UTM- und SSH-Status ohne VM-Start |
| `rcu utm health` | UTM-Status und SSH-Authentifizierung prüfen |
| `rcu utm connect` | SSH-Verbindung testen |
| `rcu utm shell` | Interaktive Debian-Shell öffnen; mit `exit` nach macOS zurückkehren |
| `rcu utm start` | Vorhandene VM starten, danach SSH-Bereitschaft prüfen |
| `rcu utm stop` | Ausschließlich regulären Shutdown anfordern |
| `rcu update <quellverzeichnis>` | Versionierten Release aus einem vertrauenswürdigen lokalen Checkout installieren |
| `rcu rollback` | Auf den vorherigen Release zurückschalten |
| `rcu uninstall` | Launcher entfernen und Bundle archivieren; Konfiguration erhalten |

`rcu update` erwartet ein vollständiges, vertrauenswürdiges RCU-Quellverzeichnis mit `install.sh` und `VERSION` (beispielsweise einen neu geklonten Checkout). Es lädt selbst keine Dateien aus dem Internet nach.

## Konfiguration und Sicherheit

Der Installer übernimmt `config/config.example` nur bei fehlender Benutzerkonfiguration nach `~/.config/rcu/config`. Der Parser verwendet eine Whitelist von Schlüsseln und führt keinen fremden Shell-Code über `source`/`eval` aus. Die Datei darf kein Symlink sein und muss restriktive Berechtigungen besitzen. Der SSH-Client verlangt einen zuvor überprüften Host-Key. Der SSH-Private-Key wird ausschließlich lokal auf dem macOS-Host verwendet.

Installationen verwenden Staging und versionierte Releases mit atomarer Umschaltung des aktiven Links. Ein vorhandener früherer Release bleibt erhalten. Der Uninstaller archiviert das verwaltete Bundle, bewahrt die Konfiguration auf und entfernt nur eigene Launcher-/PATH-Einträge. Ein bekanntes älteres RCU-Rollback-Backup wird dabei nicht verändert.

Die Prozentangaben der CLI beziehen sich auf nachweislich abgeschlossene Prüfschritte, **nicht** auf den numerischen Linux-Bootfortschritt. Während des Bootvorgangs meldet die CLI zusätzlich die verstrichene Wartezeit sowie UTM- und SSH-Zustand. Für den Gast ohne aktiven QEMU Guest Agent kann UTM keinen belastbaren numerischen Bootfortschritt liefern.

## Tests und Nachweisgrenzen

Isolierte Tests (macOS-Host oder Linux mit Mocks):

```sh
/bin/bash tests/smoke.sh
```

Die Tests erzeugen ein temporäres HOME und verwenden simulierte UTM-, SSH-, Homebrew- und gum-Kommandos. Die aktuelle isolierte Suite prüft 40 Fälle mit 0 Fehlern. Zusätzlich wird der direkte `rcu`-Einstieg für eine gestoppte und eine laufende VM geprüft.

Noch nicht vollständig abgenommen sind die produktive Installation vom GitHub-Checkout, die echte interaktive TTY-Darstellung und ein realer regulärer VM-Shutdown. Ein bestandener Mock-Test ersetzt diese Prüfungen nicht.
