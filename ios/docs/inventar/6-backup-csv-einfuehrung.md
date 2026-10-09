# R6 – Inventar für den SwiftUI-Nachbau: Logo-Suche, Sicherung, Rückfrage, Alles löschen, CSV, Migration, Einführung, Start, Service Worker

Grundlage: index.html 5030–5593 (+ Helfer 1520–1610, 1615–1671, 1904–1918, 4915–5029), sw.js, manifest.webmanifest, Commit d620f19.
Texte stehen wörtlich in «», `\n` steht für einen Zeilenumbruch, `{x}` für eingesetzte Werte.

---

## 1. Speicher-Grundlagen (Bezug für Backup und Migration)

- **localStorage-Schlüssel** `vertraege.v1` (`LS`) = JSON `{settings, contracts, incomes}` (`saveLocal`/`loadLocal`). Weitere Schlüssel gibt es nicht. Speicherfehler werden still verschluckt.
- **Standardwerte** (`state`, 1709): `settings = {home:"CHF", rates:{}, holders:["Ich"]}`, `contracts = {}`, `incomes = {}`.
- **loadLocal:** Settings werden per `Object.assign` in die Standardwerte gemischt, `contracts` und `incomes` ersetzt. Andere Top-Level-Schlüssel (z.B. das alte `budget`) werden ignoriert. Danach läuft `migCats()`.
- **Blobs:** IndexedDB `kontivo-files`, Store `blobs`, Schlüssel = Blob-ID, Wert = Blob (`KBlob`). Beim Start werden alle Blobs in den Speicher geladen und bekommen je eine Object-URL (`KBlob.ready`).
  - **Blob-ID** (`newId`) = 16 Zufallsbytes als 32 Hex-Zeichen (klein).
  - `KBlob.has/url/get/put/del/ids/exportAll/importAll`.
  - `window.claude.use("assets")` liefert `{upload(file)→{id}, list()→{assets:[{id}]}, delete(id)}`, `use("downloads")` liefert `{save({filename,data})}` (iOS-Teilen-Menü, sonst `<a download>`). Andere Namen werden abgelehnt.
- **Vertrags-/Einnahmen-ID** (`uid`) = `Date.now().toString(36)` + 5 Zeichen Base36-Zufall. Beim CSV-Import: `uid()+Index`.
- **Blob-Referenzen im Modell:** `contract.logoId`, `income.logoId`, `contract.docs[].id` (`{id,name,type}`), `settings.avatars[Inhaber]`. Unterschriften liegen **nicht** als Blob vor, sondern als JPEG-Data-URL in `settings.sigs[Inhaber]`.

---

## 2. Sicherung (Backup)

### 2.1 Export (Klick auf `#bkSave` «Backup erstellen»)
1. Benutzte Blob-IDs sammeln: `logoId` und `docs[].id` aller Verträge **und** Einnahmen sowie alle Werte von `settings.avatars`.
2. `KBlob.exportAll(ids)`: nur IDs, die auf dem Gerät vorhanden sind, nacheinander als Base64 über `FileReader.readAsDataURL`, Präfix `data:…;base64,` abgeschnitten. Schlägt etwas fehl, wird `files = {}` gesetzt (siehe Befund M5).
3. JSON (ohne Einrückung, `JSON.stringify`):
```json
{
  "app": "vertraege",
  "version": 2,
  "exported": "2026-10-03T08:15:42.123Z",
  "settings": { …komplettes state.settings… },
  "contracts": { "<id>": { …Vertrag… } },
  "incomes":   { "<id>": { …Einnahme… } },
  "files": { "<blobId32hex>": { "type": "image/png", "data": "<Base64 ohne Präfix>" } }
}
```
   - `exported` = `new Date().toISOString()` (UTC, mit Millisekunden).
   - `type` = `blob.type` oder `""`.
4. Dateiname `kontivo-sicherung-YYYY-MM-DD.json` (lokales Datum `iso(today())`). MIME `application/json`.
5. Speichern über `downloads.save`. Erfolg: Toast «Backup gespeichert». Abbruch im Teilen-Menü (`code:"declined"`): keine Meldung. Anderer Fehler oder kein Download möglich: Textfeld in `#csvOut` mit dem JSON und der Notiz «Download nicht möglich. Text kopieren und als .json-Datei sichern.»
6. Läuft zu viel Zeit seit dem Tippen ab (Teilen verweigert), fragt die Rückfrage nach: Titel «Datei bereit», Text «{Dateiname}\n\nIm nächsten Schritt «In Dateien sichern» wählen.», Knopf «Teilen».

**Settings-Schlüssel im Backup** (alles, was im Gerät steht): `home`, `rates{EUR,USD,GBP,TRY}` (CHF pro Einheit), `rateDate`, `rateChecked`, `rateSrc`, `rateAuto`, `holders[]`, `lastHolders[]`, `catList[{n,c,i}]`, gegebenenfalls das alte `cats[{n,c}]`, `theme` ("auto"|…), `sort` ("cat"|…), `senders{Inhaber:{first,last,street,zip,city,country,same?}}`, `sigs{Inhaber:DataURL}`, `avatars{Inhaber:BlobID}`, `onboarded` (Zahl), `lastReview`, `reviewSnooze` (ISO-Datum), `qIgn{}`. Alte Backups können zusätzlich `rate`, `sender`, `senderF` und `sig` enthalten (siehe Migration).

**Vertragsfelder** (laut Doku und Code): partner, label, cat, amount, cur, cycle, due, start, end, notice, noticeU (m|w|d|k), renew, cancTerm (""|p|m|q|h|y|a), mand, noWatch, custNo, contrNo, holders[], payM, payA, cancF, cancUrl, trial, trialKept, web, addr, tel, mail, note, color, logoId, logoBg, prices[{from,amount}], docs[{id,name,type}], extras[{date,amount,note}], status (active|cancelled), cancelledAt, cancelPer, cancelledOn, keptFor, paused, pausedAt, pausedUntil, t.
**Einnahmefelder:** name, label, cat, amount, cur, cycle (inkl. 0 = einmalig), due, start, end, holders[], prices[], note, logoId, logoBg, color, status, t.

