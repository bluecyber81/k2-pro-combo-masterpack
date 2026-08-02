# K2 Pro Combo: CFS- und Motorcontroller-Studie

Stand: 2026-08-01  
Zielgeraet: Creality K2 Pro Combo, Modellkennung F012 / Board CR0CN200400C10  
Arbeitsweise: Live-System nur lesend untersucht. Es wurden keine CFS-, Motor-, Bewegungs-, Kalibrier-, Flash- oder Heizbefehle ausgefuehrt.

## 1. Kurzfazit

1. Das CFS und die geschlossenen Druckermotoren sind zwei getrennte Steuerungssysteme.
2. Die CFS-Material- und Verbindungsmotoren werden vom CFS-Mikrocontroller ueber den proprietaeren RS485-Befehlssatz gesteuert.
3. `motor_control` verwaltet beim K2 Pro die geschlossenen X-, Y- und E-Regelkreise. Z und Z1 sind in der vorhandenen F012-Konfiguration bewusst deaktiviert.
4. Beide Systeme treffen sich funktional am Filamentweg: CFS-Sensoren und -Motoren liefern Filament, der E-Motor zieht es durch den Extruder. Ein Stau kann deshalb Fehler in beiden Bereichen ausloesen.
5. Der Live-Stand ist gesund:
   - CFS verbunden, Firmware 1.5.0, Updatezustand `done`.
   - Zwei externe Motorcontroller melden `mot2_023_C30-mot2_002_081`, jeweils `update: done`.
   - Der Extrudercontroller meldet `mot2_022_C30-mot2_002_081`.
   - Moonraker/Klipper meldet `motor_ready: true`, `is_homing: false` und keine aktiven Motor-Fehlercodes.
6. Der Kommentar `FW: ...071.bin` in `motor_control.cfg` ist veraltet. Die tatsaechlich installierte und beim Boot erkannte Motor-Firmware ist `081`. Das ist ein Dokumentationsfehler, kein fehlgeschlagenes Update.
7. Fremde K2-Plus-`tool.cfg`-Dateien und direkte `BOX_SEND_DATA`-/`MOTOR_*`-Schreibbefehle duerfen nicht auf diesen K2 Pro uebernommen werden. Sie umgehen die aktuelle 1.1.6.7-/CFS-1.5.0-Orchestrierung.

## 2. Verifizierter Live-Stand

| Bereich | Verifizierter Stand | Bewertung |
|---|---|---|
| Drucker | K2 Pro, F012, Board CR0CN200400C10 | Exakt passendes Modell |
| Druckzustand | `standby`, Heizungsziele 0 C | Sicher fuer lesende Analyse |
| CFS | verbunden, Typ `CFS`, Version 1.5.0 | OK |
| CFS Firmware-ID | `cfs0_050_G32-cfs0_000_150` | `update: done` |
| X/Y-Motorcontroller | zwei RS485-Geraete, App-Version 081 | beide `update: done` |
| Extrudercontroller | `mot2_022_C30-mot2_002_081` | erkannt und aktuell zum installierten Paket |
| Haupt-MCU | `mcu0_120_G32-mcu0_001_000` | Boot erfolgreich |
| Nozzle-MCU | `noz0_130_G30-noz0_021_000` | Boot erfolgreich |
| `motor_control` | `motor_ready: true` | OK |
| CFS-Bus | `/dev/ttyS5`, 230400 Baud | aktiv |
| CFS-Pro | Firmwareunterstuetzung vorhanden, aber kein CFS-Pro angeschlossen | dormant, nicht verwenden |

Die Datumsangabe `2020-01-01` im sehr fruehen MCU-Update-Log ist die Startzeit vor der Zeitsynchronisation des Linux-Systems. Sie ist kein Firmwaredatum.

## 3. Untersuchungsmethode

Verwendet wurden:

- Moonraker-Objektabfragen fuer `print_stats`, `box`, `filament_rack` und `motor_control`.
- Lesende SSH-Abfragen von Configs, Versionsdateien und Logs.
- SHA-256-Vergleich der installierten Python-Erweiterungen.
- `strings`, `readelf` und dynamische Symbolanalyse der kopierten ARM-Binaermodule.
- Lokale, isolierte ARM-Ausfuehrung mit QEMU. Dabei wurden Klipper-Laufzeitobjekte durch inerte Platzhalter ersetzt. Keine serielle Schnittstelle und kein Druckerobjekt war erreichbar.
- Vergleich mit aktuellen Checkouts der offiziellen Creality-Quellen und relevanter Community-Projekte.

Die Offline-Analyse konnte reale Enums, Funktionscodes, Methodensignaturen und Fehlerlisten aus `box_wrapper` und `motor_control_wrapper` auslesen, ohne die Klassen gegen den Drucker zu instanziieren.

## 4. Architektur

### 4.1 CFS-Pfad

