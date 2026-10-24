# Kontivo: Datenmodell

Stand 24.10.2026 · Web v322. Verbindliche Beschreibung aller gespeicherten Daten der Web-App, als Vorlage für die Swift-Modelle (`Codable`) und den Import von Web-Backups.
Prüfung: `python3 tests/check_model.py <Backup.json>` meldet Felder, die hier fehlen, und falsche Typen.

Schreibweise: **Typ** wie im JSON. `Datum` = Text `JJJJ-MM-TT` (lokales Datum, ohne Uhrzeit), `""` = nicht gesetzt. «Pflicht» = wird von der App immer geschrieben.

## 1 Speicherorte

| Ort | Inhalt |
|---|---|
| localStorage `vertraege.v1` | JSON `{settings, contracts, incomes, vars}` |
| localStorage `vertraege.v1.defekt` | Rohdaten, die beim Start nicht lesbar waren und beim «Neu beginnen» beiseitegelegt wurden |
| IndexedDB `kontivo-files`, Store `blobs` | Dateien (Logos, Dokumente, Personenbilder): Schlüssel = Datei-ID, Wert = Blob |
| Backup-Datei `kontivo-sicherung-JJJJ-MM-TT.json` | `{app:"vertraege", version:2, exported:ISO-Zeit, settings, contracts, incomes, vars, files:{ID:{type, data:Base64}}}` |

- `contracts`, `incomes`, `vars` sind Objekte `{ID: Eintrag}`. IDs: `Date.now().toString(36)` + 5 Zufallszeichen (uid). Erlaubt beim Import: `[A-Za-z0-9_-]{1,40}`, sonst neu vergeben.
- Datei-IDs: 32 Hex-Zeichen (crypto.getRandomValues). Erlaubt beim Import: `[A-Za-z0-9_.:-]{1,80}`.
- Nicht gespeichert (nur Laufzeit): gewählter Tab, Monat/Jahr, Filter (`state.flt`, `heroF`, `fltA`), Suche, Ansicht im Verträge-Tab (`lm`).
- Swift: ein `AppData: Codable` mit diesen vier Teilen; Dateien im App-Container, Metadaten im Modell.

## 2 Vertrag (`contracts[ID]`)