### 2.2 Import (`#bkLoad` «Backup laden» öffnet `#bkFile`, accept `.json,application/json`)
1. `FileReader.readAsText`, dann `JSON.parse`. Fehler: Toast «Keine gültige Backup-Datei».
2. Gültig ist eine Datei nur mit `o.app === "vertraege"` **und** `typeof o.contracts === "object"`. Das Feld `version` wird **nicht** ausgewertet.
3. Rückfrage: Titel «Backup einspielen?», Text «Backup vom {dd.m.yyyy} mit {nc} Verträgen und {ni} Einnahmen[ sowie {nf} Logos/Dokumenten].\n\nDie aktuellen Daten werden ersetzt.», Knopf «Einspielen», rot. Das Datum kommt aus `new Date(o.exported).toLocaleDateString("de-CH")`, ohne Angabe steht «unbekannt».
4. Sind Dateien vorhanden: Toast «Dateien werden übernommen…», dann `KBlob.importAll(o.files)`. Jede Datei wird nacheinander mit **derselben ID** gespeichert, Base64 → Blob mit `type`. Bei Fehler: Toast «Einige Dateien konnten nicht übernommen werden».
5. `restoreAll(o)`: `contracts = o.contracts||{}`, `incomes = o.incomes||{}`, `settings = Object.assign(aktuelleSettings, o.settings||{})` (wird **gemischt**, siehe Befund M3), danach `migCats()`, `saveLocal()`, `fillSettings()`, `render()` und Toast «Backup eingespielt».
6. Vorhandene Blobs des Geräts werden **nicht** gelöscht. Filter (`state.flt`) und `state.bHolder` werden nicht zurückgesetzt.

---

## 3. Rückfrage (`ask`, global `window.kontivoAsk`)
- `ask({title, text, ok="OK", danger=false, alert=false}) → Promise<Bool>`. Der Text wird mit `white-space:pre-line` dargestellt.
- Bottom-Sheet `#sheetAsk` mit Scrim: Titel `#askT`, Text `#askP`, Knopf `#askOk` (Beschriftung `ok`, mit `danger` rote Klasse `dangerbtn`), `#askNo` «Abbrechen» (versteckt bei `alert`).
- Es ist immer nur eine Rückfrage offen. Eine neue überschreibt die alte, deren Promise dann nie aufgelöst wird.
- SwiftUI: `.confirmationDialog` bzw. `.alert` mit `role: .destructive`.

---

## 4. Alles löschen (`#wipeAll` «Alle Daten löschen»)
1. Rückfrage 1: Titel «Alle Daten löschen?», Text «Gelöscht werden {nc} Verträge, {ni} Einnahmen, eigene Kategorien, Inhaber, Absender sowie hochgeladene Logos und Dokumente.\n\nDarstellung und Währung bleiben erhalten.\n\nTipp: Speichere vorher ein Backup.», Knopf «Weiter» (rot).
2. Rückfrage 2: Titel «Wirklich endgültig löschen?», Text «Das lässt sich nicht rückgängig machen.», Knopf «Endgültig löschen» (rot).
3. Toast «Lösche …». Alle Blobs werden gelöscht (`assets.list` und dann `delete` für jeden).
4. `contracts = {}`, `incomes = {}`. Settings werden neu gesetzt auf `{holders:["Ich"], home, rates, rateDate, theme, sort}`, alle anderen Schlüssel fallen weg (auch `onboarded`, siehe Befund L4). Dazu `bHolder=""`, `flt={cat:null,partner:null,holder:null}`.
5. Danach `saveLocal`, `fillSettings`, `goTab("list")`, `render` und Toast «Alle Daten gelöscht».

---

## 5. CSV-Export (`#csvBtn` «CSV exportieren»)
- **Nur Verträge** (alle, auch gekündigte), keine Einnahmen. Reihenfolge = `Object.keys(state.contracts)`.
- Trennzeichen `;`, Zeilenende `\n`, UTF-8 **ohne BOM**, **ohne Anführungszeichen**. In jedem Wert werden `;`, `\n` und `\r` durch ein Leerzeichen ersetzt.
- Dateiname `kontivo-export-YYYY-MM-DD.csv`, MIME `text/csv`. Toast «CSV gespeichert». Ohne Download: Textfeld in `#csvOut` und Toast «Download nicht möglich — Text kopieren».

| # | Spaltenname (exakt) | Inhalt / Format |
|---|---|---|
| 1 | `Vertragspartner` | `partner` |
| 2 | `Bezeichnung` | `label` |
| 3 | `Kategorie` | `cat` |
| 4 | `Betrag` | `curPrice(c)` = **heutiger** Preis (inkl. Preisänderungen), `toFixed(2)`, Dezimalpunkt |
| 5 | `Waehrung` | `cur` |
| 6 | `Turnus_Monate` | `cycle` (Wert wie gespeichert) |
| 7 | `ProMonat_{home}` (z.B. `ProMonat_CHF`) | `monthlyCost(c)` in Hauptwährung, `toFixed(2)` |
| 8 | `NaechsteZahlung` | `nextDue(c)` als ISO-Datum oder "" |
| 9 | `Beginn` | `start` |
| 10 | `Ende` | `effEnd(c)` = Ende, mit `renew` auf ≥ heute vorgerollt, ISO oder "" |
| 11 | `Kuendigungsfrist` | `notice` oder "" (0 wird zu "") |
| 12 | `Einheit` | `noticeU` (m/w/d/k) oder "" |
| 13 | `Verlaengerung` | `renew` oder "" |
| 14 | `KuendigenBis` | `urgency(c).date` (= noticeDeadline), ISO oder "" |
| 15 | `Preisverlauf` | `Anfang:{amount 2dp}` + für jede Preisänderung ` \| {from}:{amount 2dp}` |
| 16 | `Kundennummer` | `custNo` |
| 17 | `Vertragsnummer` | `contrNo` |
| 18 | `Inhaber` | `holders.join(", ")` |
| 19 | `Zahlungsart` | `payM` |
| 20 | `BelastetUeber` | `payA` |
| 21 | `KuendigungPer` | `cancF` (= **Kündigungsweg**-Text, z.B. «Einschreiben», kein Datum) |
| 22 | `Website` | `web` |
| 23 | `Telefon` | `tel` |
| 24 | `EMail` | `mail` |
| 25 | `Status` | `status` oder `active` |
| 26 | `KuendbarPer` | `cancTerm` (""/p/m/q/h/y/a) |
| 27 | `Pflichtvertrag` | `ja` oder "" |
| 28 | `Notiz` | `note` (Umbrüche werden zu Leerzeichen) |
| 29 | `Sonderzahlungen` | für jeden Eintrag `{date}:{amount 2dp}[:{note}]`, verbunden mit ` \| `. In der Notiz werden `\|` und `:` durch Leerzeichen ersetzt |