```text
Creality Print / G-Code
        |
        v
M8200 und offizielle BOX_* Makros
        |
        v
box.py -> box_wrapper.cpython-39.so
        |
        v
serial_485 / auto_addr
        |
        v
/dev/ttyS5, 230400 Baud
        |
        v
CFS-MCU -> Materialmotoren, Verbindungsmotor,
           RFID, Messrad, Filamentsensoren, Buffer
```

### 4.2 Geschlossene Druckermotoren

```text
Klipper Bewegungsplanung
        |
        +--> X/Y Step/Dir + motor_control Schutz/Feedback
        |                 -> externe Closed-Loop-Controller
        |
        +--> E Step/Dir + Nozzle-MCU PB12 Stall/Schutz
                          -> Extruder-Closed-Loop-Controller
```

`motor_control` ist nicht die Geschwindigkeitsregelung der CFS-Spulenmotoren. Die CFS-Motoren gehoeren zum CFS-MCU und werden ueber `box_wrapper` angesprochen.

### 4.3 Gemeinsamer Fehlerpfad

Der funktionale Zusammenhang ist:

```text
CFS-Spule -> CFS-Materialmotor -> CFS-Verbindung -> PTFE
          -> Werkzeugkopf-Filamentsensor -> E-Motor -> Duese
```

Ein Filamentstau kann deshalb als CFS-Segmentfehler, als E-Motor-Tracking-/Ueberstromfehler oder als Kombination erscheinen. Der Wrapper enthaelt dafuer Ereignisse wie `extruder_motor_err_state`, `extruder_motor_retry` und `box:handle_motor_extruder_error`.

## 5. RS485-Protokoll des CFS

### 5.1 Rahmen

Der aus dem installierten Code rekonstruierte Rahmen ist:

```text
Byte 0  Kopf       0xF7
Byte 1  Adresse
Byte 2  Laenge
Byte 3  Status
Byte 4  Funktion
Byte 5+ Nutzdaten
Letztes Byte CRC8
```

CRC8 verwendet das Polynom `0x07`. In der Auto-Address-Implementierung wird die Pruefsumme ueber Laenge, Status, Funktion und Nutzdaten gebildet, nicht ueber Kopf und Adresse.

`buf_len = 0` bedeutet in einem normalen Report, dass nach dem Verarbeiten kein unvollstaendiger Rest im Empfangspuffer liegt. Das ist kein Fehler.

### 5.2 Auto-Addressing

| Funktion | Code | Bedeutung |
|---|---:|---|
| Slave-Adresse setzen | `0xA0` | Adresse einer gefundenen Einheit zuweisen |
| Slave-Info lesen | `0xA1` | Typ, UUID und Modus ermitteln |
| Online-Check | `0xA2` | periodischer Heartbeat |
| Adresstabelle lesen | `0xA3` | bekannte Zuordnung pruefen |
| Loader zu App | `0x0B` | Bootloader verlassen |

Bekannte Geraetetypen:

| Typ | Wert | Broadcast | Vorgesehene Adressen |
|---|---:|---:|---|
| Material Box / CFS | 1 | `0xFE` | `0x01` bis `0x04` |
| Closed-Loop Motor | 2 | `0xFD` | im Code `0x81` bis `0x84` vorbereitet |
| Belt-Tension Motor | 3 | `0xFC` | `0x91` bis `0x92` |
| CFS-Pro | 10 | `0xFE` | neue Box-Generation |

Im aktuell laufenden Klipper-`auto_addr` ist nur die Material-Box-Tabelle aktiv. CLM und BTM sind dort auskommentiert. Der fruehe Creality-MCU-Updater erkennt die beiden externen Motorcontroller separat an den Boot-Adressen `0x85` und `0x86`. Diese Boot-/Updater-Adressen duerfen nicht mit den logischen Klipper-Motornummern gleichgesetzt werden.

Der bestehende lokale Poll-Abstand von 10 Sekunden reduziert unnoetige CFS-Loglast. Einzelne Timeout-Zeilen bei Broadcast-Suche oder nicht belegten Adressen sind erwartbar. Entscheidend sind Onlinezustand, Folgeantworten und das Fehlen schwerer Fehler.

## 6. CFS-Funktionscodes

Die folgende Tabelle stammt aus dem aktuell installierten `box_wrapper`.