| Feld | Typ | Pflicht | Bedeutung, Werte |
|---|---|---|---|
| `partner` | Text | ja | Vertragspartner (Anbieter). Gruppierung über `pkey` (siehe 7) |
| `label` | Text | ja | Bezeichnung («Krankenkasse», «Internet»); Anzeige `label` ‖ `partner` ‖ «Ohne Namen» |
| `cat` | Text | ja | Kategoriename (siehe 5.2); Standard «Sonstiges» |
| `amount` | Zahl | ja | Anfangspreis je Zahlung in `cur`, auf Rappen/Cent gerundet. Aktueller Preis = letzte Preisänderung ≤ Stichtag (`curPrice`) |
| `cur` | Text | ja | `CHF`, `EUR`, `USD`, `GBP`, `TRY` |
| `cycle` | Zahl | ja | Zahlungsrhythmus in Monaten: 1, 2, 3, 6, 12, 24 |
| `due` | Datum | ja | Zahlungsanker: ein Zahlungstermin; alle Termine = `due` ± k·`cycle` Monate (Tag 29–31 → Monatsende in kurzen Monaten, kein Drift) |
| `start` | Datum | ja | Vertragsbeginn; `""` = unbekannt (dann rückwirkend voll gezählt). Vor `start` keine Zahlungen |
| `end` | Datum | ja | Vertragsende bei Mindestlaufzeit; `""` = unbefristet |
| `renew` | Zahl \| Text \| `""` | ja | Verlängerung in Monaten nach `end`; `""` = keine (endet von selbst). Das Formular speichert eine Zahl, der CSV-Import und alte Daten Ziffern als Text («12»); gerechnet wird immer mit `+renew` |
| `notice` | Zahl | ja | Kündigungsfrist; 0 = keine. 0–1200 |
| `noticeU` | Text | ja | Einheit der Frist: `m` Monate, `w` Wochen, `d` Tage, `k` «bis zum n. des Monats» (n = `notice`, max. 28) |
| `cancTerm` | Text | ja | Kündbar per (nur ohne `end`): `""` jederzeit, `p` Ende Zahlungsperiode, `m` Monatsende, `q` Quartalsende, `h` Halbjahresende, `y` Jahresende, `a` Ende Vertragsjahr |
| `mand` | Bool | ja | Pflichtvertrag: nur Anbieter wechseln, nicht ersatzlos kündigen |
| `noCancel` | `true` | nein | Nicht kündbar (Gebühren); fehlt sonst. Kategorie «Steuern & Gebühren» gilt immer als nicht kündbar (`isFixed`) |
| `noWatch` | Bool | ja | Frist nicht beobachten (nicht in «Fristen»). Bei Probeabo immer `false` |
| `trial` | Datum | ja | Probeabo: erster kostenpflichtiger Tag; davor keine Zahlungen. `""` = kein Probeabo |
| `trialKept` | Datum \| `true` | nein | Probeabo behalten: Wert = `trial` (oder `true` aus CSV/alten Daten); dann keine Probeabo-Frage mehr |
| `custNo`, `contrNo` | Text | ja | Kunden- bzw. Vertragsnummer (Beschriftung je Art: Rufnummer, Policen-, Versichertennummer) |
| `holders` | Text[] | ja | Personen (Namen aus `settings.holders`); leer = niemand zugeordnet |
| `split` | {Name: Prozent} | nein | Individuelle Aufteilung ab 2 Personen; Summe 100 (gültig ± 0.6), 4 Nachkommastellen; fehlt = gleich verteilt |
| `payM` | Text | ja | Zahlungsart: `""`, «Lastschrift (LSV/SEPA)», «eBill», «Kreditkarte», «QR-Rechnung», «Dauerauftrag», «TWINT», «PayPal», «Sonstiges» |
| `payA` | Text | ja | Belastet über (frei, z.B. «Visa …4417») |
| `cancF` | Text | ja | Kündigungsweg: `""` (noch wählen), «Online / Kundenkonto», «E-Mail», «Brief», «Telefon». Alt «Einschreiben» → «Brief» |
| `cancUrl` | Text | ja | Kündigungslink, nur bei «Online / Kundenkonto» |
| `web`, `tel`, `mail` | Text | ja | Kontakt des Vertragspartners |
| `addr` | Text | ja | Adresse des Vertragspartners, mehrzeilig (Firma, Strasse, PLZ Ort, Land). Gilt für alle Verträge desselben Vertragspartners (wird parallel geschrieben) |
| `note` | Text | ja | Notiz |
| `color` | Text | ja | Eigene Farbe `#RGB`/`#RRGGBB`, `""` = Kategoriefarbe |
| `logoId` | Text | ja | Datei-ID des Logos, `""` = keins |
| `logoBg` | Text | ja | Hintergrund des Logos (`#RRGGBB` oder `rgb(r,g,b)`), `""` |
| `prices` | {from: Datum, amount: Zahl}[] | ja | Preisänderungen ab Datum (auch künftige = «geplant»; 0 = gratis). Sortierung nach Datum |
| `extras` | {date: Datum, amount: Zahl, note: Text}[] | ja | Sonderzahlungen; Gutschrift = negativ. Zählen in Kosten/Budget im Monat des Datums, nie in `monthlyCost` |
| `docs` | {id, name, type}[] | ja | Dokumente: Datei-ID, Dateiname, MIME-Typ |
| `status` | Text | ja | `active`. `cancelled` nur aus altem CSV-Import (dann `cancelledAt` = Ende) |
| `cancelledAt` | Datum | ja | Altfeld zu `status: cancelled`, sonst `""` |
| `cancelPer` | Datum | nein | Gekündigt: läuft bis (letzter Vertragstag). Vorbei = Archiv |
| `cancelledOn` | Datum | nein | Gekündigt am |
| `keptFor` | Datum | nein | «Behalten» für dieses Vertragsende (= `termEnd` zum Zeitpunkt); verfällt von selbst, wenn sich das Ende ändert |
| `paused` | Bool | nein | Pausiert; keine Zahlungen von `pausedAt` bis vor `pausedUntil` |
| `pausedAt` | Datum | nein | Beginn der Pause |
| `pausedUntil` | Datum | nein | Ende der Pause (erster Tag wieder aktiv); `""` = offen. «Fortsetzen» setzt heute |
| `review` | {v: `keep`\|`kill`, at: Datum} | nein | Quartals-Check: behalten bzw. zum Kündigen vorgemerkt |
| `cred`, `mref` | Text | nein | Gläubiger-ID und Mandatsreferenz aus dem Kontoauszug (max. 40), für den nächsten Import |
| `t` | Zahl | ja | Erfasst am (ms seit 1970); Sortierung bei Gleichstand, Start des Quartals-Checks |