Nicht im Export enthalten: addr, cancUrl, noWatch, trial, trialKept, cancelledAt, cancelPer, cancelledOn, keptFor, paused*, color, logo, docs, t.

---

## 6. CSV-Import (`#csvImp` «CSV importieren» öffnet `#csvFile`, accept `.csv,text/csv,text/plain,text/comma-separated-values`)

### 6.1 Parser (`csvParse`)
1. BOM U+FEFF am Anfang wird entfernt. Gelesen wird mit `readAsText`, also immer als UTF-8.
2. **Trennzeichen:** aus `;`, `,` und Tabulator dasjenige mit den meisten Treffern in der **ersten Zeile** (einfaches Split, ohne Rücksicht auf Anführungszeichen). Bei Gleichstand gewinnt die Reihenfolge `;`, `,`, Tab.
3. Zeichenweise Zustandsmaschine: `"` schaltet den Zitat-Modus ein, und zwar an **jeder** Stelle (Befund H1). Im Zitat steht `""` für ein `"`, ein einzelnes `"` beendet das Zitat. Trennzeichen beendet das Feld. `\n`, `\r` oder `\r\n` beendet die Zeile. Zeilen, deren Felder alle leer sind, werden verworfen.
4. Die erste Zeile ist die Kopfzeile, Werte werden mit `trim()` gelesen.

### 6.2 Spaltenerkennung (`CSVMAP`, `csvNorm`)
- **Normalisierung** `csvNorm`: Kleinschreibung, ä→ae, ö→oe, ü→ue, ß→ss, danach alles ausser `a-z0-9` entfernen. Beispiel: «Kündigungs-Frist» → `kuendigungsfrist`.
- **Zuordnung:** Die Zielfelder werden in der Reihenfolge unten durchlaufen, je Feld die Aliase in der angegebenen Reihenfolge. Treffer bei **exakter** Gleichheit mit einer normalisierten Spalte, die noch nicht vergeben ist. Bei doppelten Spaltennamen zählt nur die erste Spalte.

| Zielfeld | Aliase (normalisiert, in Reihenfolge) |
|---|---|
| partner | partner, anbieter, vertragspartner, firma, unternehmen, provider, company, merchant, name, vertragsname |
| label | bezeichnung, vertrag, titel, label, beschreibung, abo, service, produkt, abonnement, name |
| cat | kategorie, category, art |
| amount | betrag, preis, kosten, amount, price, cost, costs, beitrag, monatsbetrag, zahlung, payment |
| cur | waehrung, wahrung, currency |
| cycle | turnusmonate, turnus, abrechnungsperiode, abrechnungszeitraum, zahlungsperiode, intervall, zyklus, rhythmus, zahlungsintervall, zahlungsrhythmus, billingperiod, frequency, billingcycle, interval, period |
| due | naechstezahlung, naechsteabbuchung, naechstefaelligkeit, faellig, faelligam, faelligkeit, nextpayment, nextbilling, nextdue, zahltag, abbuchungsdatum |
| start | beginn, vertragsbeginn, startdatum, start, startdate, abschlussdatum, seit |
| end | ende, vertragsende, enddatum, laufzeitende, laufzeitbis, enddate |
| notice | kuendigungsfrist, frist, notice, noticeperiod, cancellationperiod |
| noticeU | einheit |
| renew | verlaengerung, verlaengerungmonate |
| cancTerm | kuendbarper |
| mand | pflichtvertrag, pflicht |
| custNo | kundennummer, kundennr, customernumber |
| contrNo | vertragsnummer, vertragsnr, contractnumber, policennummer |
| holders | inhaber, vertragsinhaber, person, owner, holder |
| payM | zahlungsart, zahlungsmethode, zahlungsmittel, paymentmethod |
| payA | belastetueber, konto, karte |
| cancF | kuendigungper |
| web | website, web, url |
| tel | telefon, phone |
| mail | email, mail |
| note | notiz, notizen, notes, note, bemerkung, kommentar |
| addr | kuendigungsadresse, adresse, address, anschrift |
| prices | preisverlauf, kostenhistorien, kostenhistorie, preishistorie |
| tags | tags, schlagworte |
| contact | kontaktdaten, kontakt, ansprechpartner |
| dueDay | abbuchungstag, zahltagimmonat |
| status | status |
| extras | sonderzahlungen, einmalzahlungen |

Nicht zugeordnet (aus dem eigenen Export): `ProMonat_*`, `KuendigenBis`.
**Mindestanforderung:** eine Spalte für `amount` **und** eine für `partner` oder `label`. Sonst Hinweis: Titel «Keine passenden Spalten», Text «Nötig sind mindestens eine Spalte für den Namen (z.B. «Name» oder «Vertragspartner») und eine für den Betrag (z.B. «Kosten»). Am einfachsten: einmal «CSV exportieren» und die Datei als Vorlage nutzen.» (nur OK). Bei weniger als 2 Zeilen erscheint derselbe Hinweis.

### 6.3 Wert-Umwandlung
- **Zahl `csvNum`:** zuerst alles ausser `\d , . - '` entfernen, dann `'` entfernen. Kommen `,` und `.` beide vor, ist das hinterste das Dezimalzeichen, das andere wird entfernt. Sonst wird das **erste** `,` zu `.`. Ergebnis über `parseFloat`, endlich oder `null`. Beispiele: `1'234.50`→1234.5, `1.234,50`→1234.5, `12,90`→12.9, `CHF 12.-`→12, `-12,90`→−12.9, `1.000`→**1** (Befund L1).
- **Datum `csvDate`** → ISO `YYYY-MM-DD` oder "":
  - `^(\d{4})-(\d{1,2})-(\d{1,2})` (Rest wird ignoriert, z.B. eine Uhrzeit)
  - `^(\d{1,2})[./](\d{1,2})[./](\d{2,4})` = **Tag.Monat.Jahr**, zweistellige Jahre +2000
  - Überlauf durch `new Date(y,m-1,d)` ohne Prüfung (31.02 → 03.03). Andere Formate ergeben "".