| Code | Name | Richtung | Risiko bei manueller Nutzung |
|---:|---|---|---|
| `0x01` | `CREATE_CONNECT` | lesen/Handshake | niedrig, aber nur ueber Wrapper |
| `0x02` | `GET_RFID` | lesen | niedrig |
| `0x03` | `GET_REMAIN_LEN` | lesen | niedrig |
| `0x04` | `SET_BOX_MODE` | schreiben | hoch, aendert Zustandsmaschine |
| `0x05` | `GET_BUFFER_STATE` | lesen | niedrig |
| `0x06` | `CTRL_MATERIAL_MOTOR_ACTION` | schreiben | sehr hoch, bewegt Spulenmotor |
| `0x07` | `CTRL_CONNECTION_MOTOR_ACTION` | schreiben | sehr hoch, bewegt Verbindungsmotor |
| `0x08` | `GET_FILAMENT_AND_BUFFER_STATE` | lesen | niedrig; Alias fuer kombinierten Sensorstatus |
| `0x09` | `SET_MOTOR_SPEED` | schreiben | sehr hoch |
| `0x0A` | `GET_BOX_STATE` | lesen | niedrig |
| `0x0C` | `GET_BOX_MODE` | lesen | niedrig |
| `0x0D` | `SET_PRE_LOADING` | schreiben | hoch |
| `0x0E` | `MEASURING_WHEEL` | lesen/steuern | mittel bis hoch |
| `0x0F` | `TIGHTEN_UP_ENABLE` | schreiben | hoch, beeinflusst Spulenspannung |
| `0x10` | `EXTRUDE_PROCESS` | schreiben | sehr hoch, mehrstufiger Ladeprozess |
| `0x11` | `RETRUDE_PROCESS` | schreiben | sehr hoch, mehrstufiger Entladeprozess |
| `0x13` | `EXTRUDE_PROCESS_MODEL2` | schreiben | sehr hoch, alternative Prozesslogik |
| `0x14` | `GET_VERSION_SN` | lesen | niedrig |
| `0x15` | `GET_HARDWARE_STATUS` | lesen | niedrig |
| `0x18` | `SET_DRY_MODE` | schreiben | nur CFS-Pro, auf Standard-CFS nicht nutzen |
| `0x19` | `GET_DRY_MODE` | lesen | CFS-Pro |
| `0x1A` | `PAUSE_DRY` | schreiben | CFS-Pro |
| `0x1B` | `CONTINUE_DRY` | schreiben | CFS-Pro |
| `0x55` | `COMMUNICATION_TEST` | Testverkehr | nur kontrollierte Diagnose |

### 6.1 Lade- und Entladestufen

Der aktuelle Wrapper modelliert Laden und Entladen als mehrstufige Prozesse. Die Enum-Werte sind nicht einfach fortlaufend:

```text
ExtrudeStage: 1=0, 2=4, 3=5, 4=6, 5=4, 6=7, 7=6
RetrudeStage: 1=0, 2=1, 3=2, 4=1, 5=4
```

Dass mehrere logische Stufen denselben niedrigen Wert verwenden, zeigt: Die Zahl allein beschreibt den Vorgang nicht vollstaendig. Trigger, Slot, Sensorzustand und Wrapper-Kontext gehoeren dazu. Genau deshalb ist ein rohes Paket wie `CMD=16 DATA=...` kein sicherer Ersatz fuer die Herstellerlogik.

Die aktuelle Methodensignatur bestaetigt diese Orchestrierung:

```text
communication_extrude_process(addr, num, trigger='', stage=2,
                              report_err=True, extrude=None)
communication_retrude_process(addr, num, trigger, report_err=True)
```

## 7. Offizieller G-Code-Pfad

Der fuer diesen K2 Pro passende Einstieg ist `M8200`, nicht ein fremdes `tool.cfg`.

| M8200-Parameter | Herstellerpfad |
|---|---|
| `P` | `CR_BOX_PRE_OPT` |
| `C` | `CR_BOX_CUT` |
| `R` | `CR_BOX_RETRUDE`, optional mit Laenge |
| `L I0..I3` | Slot T1A bis T1D, `CR_BOX_EXTRUDE`, danach Abfall/Purge |
| `W` | `CR_BOX_WASTE` |
| `F` | `CR_BOX_FLUSH` |
| `O` | `CR_BOX_END_OPT` |

Der Stock-Start-/Endpfad verwendet ausserdem `BOX_START_PRINT`, `BOX_NOZZLE_CLEAN`, `BOX_END` und `BOX_END_PRINT`. Pause/Resume nutzt die eigene Fehlerfortsetzung. Diese Reihenfolge verbindet CFS-Zustand, Filamentsensor, Cutter, Extruder, Temperatur und Purge.

## 8. CFS-Sensoren und Aktoren

Der Wrapper kennt mindestens:

- vier Materialkanaele je CFS,
- RFID-Leser,
- Restlaengenverwaltung,
- Materialmotor je Slot,
- Verbindungsmotor,
- Messrad,
- Buffer leer/voll,
- Filamentsensoren an CFS und Werkzeugkopf,
- Cutter und Cutter-Hallsensor,
- Spulenspannung/Tighten-Up,
- Preloading,
- Auto-Refill,
- Fehlerfortsetzung,
- bei CFS-Pro zusaetzlich Trocknungszustand, Temperatur und Feuchte.

Der Live-Status `mode: 0` bedeutet, dass die Lade-/Entlade-Zustandsmaschine im Leerlauf ist. Er beweist nicht, dass jede interne Motorendstufe physisch stromlos ist.