Vertragsart (nur im Formular, abgeleitet): Nicht kündbar (`noCancel` oder Steuern) · Mindestlaufzeit (`end`) · Probeabo (`trial` und nicht behalten) · Flexibel (sonst).

## 3 Einnahme (`incomes[ID]`)

| Feld | Typ | Pflicht | Bedeutung |
|---|---|---|---|
| `name` | Text | ja | Quelle (Arbeitgeber, Mieter …) |
| `label` | Text | ja | Bezeichnung; Anzeige `label` ‖ `name` ‖ «Einnahme» |
| `cat` | Text | ja | Art: Lohn, Nebeneinkommen, Bonus, Rente, Zulagen, Unterstützung, Kapitalerträge, Vermietung, Rückerstattung, Sonstiges (fest, nicht verwaltbar) |
| `amount`, `cur` | Zahl, Text | ja | wie Vertrag (netto) |
| `cycle` | Zahl | ja | 0 = einmalig (am `due`), sonst 1, 2, 3, 6, 12, 24 |
| `due`, `start`, `end` | Datum | ja | wie Vertrag; `end` vorbei = Archiv |
| `holders` | Text[] | ja | Empfänger (in der App genau eine Person) |
| `prices` | {from, amount}[] | ja | Änderungen des Betrags |
| `note`, `logoId`, `logoBg`, `color` | Text | ja | wie Vertrag |
| `status` | Text | ja | immer `active` |
| `t` | Zahl | ja | Erfasst am (ms) |

## 4 Variable Kosten (`vars[ID]`, Planwert pro Monat)

| Feld | Typ | Pflicht | Bedeutung |
|---|---|---|---|
| `label` | Text | ja | Bezeichnung (max. 60); leer = Name des Symbols |
| `ic` | Text | ja | Symbol: `benzin`, `essen`, `aus`, `frei`, `kleid`, `haus`, `ferien`, `gesch`, `tier`, `mobil`, `gesund`, `sonst` |
| `amount`, `cur` | Zahl, Text | ja | geschätzter Betrag pro Monat (0 – 10 Mio.) |
| `holders` | Text[] | ja | Personen (anteilig wie Verträge, gleich verteilt) |
| `start`, `end` | Datum | ja | gilt in Monaten, die den Zeitraum berühren; `""` = offen |
| `logoId`, `logoBg` | Text | ja | wie Vertrag |
| `t` | Zahl | ja | Erfasst am (ms) |

## 5 Einstellungen (`settings`)

### 5.1 Felder