- **Turnus `csvCycle`** → 1|2|3|6|12|24|"w" (Befund M2):
  - leer → 1. Reine Zahl → nur 1/2/3/6/12/24 zulässig, sonst 1.
  - Danach Teiltextsuche im normalisierten Wert, in dieser Reihenfolge: `woech|week`→"w"; `2jahr|zweijaehr|biennial`→24; `halbjaehr|halfyear|semiannual|6monat`→6; `quartal|quarter|viertel|3monat`→3; `2monat|zweimonat|bimonth`→2; `jaehr|jahr|year|annual`→12; sonst 1.
  - "w" (wöchentlich): Betrag × 52/12 auf 2 Stellen gerundet, Turnus 1.
- **Kündbar per `csvTerm`** → ""|p|m|q|h|y|a: Ist der Wert genau `p/m/q/h/y/a`, wird er übernommen. Sonst in dieser Reihenfolge: `periode`→p, `monatsende|monat`→m, `quartal`→q, `halbjahr`→h, `vertragsjahr`→a, `jahresende|jahr`→y, sonst "".
- **Kategorie** (Reihenfolge):
  1. vorhandene Kategorie mit gleichem Namen (Gross-/Kleinschreibung egal)
  2. Stichwortregel `csvCat` (unten)
  3. Kategorie aus dem Katalog (`tpl[2]`)
  - Liegt das Ergebnis nicht in `allCats()`, wird es als Rohname behandelt. Ein unbekannter Rohname wird als **neue Kategorie** angelegt: `{n:Rohname, c:COLORS[(Anzahl+3)%8], i:"tag"}` in `settings.catList`, `settings.cats` wird gelöscht (Befund L3: geschieht vor der Bestätigung). Ohne Kategorie: «Sonstiges».
  - `csvCat`-Regeln (erste Regel, die passt; Text normalisiert):
    Gesundheit `/gesund|arzt|zahn|apothek|optik|brille|health/` · Versicherung `/versich|police|haftpflicht|krankenkass|insurance/` · Abos & Medien `/stream|entertain|musik|music|video|software|app|cloud|zeitschrift|zeitung|abo|medien/` · Mobilfunk & Internet `/handy|mobilfunk|internet|telefon|dsl|glasfaser|phone|tv/` · Energie & Wasser `/strom|gas|energie|heiz|wasser|energy/` · Wohnen `/miete|wohn|haus|immobil|nebenkost|rent/` · Freizeit & Sport `/fitness|sport|verein|freizeit|gym/` · Familie & Bildung `/kind|kita|hort|schule|bildung|familie|betreuung|kurs|studium/` · Steuern & Gebühren `/steuer|gebühr|gebuehr|abgabe|serafe|billag|tax/` · Mobilität `/auto|kfz|bahn|mobilit|leasing|oev|transport|car|parkplatz/` · Finanzen `/bank|konto|kredit|finanz|spar|depot|vorsorge|säule|finance/` · sonst `^(andere|sonstig|other|misc)` → Sonstiges, sonst "".
- **Währung:** Gross geschriebener Text aus Währungsspalte + `" "` + Betragsspalte: `EUR|€`→EUR, `USD|US$|$`→USD, `GBP|£`→GBP, `TRY|₺|\bTL\b`→TRY, `CHF|FR`→CHF, sonst Hauptwährung.
- **Kündigungsfrist:** Zahl = `csvNum(notice)`. Die Einheit kommt aus der Spalte `Einheit`, sonst aus dem Fristtext ohne Ziffern, Leerzeichen und `.,`, jeweils normalisiert. Regeln: `^k|tagimmonat`→k; `^w|woche|week`→w; `jahr|year`→Frist ×12 mit Einheit m; `^d|^t|tag|day`→d; sonst m. Fehlt die Zahl: Katalogwert (`tpl[5]`/`tpl[6]`) nur, wenn die Fristspalte leer ist, sonst 0/"m".
- **Verlängerung:** `String(csvNum(renew)||"")`.
- **Preisverlauf:**
  - a) Format der App «Contract»: `dd.mm.yyyy bis dd.mm.yyyy Betrag` (auch mehrfach, durch Kommas getrennt). Jede Periode wird zu einer Preisänderung `{from, amount}`. Fehlt eine direkt folgende Periode, kommt am Tag nach `to` eine Rückkehr auf den Betrag aus der Spalte dazu. Liegt die erste Periode am oder vor `start`, wird sie zum Grundbetrag. Doppelte `from` werden entfernt.
  - b) Eigenes Format `Anfang:Betrag | Datum:Betrag | …`: «anfang» (Gross-/Kleinschreibung egal) ergibt den Grundbetrag, sonst wird mit `csvDate(Datum)` eine Preisänderung erzeugt.
- **Inhaber `csvHolders`:** Trennung an `,`, `&`, `/`, `+` und am Wort «und». Hat der letzte Teil mehrere Wörter, bekommt jeder einwortige Teil dessen Nachnamen (Befund L6). Danach Abgleich mit vorhandenen Inhabern über den vollen Namen oder den Vornamen (Gross-/Kleinschreibung egal). Ohne Spalte: erster Inhaber aus den Settings oder «Ich». Unbekannte Namen gelten als neue Inhaber.
- **Pflicht:** Spalte gefüllt → `/^(ja|yes|1|true|x)$/`. Sonst «pflicht» in den Tags oder Katalog `tpl[9]`.
- **Tags:** Trennung am Komma, Einträge mit «pflicht» entfallen, der Rest wird zur Notizzeile «Tags: …».
- **Notiz** = folgende Zeilen mit `\n` verbunden, leere entfallen: Notiz, «Kündigungsadresse: {addr}», «Kontakt: {contact}», «Tags: {rest}», «Kein Betrag im Import» (wenn Betrag 0 und die Betragsspalte leer ist).
- **Sonderzahlungen:** Trennung an `|`, jedes Stück gegen `^(\d{4}-\d{2}-\d{2}):(-?[\d.]+):?(.*)$` → `{date, amount, note}`.
- **Status:** `/cancel|gekuend|archiv/` → `cancelled` mit `cancelledAt` = heute, sonst `active`.
- **Katalog** (`tplFind(partner)||tplFind(label)`, exakter Name ohne Rücksicht auf Gross-/Kleinschreibung). TPL-Indizes: 0 Name, 1 Land, 2 Kategorie, 3 Bezeichnung, 4 Web, 5 Frist, 6 Einheit, 7 Kündbar per, 8 Kündigungsweg, 9 Pflicht, 10 Hinweis. Verwendet für: Kategorie, Frist/Einheit (nur wenn die Fristspalte leer ist), cancTerm (wenn leer und kein Ende), cancF (wenn leer), web (wenn leer), mand.