## 9. CFS-Fehlerbild und mechanische Zuordnung

Die aus dem Live-Wrapper rekonstruierten Fehlercodes sind Funktionen des Codes, nicht aktuell aktive Fehler.

| Key | Bedeutung / wahrscheinlich betroffener Abschnitt |
|---:|---|
| 831 | RS485-Timeout |
| 834 | ungueltiger Parameter |
| 835 | Blockade an der CFS-Verbindung |
| 836 | Blockade Verbindung bis Filamentsensor |
| 837 | Blockade Filamentsensor bis Extruderzahnrad |
| 838 | Verbindung passiert, aber keine Extrusion |
| 839 | kein Filament an CFS-Extrusionsposition |
| 840 | Box-Modus passt nicht zum erwarteten Zustand |
| 841 | Cutter-Sensor oder Rueckstellung fehlerhaft |
| 843 | RFID-Fehler |
| 844 | Pneumatikanschluss/PTFE auffaellig oder geknickt |
| 845 | Duese blockiert |
| 846 | CFS-Geschwindigkeit kleiner als Extrudergeschwindigkeit |
| 847 | Filament/Spule wickelt sich unguenstig |
| 848 | Filamentbruch an Verbindung |
| 849 | Verbindung beim Rueckzug nicht verlassen |
| 850 | Rueckzug unklar oder mehrere Verbindungen ausgeloest |
| 851 | Buffer-leer beim Rueckzug nicht erreicht |
| 852 | Sensorzustaende widerspruechlich |
| 853 | Feuchtesensorfehler |
| 855 | Cutterposition unplausibel |
| 856 | Cutter fehlt/nicht erkannt |
| 857 | Motorlastfehler |
| 858 | EEPROM-Fehler |
| 859 | Messradfehler |
| 860 | Bufferfehler |
| 861/862 | RFID-Kartenfehler |
| 863 | Rueckzug abgeschlossen, Werkzeugkopf-Sensor erkennt weiter Filament |
| 864 | Laden erreicht Buffer-voll nicht |
| 865 | Verbindung beim Laden/Entladen nicht verlassen |
| 870-875 | CFS-Pro-Trocknungsfehler |
| 890 | RFID-Slotfehler |

Fuer eine Diagnose sollte immer zuerst der Abschnitt bestimmt werden: Spule, CFS-Ausgang, PTFE, Fuenfwegeverteiler, Werkzeugkopf-Sensor, Extruder oder Duese. Ein blindes Erhoehen von Motorgeschwindigkeit oder Zugkraft verschiebt den Fehler oft nur und kann Filament oder Cutter belasten.

## 10. Motorcontroller des Druckers

### 10.1 Was geregelt wird

Aktiv ist:

```ini
motor_closed_loop: x,y,e
```

X und Y besitzen externe geschlossene Regler. E wird ueber die Nozzle-MCU eingebunden; sein Stall-/Schutzeingang ist `nozzle_mcu:PB12`. Z und Z1 sind in dieser F012-Konfiguration kommentiert und duerfen nicht aus einer K2-Plus-Konfiguration aktiviert werden.

Die gefundenen Parameter zeigen eine kaskadierte geschlossene Regelung mit:

- Positionsregelkreis,
- Geschwindigkeitsregelkreis,
- Stromregelkreis,
- Encoderfeedback,
- `id`-/`iq`-Rueckmeldung,
- Feedforward,
- LESO-Beobachter,
- Feldschwaechungs- und Filterparametern,
- SVPWM-/Chopperparametern,
- Ueberstrom-, Geschwindigkeits-, Positions-, Spannungs- und Temperaturschutz.

Die Bezeichnungen sprechen stark fuer eine FOC-/Vektorregelungsarchitektur. Das ist eine technische Ableitung aus den Parametern; Creality dokumentiert den internen Regelalgorithmus nicht vollstaendig offen.

### 10.2 Aktive F012-Reglerwerte

X und Y sind gleich konfiguriert:

| Parameter | Wert |
|---|---:|
| Positions-Kp | 300 |
| Geschwindigkeits-Kp | 0.028 |
| Geschwindigkeits-Ki | 6.0 |
| Strom-Kp | 2.5 |
| Strom-Ki | 200.0 |
| LESO b0k | 1.0 |
| LESO z3k | 0 |
| LESO wp/ws | 4000 / 4000 |
| LESO wd | 400 |
| max. Trackingfehler | 0.3 |
| Trackingfehler-Zeit | 0.1 s |
| Wiederholungen | 4 |
| Cutter-Offset | 0.4 mm |
| Overcurrent-Sonderumschalter | 0 |

Diese Werte sind Herstellerwerte der installierten F012-Fassung. Es gibt keinen belastbaren Grund, sie mit Werten eines K2 Plus oder eines fremden Closed-Loop-Boards zu ersetzen.

### 10.3 Niedrige Motor-Protokollbefehle