| Feld | Typ | Bedeutung |
|---|---|---|
| `home` | Text | Hauptwährung (`CHF`, `EUR`, `USD`, `GBP`, `TRY`); bestimmt auch das Zahlenformat (EUR → 1.234,50, sonst 1’234.50) |
| `rates` | {Währung: Zahl} | Kurse in CHF pro Einheit (z.B. `EUR: 0.94`); fehlt ein Kurs, gelten Startwerte EUR 0.94, USD 0.80, GBP 1.07, TRY 0.02 |
| `rateDate` | Datum | Stand der Kurse (EZB-Datum) |
| `rateChecked` | Datum | Tag der letzten Prüfung |
| `rateCheckedAt` | Zahl | Zeitpunkt der letzten Prüfung (ms); neue Abfrage frühestens nach 3 h |
| `rateSrc` | Text | Quelle: `ezb` oder `er` (open.er-api.com) |
| `holders` | Text[] | Personen (Inhaber), Reihenfolge = Anzeige; mindestens eine, Standard `["Ich"]` |
| `lastHolders` | Text[] | Zuletzt gewählte Personen (Vorbelegung neuer Verträge) |
| `senders` | {Name: Absender} | Absender je Person: `{first, last, street, zip, city, country, same?}`; `same` = gleiche Adresse wie andere Person |
| `sigs` | {Name: Data-URL} | Unterschrift je Person (JPEG/PNG als `data:image/…;base64,…`) |
| `avatars` | {Name: Datei-ID} | Personenbild |
| `catList` | {n, c, i, k}[] | Ausgaben-Kategorien: Name, Farbe, Symbol (Standardname oder `tag`), Schlüssel k (ursprünglicher Standardname, bleibt beim Umbenennen). Fehlt = 12 Standardkategorien |
| `theme` | Text | Darstellung: `auto`, `light`, `dark` (gerätebezogen, wird beim Backup-Einspielen nicht übernommen) |
| `sort` | Text | Sortierung Verträge: `due`, `cost`, `partner`, `cat` (Standard), `holder` |
| `sortI`, `sortV` | Text | Sortierung Einnahmen (`due`, `cost`, `partner`, `cat`, `holder`) bzw. variable Kosten (`cost`, `name`, `cat`, `holder`) |
| `kArt` | Text | Kosten-Tab: `fix` (Standard), `all`, `var` |
| `bArt` | Text | Budget: `all` (Standard), `fix`, `none` |
| `onboarded` | Zahl | Version der gesehenen Einführung (aktuell 1) |
| `lastReview`, `reviewSnooze` | Datum | Quartals-Check: zuletzt durchgegangen bzw. zurückgestellt bis |
| `qIgn` | {Schlüssel: 1} | Ignorierte Hinweise der Vollständigkeit: `c:<ID>:<Feld>`, `i:<ID>:<Feld>`, `p:<pkey>:addr\|logo`, `h:<Name>:sender` |
| `logoSkip` | {pkey: 1} | Vollständigkeit: Vertragspartner ohne Logo bewusst gelassen |
| `ltWin` | Text | Kündigungsschreiben: Adressfenster `l` (links, Standard, DIN 5008 / SN 010130) oder `r` (rechts, nur Schweizer Brief) |
| `bankIgn` | Text[] | Kontoauszug: «Nicht mehr vorschlagen» (Gruppenschlüssel, siehe kontivo-swift-hinweise 1) |
| `bankAlias` | {Schlüssel: {n, c}} | Kontoauszug: gelernte Namen (n) und Kategorie (c) je Gruppenschlüssel |
| `bankLast` | {from, to, at, n, ok: 1} | Letzter Kontoauszug: Zeitraum, Datum, Anzahl Dateien |
| `dataVer` | Zahl | Datenversion, aktuell 2 |
| `rateTs` | Zahl | Altfeld früherer Versionen, ungenutzt (beim Import ignorieren) |
| `cats` | {n, c}[] | Altfeld: eigene Kategorien vor `catList`; wird beim ersten Speichern der Kategorien entfernt (siehe 6) |

### 5.2 Kategorien
- Ausgaben (Standard, Reihenfolge): Wohnen, Energie & Wasser, Versicherung, Gesundheit, Mobilfunk & Internet, Abos & Medien, Mobilität, Familie & Bildung, Freizeit & Sport, Steuern & Gebühren, Finanzen, Sonstiges. Fachregeln hängen am Schlüssel k (`catKey`), nicht am Namen.
- Farben: gespeicherte Altfarben werden nur beim Anzeigen ersetzt (OLD_COL, CAT_OLD), Daten bleiben.

## 6 Migrationen (beim Laden und Backup-Einspielen)

| Alt | Neu | Funktion |
|---|---|---|
| `settings.rate` | `settings.rates.EUR` | migModel |
| `holder` (Text) | `holders` [Text] | migModel |
| `settings.sender` (Freitext), `senderF`, `sig` | `senders[Person]`, `sigs[Person]` (an die Person mit passendem Vornamen, sonst die erste) | migModel, senderParse |
| Kategorienamen «Energie», «Streaming & Software», «Fitness & Freizeit», «Steuern», «Kinderbetreuung» | neue Namen, `catList[].k` | migCats (nur bei `dataVer` < 2) |
| `settings.cats` | `settings.catList` | catList / saveCatList |
| `cancF` «Einschreiben» | «Brief» | migVia, sanitizeImport |
| `bankLast` ohne `ok: 1` | verworfen | sanitizeImport |

Swift: Migrationen nur im Importer für Web-Backups, das native Modell kennt nur die neuen Felder.

## 7 Regeln und Normalisierung