### 6.4 Aufbau des Vertrags (`csvToContracts`)
```
{partner, label, cat, amount: round2(Grundbetrag), cur, cycle,
 due: csvDate(due), start: csvDate(start), end: csvDate(end),
 notice, noticeU, renew, cancTerm, mand, custNo, contrNo, holders,
 payM, payA, cancF, trial:"", web, tel, mail, note,
 color:"", logoId:"", logoBg:"", prices, docs:[], extras,
 status, cancelledAt, t: Date.now()}
```
- Zeile ohne partner **und** ohne label: wird übersprungen (Zähler «ohne Namen»). Ein fehlender Betrag zählt als 0.
- Mit `end` gilt `cancTerm = ""`.
- **due fehlt:** Basis = `start` oder heute. Mit `dueDay` 1–31 wird der Tag gesetzt (begrenzt auf das Monatsende). Danach wird in Schritten von `cycle` Monaten ab der Basis vorgerollt, bis das Datum ≥ heute ist (höchstens 600 Schritte).
- **Abgelaufen:** Ist `end` < heute und der Status nicht `cancelled`, wird `status = cancelled` und `cancelledAt = end` gesetzt (Zähler «archiviert»).
- **Duplikate:** Schlüssel `[csvNorm(partner), csvNorm(label), amount.toFixed(2), cycle, start].join("|")`, geprüft gegen vorhandene Verträge **und** innerhalb der Datei. Treffer werden übersprungen (Zähler «bereits vorhanden»).

### 6.5 Dialoge und Übernahme
- Fehler beim Lesen: Toast «Die Datei konnte nicht gelesen werden».
- Kein Vertrag übrig: Titel «Nichts zu importieren», Text «Übersprungen: {n} bereits vorhanden, {m} ohne Namen.» oder «Die Datei enthält keine Verträge.» (nur OK).
- Bestätigung: Titel «{n} Vertrag gefunden» bzw. «{n} Verträge gefunden», Knopf «Importieren». Text aus folgenden Zeilen, jeweils nur wenn zutreffend: «{a} davon sind bereits beendet und kommen ins Archiv.\n», «Übersprungen: ….\n», «Neue Inhaber: A, B.\n», dann «\nBestehende Verträge bleiben unverändert.».
- Bei OK: neue Inhaber an `settings.holders` anhängen, gegebenenfalls `saveSettings`, Verträge mit `uid()+k` einfügen, `saveLocal`, `goTab("list")`, `render`. Toast «{n} Vertrag importiert — bitte kurz prüfen» bzw. «{n} Verträge importiert — bitte kurz prüfen».

---

## 7. Migration (beim Laden über `loadLocal` und beim Backup-Einspielen über `restoreAll`; `migCats` ruft `migModel` auf; gespeichert wird nur bei Änderung)

### `migModel()` (1617–1627), Reihenfolge
1. **Kurs:** `settings.rate` vorhanden → `rates.EUR = +rate`, aber nur wenn `rates.EUR` nicht > 0 ist und `rate > 0`. Danach `rate` löschen.
2. **Inhaber:** Für jeden Vertrag **und** jede Einnahme mit dem Feld `holder`: Sind `holders` leer und `holder` gefüllt, wird `holders = [holder]` gesetzt. Danach `holder` löschen.
3. **Absender Freitext:** `settings.sender` vorhanden → falls kein `senderF` existiert, `senderF = senderParse(sender)`. Danach `sender` löschen.
   - `senderParse`: Zeilen trimmen, leere entfernen. PLZ-Zeile = erste Zeile, die auf `^(?:[A-Z]{1,2}-?)?\d{4,5}\s+\S` passt.
   - Zeile 0 (falls sie nicht die PLZ-Zeile ist): letztes Wort = `last` (nur bei mehr als einem Wort), Rest = `first`.
   - PLZ-Zeile: `zip` = 4–5 Ziffern, `city` = Rest. `street` = Zeilen 1 bis vor der PLZ-Zeile, mit «, » verbunden. `country` = Zeilen nach der PLZ-Zeile, mit «, » verbunden.
   - Ohne PLZ-Zeile: `street` = Zeilen ab 1, mit «, » verbunden.
4. **Absender/Unterschrift pro Inhaber:** Wenn `senderF` oder `sig` vorhanden ist, wird das Ziel `h0` bestimmt: der Inhaber, dessen Name (Gross-/Kleinschreibung egal) gleich `senderF.first` ist, sonst der erste Inhaber (ohne Inhaber: «Ich»). Dann `senders[h0] = senderF` und `sigs[h0] = sig`, jeweils **nur wenn dort noch nichts steht**. Danach `senderF` und `sig` löschen.

### `migCats()` (1665–1671)
5. **Vertragskategorien:** `c.cat` in `CAT_MIG` wird umbenannt (nur Verträge, nicht Einnahmen).
6. **`settings.catList`:** Einträge mit `n` in CAT_MIG werden umbenannt (ein `i` in CAT_MIG ebenfalls). Einträge, bei denen nur `i` in CAT_MIG liegt, bekommen das neue Symbol. Danach Duplikate nach `n` entfernen, der erste Eintrag bleibt.
7. **Altes `settings.cats`:** Einträge mit Altnamen entfernen.
8. Bei Änderung `saveLocal()`.

`CAT_MIG` = {«Energie»→«Energie & Wasser», «Streaming & Software»→«Abos & Medien», «Fitness & Freizeit»→«Freizeit & Sport», «Steuern»→«Steuern & Gebühren», «Kinderbetreuung»→«Familie & Bildung»}.
Die Migration ist **nicht versioniert** und läuft bei jedem Start (Befund M1). Für SwiftUI: einmalige, versionierte Migration beim Import alter Backups (Version aus der Datei).

**Rückfall `catList()`** (wird nicht gespeichert): Ohne `catList` gelten die 12 Standardkategorien (`CATS` mit `CAT_COLOR`, Symbol = Name), ergänzt um Einträge aus dem alten `settings.cats`, die keine Standardnamen sind (Symbol «tag»).