| Code | Name | Wirkung | Einstufung |
|---:|---|---|---|
| `0x01` | `reboot` | Controller neu starten | rot |
| `0x03` | `encoder_calibrate_official` | Encoder-Magnetkalibrierung | rot |
| `0x04` | `elec_offset_calibrate` | elektrischen Winkel kalibrieren | rot |
| `0x05` | `control` | Motor aktiv steuern | rot |
| `0x06` | `sys_param` | Systemparameter lesen/schreiben | rot bei Schreibzugriff |
| `0x07` | `flash_param` | Flashparameter lesen/schreiben | rot |
| `0x08` | `get` | Feedback/Parameter lesen | gelb, nur Wrapper-konform |
| `0x0B` | `boot` | Bootloader starten | rot |
| `0x0C` | `protection` | Schutzstatus/Schutzparameter | gelb bis rot |
| `0x0D` | `systemid` | Motoridentifikation | rot, kann anregen/bewegen |
| `0x0E` | `read485_addr` / `set485_addr` | Adresse lesen oder setzen | Setzen rot |
| `0x0F` | `version` | Version abfragen | gelb; nicht noetig, Bootdatei ist sicherer |
| `0x11` | `stall_mode` | Stall-Pin-Modus umschalten | rot waehrend Betrieb |
| `0x12` | `dev_uuid` | Geraete-ID | gelb |
| `0x13` | `err_detail_data` | Fehlerdetail lesen | gelb |
| `0x14` | `cut_detail_data` | Cutterdetail lesen | gelb |
| `0x15` | `pos_data_sample` | Positionsdaten sampeln | gelb |
| `0x16` | `spd_data_sample` | Geschwindigkeitsdaten sampeln | gelb |

Sichere Feedback-IDs im Wrapper sind `pos_fdb=5`, `spd_fdb=6`, `id_fdb=7` und `iq_fdb=8`. Auch diese sollten nicht durch handgebaute Pakete abgefragt werden, solange der Herstellerwrapper und dessen Timing nicht vollstaendig dokumentiert sind.

### 10.4 Sichtbare G-Code-Oberflaeche

Der Wrapper registriert unter anderem:

- `MOTOR_AUTO_CHECK_PROTECTION`
- `MOTOR_BOOT`
- `MOTOR_CHECK_CUT_POS`
- `MOTOR_CHECK_PROTECTION_AFTER_HOME`
- `MOTOR_CLEAR_ERR_WARN_CODE`
- `MOTOR_CONTROL`
- `MOTOR_ELEC_OFFSET_CALIBRATE`
- `MOTOR_ELEC_OFFSET_CALIBRATE_ALL`
- `MOTOR_ENCODER_CALIBRATE_OFFICIAL`
- `MOTOR_EXTRUDER_RETRY_PROCESS`
- `MOTOR_FLASH_PARAM`
- `MOTOR_READ_ADDR`
- `MOTOR_SET_ADDR`
- `MOTOR_REBOOT`
- `MOTOR_STALL_MODE`
- `MOTOR_SYS_PARAM`
- `MOTOR_VERSION`

Das Vorhandensein eines G-Code-Befehls bedeutet nicht, dass er ein Benutzerwerkzeug ist. Mehrere Befehle sind Produktions-, Service- oder Bootloaderfunktionen. Sie wurden in dieser Untersuchung nicht ausgefuehrt.

### 10.5 Motorfehler und Warnungen

| Key | Typ | Bedeutung |
|---:|---|---|
| 781 | Fehler | Encodersignal springt |
| 782 | Fehler | Encoder kann nicht gelesen werden |
| 783 | Fehler | Software-Peak-Ueberstrom |
| 784 | Fehler | anhaltender Software-Ueberstrom |
| 785 | Fehler | Hardware-Ueberstrom |
| 786 | Fehler | Geschwindigkeitsfeedback laenger ueber Grenzwert |
| 787 | Fehler | Positionsfeedback ausser Grenzwert |
| 788 | Fehler | Positionsbefehl springt unplausibel |
| 789 | Fehler | Positions-Trackingfehler zu gross |
| 790 | Fehler | Widerstand/Induktivitaet unplausibel |
| 791 | Fehler | Sprungantwort wird nicht stabil |
| 792 | Fehler | Motorphase/Motor nicht verbunden |
| 793 | Fehler | Phasenwiderstand weicht stark ab, moeglicher Wicklungsschluss |
| 794 | Fehler | sonstiger Fehler bei Widerstandspruefung |
| 795 | Warnung | Kommunikationsfehler |
| 796 | Warnung | Versorgungsspannung zu niedrig |
| 797 | Warnung | Controller-MCU zu heiss |

Detailpayloads koennen unter anderem Peakstrom, Encoderpulse, Dauerstrom und Zeit, Uebergeschwindigkeit und Zeit, Positionsgrenzen, Befehlssprung sowie Trackingfehler und Zeit enthalten.