- Import (`sanitizeImport`): Texte nur als Text (Zahlen → Text), `amount` auf 2 Stellen, ungültiger Rhythmus → 1, unbekannte Währung → Hauptwährung, `notice`/`renew` 0–1200, Listen müssen Listen sein, Personen nicht leer, Farben nur Hex/rgb, Unterschriften nur Bild-Data-URLs, Prototyp-Schlüssel entfernt.
- Sichern im Formular (Prüffälle: tests/golden_form.json): `end`/`renew` nur bei Mindestlaufzeit (Verlängerung ist dort mit 1 Monat vorbelegt, «nicht automatisch» muss bewusst gewählt werden); Probeabo setzt `due` auf das Probe-Ende; Jahresrhythmus bei Flexibel setzt `cancTerm` = `p`; `cancTerm` nur bei Flexibel/Probeabo; `notice` 0 bei Nicht kündbar; `noWatch` false bei Probeabo; `cancUrl` leer bei E-Mail/Brief; `split` nur, wenn ungleich verteilt; Felder ausserhalb des Formulars (Kündigung, Pause, Behalten, unbekannte) bleiben erhalten.
- Vertragspartner-Schlüssel `pkey(name)`: Kleinbuchstaben, Akzente entfernt, ß → ss, & → und, nur a–z/0–9, Wörter < 2 Zeichen und Füllwörter (LSTOP: AG, GmbH, SA …) weg. Gleicher Schlüssel = gleicher Vertragspartner (Duplikat-Hinweis, «Dubletten» in Verwalten).
- Duplikat-Hinweis (`dupOf`): gleicher Schlüssel und (gleiche Bezeichnung nach `lnorm` oder gleicher aktueller Betrag in gleicher Währung). Nur Hinweis, Sichern bleibt möglich.

## 8 Abgeleitete Werte (nicht gespeichert)

Rechenkern im Abschnitt «Rechnen» von index.html, öffentlich über `window.KontivoCalc()` für die Prüffälle:

| Wert | Funktion | Prüffall |
|---|---|---|
| Zahlungstermine, Zahlungen inkl. Sonderzahlungen | `occurrences`, `payments` | cases.json |
| Aktueller Preis, Kosten pro Monat (Hauptwährung) | `curPrice`, `monthlyCost` | cases.json |
| Vertragsende, nächster Kündigungstermin, Frist | `termEnd`, `nextTerm`, `noticeDeadline`, `effEnd`, `renewTo` | cases.json |
| Status | `isEnded`, `isPaused`, `notStarted`, `trialOn`, `needsAction`, `trialNeeds`, `isAnytime`, `isFixed` | cases.json |
| Anteil einer Person | `holderShare`, `splitOf` | cases.json, cases_budget.json |
| Fixkosten pro Monat (Kopfzeile) | `fixMonthSum` | cases_budget.json |
| Kosten je Monat, Vorjahresvergleich | `costMonths`, `paySum` | cases_budget.json |
| Budget je Monat/Jahr | `budgetYear`, `budgetMonth` | cases_budget.json |
| Fair geteilt | `fairShare` | cases_budget.json |
| Einnahmen/variable Kosten pro Monat | `incMonthNow`, `varMonth` | cases_budget.json |
| Duplikat-Hinweis, Dubletten | `dupOf`, `partnerIds`, `partnerGroups` | cases_budget.json |
| Fristen-Tab (Kopf, Zeilen, Gruppen, Knöpfe), Ansicht je Vertrag/Einnahme, Vollständigkeit | Ansichten (Texte) | golden_ui.json |
| Gespeicherter Vertrag/Einnahme aus dem Formular | saveForm, iSave | golden_form.json |

## 9 Vorschlag Swift-Typen

- `struct Contract: Codable, Identifiable` mit `enum Currency`, `enum NoticeUnit {m, w, d, k}`, `enum CancelTerm {anytime, period, month, quarter, halfYear, year, contractYear}`, `enum CancelChannel`, `enum PaymentMethod`, `Renewal?` statt `"" | Zahl`, `TrialDecision` statt `Datum | true`, `[PriceChange]`, `[ExtraPayment]`, `[Document]`, `[String: Double]?` für `split`, `Pause?` (from, until), `Cancellation?` (per, on), `Review?`.
- Datumsfelder als `DateComponents`/eigener `Day`-Typ (ohne Zeitzone), nicht `Date` mit Uhrzeit.
- `Income` mit `enum IncomeCycle {once, months(Int)}`; `VariableCost` mit `enum VarIcon`.
- `Settings` getrennt in Daten (holders, senders, catList, rates …) und Gerät (theme, Sortierung, Ansichtswahl); Personen als Entität mit ID statt Name als Schlüssel.