---

## 8. Einführung (Onboarding)

### 8.1 Daten und Ablauf
- `OB_VER = 1`. Gesehen bedeutet `settings.onboarded = 1` (`closeOnb`).
- **Erststart** (`openOnb(true)`, 8 Seiten): welcome, tab:list, tab:stat, tab:budget, tab:term, tips, setup, start.
- **Tour aus «Mehr»** (`#onbOpen` «Einführung ansehen» mit Untertitel «Die wichtigsten Funktionen in einer Minute», `openOnb(false)`, 6 Seiten): ohne setup und start.
- Vollbild-Overlay `#onb` (`role=dialog`, `aria-modal`), solange es offen ist `body.overflow=hidden`. Fortschrittspunkte `#obProg` (ein Punkt pro Seite, `on` für alle Seiten bis zur aktuellen). Rückwärts navigieren setzt die Animationsklasse `back`.
- **Kopfzeile** (`obTop`) auf den Seiten tab/tips/setup/start: links ein Chip, rechts «Überspringen», solange die aktuelle Seite vor der Tips-Seite liegt.
- **Wischen:** horizontal ≥ 50 px und |dx| > |dy|. Gesten, die auf einem Eingabefeld beginnen, zählen nicht. Auf der Seite start ist Wischen nach links gesperrt. Wischen nach rechts geht zurück, nach links vorwärts.
- **Aktionen** (`data-ob`):
  - `next`: nächste Seite, auf der letzten Seite schliessen
  - `skip`: zur Seite setup springen, gibt es sie nicht (Tour), schliessen
  - `close` und `done`: schliessen
  - `backup`: schliessen, `goTab("set")`, Dateiauswahl für das Backup öffnen
  - `create`: schliessen, Formular «Neuer Vertrag» öffnen, Bezeichnung = Vorlage, Kategorie = `obCat(Kategorie)`
- **Einrichten übernehmen** (`obApplySetup`), sobald die Seite setup vorwärts verlassen wird (Knopf oder Wischen):
  - Hauptwährung geändert → `home` setzen und Kurse laden (`autoRate(false)`).
  - Name getrimmt und nicht leer → steht er noch nicht in `holders`, ersetzt er «Ich», gibt es «Ich» nicht, kommt er an den Anfang.
  - `lastHolders = [Name]`, wenn die Liste leer ist oder nur «Ich» enthält.
  - Danach `saveSettings` und `render`.
- **Vorbelegung setup:** Währung beim Erststart **EUR**, in der Tour `settings.home`. «Weitere Währungen» ist aufgeklappt, wenn die gewählte Währung in USD/GBP/TRY liegt. Name = erster Inhaber ≠ «Ich», sonst leer.
- **Schliessen** (`closeOnb`): `onboarded = 1`, `saveSettings`, Overlay ausblenden, `goTab("list")`, `render`.
- USP-Zeilen auf der Willkommensseite: Schrift wird in 0,5-px-Schritten bis 9 px verkleinert, bis alle Zeilen einzeilig passen (SwiftUI: `minimumScaleFactor`).

### 8.2 Seiten mit allen Texten (wörtlich)

**1 welcome**
- App-Logo (apple-touch-icon)
- Slogan «Deine Verträge, ganz entspannt.»
- Überschrift: «Willkommen bei» und darunter die Wortmarke (K als SVG aus dem Logo + «ontivo», aria-label «Kontivo»)
- Untertitel «Maximale Transparenz über alles,» Zeilenumbruch «was jeden Monat fix weggeht.»
- 4 Zeilen mit Häkchen: «Fixkosten, Budget & Fristen im Blick» · «Kontoauszug rein – Fixkosten erkannt» (v135) · «Ohne Bankanbindung – ganz privat» · «Für dich, deine Familie oder deine WG»
- Hauptknopf «Los geht’s» (typografischer Apostroph ’)
- Zweitknopf beim Erststart «Ich habe schon ein Backup», in der Tour «Schliessen»

**2–5 tab** (Chip links = Tab-Symbol + Tab-Name; Titel; Punkte mit Häkchen; Bildschirmfoto `onb/{tab}-light.webp` bzw. `-dark.webp` mit Verlauf und nachgebildeter Tab-Leiste, aktiver Tab hervorgehoben; Knopf «Weiter»)
- list (Chip «Verträge»): «Alle Verträge im Blick» – «Alle Vertragsdetails auf einen Blick» · «Per Kontoauszug in Minuten erfasst» (v135) · «Monatliche Fixkosten sofort sichtbar»
- stat (Chip «Kosten»): «Jeden Monat im Voraus geplant» – «Alle Abbuchungen übersichtlich geplant» · «Bezahlt oder offen sofort erkennen» · «Keine Überraschungen im Briefkasten»
- budget (Chip «Budget»): «Weisst du, was dir bleibt?» – «Einnahmen minus Fixkosten klar berechnet» · «Monatlich und jährlich auf einen Blick»
- term (Chip «Fristen»): «Keine ungewollten Vertragsverlängerungen» – «Kündigungsfristen automatisch berechnet» · «Rechtzeitig vor Fristablauf informiert» · «Kündigen mit einem Tipp – Schreiben fertig» (v135)
- Tab-Leiste (`OB_TABS`): «Verträge» (Dokument), «Kosten» (Balken), «Budget» (Karte/Geldbörse), «Fristen» (Stoppuhr), «Mehr» (drei Punkte)

**6 tips** (Chip «Gut zu wissen» mit Punkte-Symbol; Titel «Clever bis ins Detail»; Liste mit farbigem Symbol, Titel und Untertitel; Knopf «Fertig», wenn es die letzte Seite ist (Tour), sonst «Weiter»)