## 11. Startverhalten und Parametersynchronisation

Beim Klipper-Start liest `motor_control_wrapper` viele Controllerparameter. Nur als konfigurierbar markierte Werte werden mit der F012-Config verglichen.

Im aktuellen Bootlog wurde fuer X und Y festgestellt:

```text
protection_param_prt_track_err_time: Controller 0.01 s, Config 0.1 s
update_flash_param ... write success
anschliessende Pruefung: is not need override
```

Das ist keine unkontrollierte Fremdaenderung, sondern die vorgesehene Hersteller-Synchronisation von `motor_control.cfg` in den Controllerflash. Danach stimmen beide X/Y-Werte mit 0.1 s ueberein.

Beim E-Pfad erschienen fuer zwei Kalibrierfelder (`param_elec_offset`, `param_phase_order_invert`) beim Start `result is None`. Gleichzeitig gilt:

- Extruder-Firmware 081 wurde erfolgreich erkannt,
- kein Key-781-bis-Key-797-Fehler ist aktiv,
- der Wrapper wurde vollstaendig ready,
- `motor_ready: true`.

Damit sind die beiden Zeilen aktuell als nicht gelieferte/auf diesem Transportweg nicht lesbare Felder zu werten, nicht als nachgewiesener E-Motorfehler. Ein zusaetzlicher Kalibrierlauf waere ohne konkreten Druckfehler nicht gerechtfertigt.

## 12. Firmware- und Updateablauf

Der OpenWrt-Dienst `/etc/init.d/mcu_update` startet frueh beim Booten und ordnet beim F012 zu:

| Funktion | Schnittstelle / Pfad |
|---|---|
| Haupt-MCU | `/dev/ttyS2` |
| Nozzle-MCU | `/dev/ttyS3` |
| Extrudercontroller | transparent ueber Nozzle-MCU |
| externe Motorcontroller und CFS | RS485 `/dev/ttyS5`, 230400 Baud |
| Firmwarewurzel | `/usr/share/klipper/fw/F012` |

Der Updater:

1. liest Hardware- und App-Version,
2. sucht genau eine zum Hardwarepraefix passende Datei,
3. vergleicht die App-Suffixe,
4. aktualisiert nur bei Abweichung, ungueltiger Version oder explizitem Force-Flag,
5. startet die App und schreibt den Status nach `/tmp/.mcu_version` bzw. `/tmp/.485_mcu_version`.

Ein gezieltes CFS-Update wird vom Creality-Upgradeserver mit `CFS=1` und einer temporaeren JSON-Anforderung gestartet. Manuelle Force-Flags duerfen nicht benutzt werden.

### 12.1 Aktuell installierte Payloads

```text
F012 Motor extern: mot2_023_C30-mot2_002_081
F012 Extruder:      mot2_022_C30-mot2_002_081
CFS Standard:       cfs0_050_G30/G32-cfs0_000_150
CFS-Pro-Payload:    cfs6_100_G31-cfs6_220_000 (nur Paketinhalt)
```

Der Bootlog zeigt fuer beide externen Motoren, RFID und CFS `update: done`; es war kein erneutes Flashen erforderlich.

### 12.2 Warum die oeffentlichen Binaries nicht zurueckkopiert werden duerfen

Der aktuell abgerufene Stand des offiziellen GitHub-Repositories enthaelt nur aeltere Payloads:

```text
Motor: App 027 und 040
CFS:   App 113
```

Das Live-Firmwarepaket besitzt App 081 und CFS 150 sowie deutlich neuere Binaerwrapper. Ein Kopieren der oeffentlichen Repo-Binaries auf den Drucker waere ein Downgrade und ist nicht sinnvoll.

## 13. Aenderungen im neueren Box-Wrapper

Verglichen mit dem aelteren lokalen Snapshot sind `motor_control_wrapper`, `serial_485_wrapper` und `filament_rack_wrapper` weitgehend stabil. Der aktuelle `box_wrapper` ist dagegen deutlich groesser.

Neue erkennbare Bereiche sind vor allem:

- CFS-Pro-Geraetetyp,
- Trockenmodus setzen/lesen/pausieren/fortsetzen,
- automatische Feuchte-/Trocknungslogik,
- persistierter Trocknungszustand,
- kombinierter Filament-/Bufferstatus,
- zusaetzliche Lade- und Entladestufen,
- neue Dryer-Fehler 870 bis 875.

Beim angeschlossenen Standard-CFS bleiben CFS-Pro-Trocknungsbefehle inaktiv. Sie duerfen nicht testweise an das Standard-CFS gesendet werden.

## 14. Bewertung der Community-Projekte

### 14.1 MasterLufier Custom Macros

Das Projekt kennzeichnet seine `tool.cfg` selbst als K2-Plus-spezifisch und fuer aeltere Firmware/CFS-Staende getestet. Es sendet unter anderem rohe Pakete wie:

```text
BOX_SEND_DATA ... CMD=16 DATA=...
BOX_SET_BOX_MODE
BOX_RETRUDE_PROCESS
BOX_TIGHTEN_UP_ENABLE
```

Ausserdem ersetzt es Homingteile und schaltet `MOTOR_STALL_MODE` manuell zwischen Modus 1 und 2 um. Auf dem F012 K2 Pro wuerde das aktuelle Wrapperstufen, Cuttergeometrie, Single-Z-Aufbau, Fehlerfortsetzung und CFS-1.5.0-Logik umgehen. Nicht installieren.

### 14.2 k2-unleashed

Das Projekt liefert interessante Ideen fuer lesendes Monitoring und Fehlerhistorie, ist aber aktive Entwicklung und installiert Root-Module, Bewegungs-/Heiztests und eigene Diagnose-G-Codes. Seine eigenen Hinweise warnen vor Hardware- und Brandschaeden. Fuer diesen Drucker sind nur die Architekturideen sinnvoll, nicht die Steuer- oder Auto-Testmodule.

### 14.3 sw3defy Helper

Der Helper-Ansatz ist fuer Backup, Status und reversible Diagnose geeignet. Er sollte bei CFS und Motorcontroller strikt lesend bleiben und keine generischen K2-Plus-Motoraktionen anbieten.

## 15. Sichere Diagnosewege

### Gruen: automatisch und lesend moeglich

- Moonraker `motor_control` auf `motor_ready`, `is_homing` und Cutterstatus pruefen.
- Moonraker `box` auf Verbindung, CFS-Version, Mode und Slots pruefen.
- `/tmp/.485_mcu_version` und `/tmp/.mcu_version` lesen.
- `/tmp/mcu_update.log` nach `update: done`, `fw_update fail` und unerwarteten Wiederholungen auswerten.
- Klipperlog nach Key 781 bis 797 und CFS-Key 831 bis 890 durchsuchen.
- CFS-RS485-Statistik passiv aus dem vorhandenen Log bilden.
- Hashes und Groessen der installierten Wrapper dokumentieren.

### Gelb: nur bei konkretem Anlass und mit Drucker im sicheren Zustand

- Herstellerseitige Versions-/Detailabfragen ueber vorhandene Wrapper.
- Passiver Mitschnitt eines vom Benutzer am Display gestarteten normalen CFS-Wechsels.
- Vergleich von Sensoruebergaengen und Zeiten, ohne Pakete zu injizieren.
- Fehlercode loeschen erst nach Sicherung und nach Beheben der mechanischen Ursache.

### Rot: nicht automatisieren

- `BOX_SEND_DATA` mit selbstgebauten Payloads.
- CFS-Material-/Verbindungsmotor direkt ansteuern.
- CFS-Motorgeschwindigkeit oder Tighten-Up blind aendern.
- `MOTOR_FLASH_PARAM`, `MOTOR_SYS_PARAM` mit Schreibwerten.
- Encoder- oder elektrischen Offset kalibrieren.
- RS485-Adressen setzen.
- Bootloader, Reboot oder Force-Flash ausloesen.
- K2-Plus-`tool.cfg`, Homing-Overrides oder Motorparameter uebernehmen.

## 16. Sinnvolle Helper-Erweiterungen

Aus der Studie lassen sich sichere Verbesserungen ableiten:

1. Neuer read-only Abschnitt `Motorcontroller-Status`:
   - `motor_ready`, `is_homing`, Cutterstatus,
   - erkannte Versionen aus den temporaeren Creality-Versionsdateien,
   - Updatezustand `done/failed`,
   - aktive Key-781-bis-Key-797-Meldungen.
2. CFS- und Motorfehler gemeinsam nach Filamentweg gruppieren.
3. `mcu_update.log` unterscheiden zwischen erwarteten Discovery-Timeouts und echtem `fw_update fail`.
4. Warnen, wenn Config-Kommentar und tatsaechliche Version abweichen, aber keine Vendor-Config nur fuer einen Kommentar aendern.
5. Keine Buttons fuer rohe Motor-, Flash-, Kalibrier- oder Adressbefehle anbieten.
6. Bei einem spaeteren echten CFS-Problem eine passive Timeline aus Displayaktion, CFS-Status, Buffer, Werkzeugkopf-Sensor und E-Motorfehler erzeugen.

## 17. Grenzen der Rekonstruktion

Nicht vollstaendig offen dokumentiert sind weiterhin:

- die Bitbelegung aller Sensorstatus-Payloads,
- die exakten Action-Werte von `CTRL_MATERIAL_MOTOR_ACTION` und `CTRL_CONNECTION_MOTOR_ACTION`,
- Einheit und Grenzwerte von `SET_MOTOR_SPEED`,
- alle Trigger-/Stufen-Kombinationen fuer jeden mechanischen Sonderfall,
- die interne CFS-Regelung fuer Zugkraft und Spulenrueckwicklung,
- der vollstaendige Zusammenhang zwischen Boot-/Updater-Adresse, logischer Motornummer und Laufzeittransport der externen Controller.