| Farbe | Symbol | Titel | Text | Etikett |
|---|---|---|---|---|
| #475569 | Bank | «Kontoauszug einlesen» | «Fixkosten aus der CSV-Datei der Bank finden.» | |
| #B0562A | Trendpfeil | «Preisverlauf» | «Sieh, wie sich Vertragspreise verändern.» | |
| #A93227 | Geschenk | «Probeabos im Blick» | «Erinnerung, bevor Kosten entstehen.» | |
| #2E6A4E | Personen | «Für den ganzen Haushalt» | «Verträge nach Personen getrennt.» | |
| #6B4E9E | Büroklammer | «Dokumente am Vertrag» | «PDFs direkt beim Vertrag ablegen.» | |
| #8A6A1F | Etikett | «Verträge kategorisieren» | «Kosten nach Bereichen ordnen.» | |
| #1F4E8C | Dokument | «Kündigung leicht gemacht» | «PDF erstellen, drucken oder per E-Mail versenden.» | |
| #B23A6F | Kamera | «Kontoauszug als PDF oder Foto» | «Einfach fotografieren oder PDF wählen.» | Web «Bald», nativ ohne (gibt es dort) |
| #2F86A6 | Wolke mit Haken | «iCloud-Synchronisierung» | «Deine Daten auf deinen Geräten aktuell.» | «Bald» |

**7 setup** (nur Erststart)
- Chip «Fast geschafft», Titel «Noch zwei Angaben», Untertitel «Beides kannst du später jederzeit unter «Mehr» ändern.»
- Karte «Hauptwährung»: Kacheln EUR, CHF (gross), Knopf «Weitere Währungen» (aufklappbar), darunter USD, GBP, TRY (klein). Jede Kachel zeigt Fahne (SVG `OB_CUR`) und Kürzel fett, gewählt mit Haken; aria-label «EUR (Euro)», «CHF (Franken)», «USD (US-Dollar)», «GBP (Pfund)», «TRY (Lira)». Hinweis «Andere Währungen rechnet Kontivo automatisch um.»
- Karte «Wie heisst du?»: Textfeld, Platzhalter «Name», `autocomplete=given-name`, `enterkeyhint=done`. Hinweis «So ordnest du Verträge dir oder anderen im Haushalt zu.»
- Knopf «Weiter», Zweitknopf «Backup einspielen»

**8 start** (nur Erststart)
- Chip «Letzter Schritt», Titel «Womit fangen wir an?», Untertitel «Lass Kontivo suchen oder starte mit einer Vorlage.» (v110)
- Karte «Automatisch finden» – «Kontoauszug wählen, Vorschläge bestätigen» (Bank-Symbol; Web: Dateiauswahl, nativ: Auswahl Datei / Foto aufnehmen / Aus Fotos, danach Einführung schliessen)
- Abschnitt «Mit Vorlage starten», Hinweis «Tipp an, was du hast – den Rest ergänzt du.», kompakte Chips (Kachel links, zweispaltig)
- 8 Chips (`OB_QUICK`, Bezeichnung → Kategorie, Farbe und Symbol der Kategorie; existiert die Kategorie nicht, wird «Sonstiges» genommen, sonst ""): «Miete» → Wohnen, «Strom» → Energie & Wasser, «Handy» → Mobilfunk & Internet, «Internet» → Mobilfunk & Internet, «Streaming» → Abos & Medien, «Fitness» → Freizeit & Sport, «Kfz-Versicherung» → Versicherung, «Rundfunkbeitrag» → Steuern & Gebühren
- Hauptknopf «Vertrag erfassen» (deaktiviert, bis eine Vorlage gewählt ist), danach «{Vorlage} erfassen»
- Zweitknopf «Erst mal umschauen»

---

## 9. Startablauf (`boot`, 5578–5590, und davor)
1. Inline-Skript (1520–1602): IndexedDB öffnen, alle Blobs laden (`KBlob.ready`), `window.claude` als Ersatz bereitstellen, `navigator.storage.persist()` anfragen. Service Worker bei `load` registrieren (nur unter https oder localhost, `updateViaCache:"none"`).
2. `LOGO` = href des apple-touch-icon.
3. `boot()`:
   - auf `KBlob.ready` warten (Fehler werden ignoriert)
   - `loadLocal()` (inkl. Migration), `buildCatChips()`, `buildSwatches()`, `render()`
   - `assets = await claude.use("assets")` (bei Fehler `null`), damit `#logoUp`/`#docUp` ein- oder ausblenden, dann erneut `render()`
   - **Einführung:** Ist `onboarded` nicht gesetzt und gibt es Verträge oder Einnahmen, wird `onboarded = 1` gespeichert, ohne Einführung. Ohne Daten startet `openOnb(true)`.
   - `autoRate(false)`: höchstens einmal pro Tag, wenn `rateChecked` ≠ heute oder USD fehlt. Quellen der Reihe nach: frankfurter.dev, frankfurter.app, open.er-api. Timeout je 8 s, Plausibilitätsprüfung: EUR zwischen 0.5 und 2 CHF.
4. Später: bei `visibilitychange` auf sichtbar erneut `autoRate(false)`.

---

## 10. Logo-Suche (5023–5200; nativ als Vorschlagsliste mit Bestätigung)
- **Auslöser:**
  - Formular Vertrag `#logoAuto` «Logo automatisch finden» (Vertragspartner, Währung, Bezeichnung, Website)
  - Formular Einnahme `#iLogoAuto` (Name, Währung, Bezeichnung)
  - Vertragspartner-Detail
  - automatisch im Hintergrund nach dem Sichern eines neuen Vertrags oder einer neuen Einnahme ohne Logo (`autoAttach`, nur online)
- **runCands:**
  - primär = Name, sonst Bezeichnung. Ohne Name und ohne Domain: Toast «Zuerst den Namen eintragen». Offline: Toast «Keine Internetverbindung».
  - Anzeige «Suche Logos…», dann `allCats(primär, Währung, null, Web, manual=true)`.
  - Hat kein Kandidat die Quelle `site`, kommt `faviconCand(Domain)` dazu (Punkte 0).
- **Quellen und Punkte:**
  - Wikidata/Commons (`wikiCands`):
    - Volltextsuche `name haswbstatement:P154` (10 Treffer) und `wbsearchentities` (de, 10 Treffer), danach `wbgetentities` für höchstens 20 IDs (claims, labels, aliases, descriptions; de|en|fr|it).
    - Bilddatei: P8972 vor P2910 vor P154.
    - Name exakt (`nameEq`) oder Teiltreffer (`nameHas`); kein Treffer → verworfen.
    - Firma = P31 nicht in `WNOT` und mindestens eines von P856/P452/P159/P1454/P749.
    - Punkte: exakt + Firma 3, exakt 1.5, Teiltreffer 1. Domain passt → max(Punkte, 3)+1. Domain passt nicht → höchstens 2. Abzug 0.001 pro Rang.
    - Mehrdeutig (mehrere exakte Firmen mit verschiedenen Websites, keine passende Domain) → höchstens 2.5.
    - Commons `imageinfo` (Breite 512, höchstens 12 Dateien). Seitenverhältnis > 3.2 → höchstens 2. Hat der Kandidat ≥ 3 Punkte und ein Seitenverhältnis ≤ 1.6, gibt es +0.5.
    - Liefert zusätzlich `dom` (Website des besten Treffers oder der einzigen passenden Firma) und `social` (X P2002, Instagram P2003; nur bei exakter Firma, leer wenn mehrdeutig).
  - App Store (`logoCands`):
    - iTunes Search JSONP, `entity=software`, `limit=20`. Länder je Währung: EUR de,ch · USD us,ch · GBP gb,ch · TRY tr,de · sonst ch,de. Abbruch, sobald ein Treffer ≥ 3 Punkte hat.
    - `lscore`: Spiele 0. Anbieter passt per `nameEq` oder Domain → 3, +2 wenn der App-Name passt (`nameEq`) bzw. +1 bei Teiltreffer, +2 bei Domain-Treffer. Sonst App-Name exakt → 2, Teiltreffer → 1.
  - Website-Symbol (`siteCand`): gstatic faviconV2 256 px, `/apple-touch-icon.png`, `www.`-Variante, alle über images.weserv.nl. Gültig ab 120×120 px, Seitenverhältnis 0.9–1.1.
    - Punkte 6 bei Domain aus dem Vertrag, 5.5 bei Domain aus Wikidata.
    - Nur manuell, ohne bekannte Domain: geratene Domain = Name ohne LGEN-Wörter + `.de/.com/.ch` (EUR) bzw. `.ch/.com/.de` (sonst), Punkte 2.5.
  - Profilbild (`socialCands`, nur manuell, höchstens 2): `unavatar.io/{x|instagram}/{handle}?fallback=false`, ab 150 px, Punkte 4.
  - Favicon (`faviconCand`, nur manuell): Google s2 über weserv, Punkte 0, Quelle `web`.
- **Namenslogik:**
  - `lnorm`: NFD ohne Akzente, ß→ss, & → « und », Nicht-Alphanumerisches → Leerzeichen.
  - `ltok`: Tokens ab 2 Zeichen ohne `LSTOP`.
  - `lusable`: mindestens ein Token mit ≥ 3 Zeichen, das weder in `LGEN` noch in `LPLACE` steht.
  - `teq`: gleich, oder ab 6 Zeichen mit Plural-Endung s/en.
  - `nameEq`: alle Suchwörter vorhanden, zusätzliche Wörter nur aus LGEN/LADJ. Listen siehe 4947–4952.
- **Sortierung:** nach Punkten absteigend, bei Gleichstand Wikipedia vor anderen. Doppelte URLs entfernt.
- **Anzeige** (`paintCands`, höchstens 10):
  - Kopfzeile «Tippe auf das passende Logo:», wenn der erste Kandidat ≥ 3 Punkte hat, sonst «Keine eindeutige Übereinstimmung – passt eines davon?»
  - leer: «Nichts gefunden. Tipp: Vertragspartner oder Bezeichnung so schreiben, wie die Firma heisst, eine Website eintragen, oder «Logo im Web suchen».»
  - Kachel mit Bild, Titel und Quelle (`LSRC`): «Wikipedia», «Website», «Website-Symbol», «Profilbild», sonst «App Store». Unter 3 Punkten blass (`weak`), Wikipedia als breite Kachel.
- **Übernahme** (`takeLogo`):
  - Toast «Übernehme Logo…»
  - wiki → `padBlob(url)`: Mindestkante 200 px, auf 512×512 eingepasst in ein 420er-Feld, Hintergrund #FFFFFF; wirkt das Ergebnis leer (Standardabweichung der Helligkeit < 8 auf 48×48), Hintergrund #1C1C1E; als Ausweichquelle weserv.
  - site/social → `padBlob(url,120,true)` (füllend)
  - store/web → `logoBlob`: Mindestkante 256 px, Seitenverhältnis 0.8–1.25, Standardabweichung ≥ 6 und ≥ 60 % deckende Pixel auf 32×32, auf 512×512 weiss; Ausweichquellen: 512er-Variante der Artwork-URL, Original, weserv.
  - Ergebnis über `assets.upload` speichern → `{id, bg}`. Toast «Logo übernommen». Fehler laut `LERR`: «Bild zu klein oder nicht quadratisch», «Bild wirkt leer oder einfarbig», «Bild konnte nicht geladen werden», «Speichern nicht möglich», sonst «Übernahme fehlgeschlagen».
- **Automatisch** (`autoLogo`/`autoAttach`): Name, sonst Bezeichnung. Von den Kandidaten mit ≥ 3 Punkten werden die ersten 3 der Reihe nach versucht. Das Logo wird nur gesetzt, wenn der Eintrag noch existiert und noch kein Logo hat. Toast «Logo für «{Name}» ergänzt».

---

## 11. Service Worker und Manifest (entfällt nativ)
- `VERSION = "kontivo-v60"`, muss bei jeder Version erhöht werden.
- CORE: `./`, `index.html`, `manifest.webmanifest`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`, `onb/{list,stat,budget,term}-{light,dark}.webp`, `fonts/{Hurricane-Regular,LaBelleAurore,Licorice-Regular,Zeyada,Qwigley-Regular,Bilbo-Regular}.ttf`.
- install: `addAll(CORE)`, danach `skipWaiting`. activate: alle Caches ausser VERSION löschen (auch alte `-ext`), danach `clients.claim`.
- fetch, gleiche Herkunft (GET): erst Netz mit `cache:"no-cache"`; bei `ok` Kopie in den Cache. Lehnt `fetch` ab: `caches.match(req,{ignoreSearch:true})`, sonst `index.html`.
- fetch für fonts.googleapis, fonts.gstatic und cdnjs (pdf.js 3.11.174): Cache `VERSION-ext`, Antwort aus dem Cache und Auffrischen im Hintergrund (auch bei opaker Antwort).
- Manifest: name/short_name «Kontivo», description «Deine Verträge, ganz entspannt», lang de-CH, start_url und scope `./`, display standalone, orientation any, background_color und theme_color #F3F1EC, Icons 192/512 (any) und 512 (maskable).