Diese Luecken wurden bewusst nicht durch aktive Motorversuche geschlossen. Der naechste vertretbare Forschungsschritt waere ein rein passiver Mitschnitt waehrend eines vom Benutzer am Display gestarteten, normalen und beaufsichtigten Filamentwechsels. Daraus liessen sich Sensoruebergaenge und Payloads zeitlich zuordnen, ohne eigene Steuerpakete zu senden.

## 18. Aktuelle Bewertung des Druckers

Zum Abschluss der Untersuchung war der Drucker kalt und im Standby. Das CFS war verbunden, `motor_ready` war wahr, alle drei relevanten Motorcontroller meldeten App-Version 081, das CFS meldete 1.5.0 und es lagen keine aktiven schweren CFS- oder Motorfehler vor.

Die sichtbarste Unstimmigkeit ist der alte `071`-Kommentar in `motor_control.cfg`. Er beeinflusst den Betrieb nicht. Eine Live-Aenderung nur fuer diesen Kommentar wuerde einen Vendor-Dateidiff erzeugen und ist deshalb nicht empfehlenswert.

## 19. Evidenz und Reproduzierbarkeit

Lokale Arbeitskopien:

- `work/cfs-motor-study-20260801/live-config/`
- `work/cfs-motor-study-20260801/live-modules/`
- `work/cfs-motor-study-20260801/analysis/arm-module-introspection.json`
- `work/cfs-motor-study-20260801/sources/`

Wichtige Hashes:

```text
motor_control.cfg:
3EF28A9F5821670D8B33BB3CE8AA8A30D81764A30A4A7FDDDA689875B72D45E4

motor_control_wrapper.cpython-39.so:
4EEBAFD993A3FEA849EE280A9FE7E7061C2F0670C13599562AAE580502ECD3F1

box_wrapper.cpython-39.so:
B9E601E10C00C22D5FF76FE17A3E7B9F7CF31052C9FA736000E9717999D90507

Offline-Introspektionsreport:
B111D30A1AFE4ABB70FDD5BA10FB1302773287ABA2C64A68D2146C898538F13E
```

Quellstaende:

```text
CrealityOfficial/K2_Series_Klipper:
bc0a52078ace1e4d82995e396b38457b9f441024

j-devops/k2-unleashed:
d3be14c50b9156b84d08403e0ed82112f2b8f278

MasterLufier/Creality-K2-Plus-Custom-Macros:
8da3ef063b9a743e761428bcdca05ffecd97a7a0
```

## 20. Quellen

- [CrealityOfficial K2 Series Klipper](https://github.com/CrealityOfficial/K2_Series_Klipper)
- [MasterLufier Creality K2 Plus Custom Macros](https://github.com/MasterLufier/Creality-K2-Plus-Custom-Macros)
- [j-devops k2-unleashed](https://github.com/j-devops/k2-unleashed)
- [sw3defy Creality Helper Script](https://github.com/sw3defy/Creality-Helper-Script-K2-Plus)

Die proprietaeren Details wurden primaer aus den exakt installierten Live-Modulen des eigenen Druckers rekonstruiert. Die Community-Quellen wurden nur zur Gegenpruefung und Risikobewertung verwendet.
+
## 21. Umsetzung im Helper v5.2.21.87

Die sicheren Punkte dieser Studie wurden als strikt lesende Diagnose umgesetzt:

- CLI: `helper.sh --motor-controller-status`
- Menue: `Status & Gesundheit -> Motorcontroller-Status`
- Einbindung in Full Health, CFS Health, Firmware Health und Preflight
- Auswertung von Moonraker `motor_control`/`box`, `/tmp/.485_mcu_version`,
  `/tmp/.mcu_version`, `/tmp/mcu_update.log`, aktuellem Klipperlog und dem
  Firmwarekommentar in `motor_control.cfg`
- keine UUID-Ausgabe, kein G-Code-Endpunkt, kein serieller Zugriff und keine
  Motor-, CFS-, Flash-, Kalibrier-, Adress-, Reboot- oder Bewegungsfunktion

Der Live-Test am 2026-08-01 ergab:

```text
motor_ready=true
controllers=2
motor_app=081
extruder_app=081
cfs_version=1.5.0
cfs_app=150
updater_failures=0
motor_error_keys=none
warn=0
fail=0
```

Die Upstream-Staende von CrealityOfficial/K2_Series_Klipper, k2-unleashed und
MasterLufier/Creality-K2-Plus-Custom-Macros wurden erneut abgeglichen und waren
gegenueber den in Abschnitt 19 genannten Commits unveraendert. Es gab daher
keinen neueren Quellstand, der eine Aenderung der F012-Regelparameter oder einen
Firmwaretausch rechtfertigt.
