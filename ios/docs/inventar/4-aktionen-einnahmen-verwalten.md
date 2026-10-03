# R4 Portierungs-Inventar: index.html Zeilen 3726–4434

Zweck: identisches Verhalten in SwiftUI ohne Blick in den JS-Code. Texte in «» sind wörtlich, Platzhalter in <>. JS-Namen in Klammern.
Datumsformate: `fmtD` = «3. Oktober 2026» (Tag ohne Null, Monat ausgeschrieben); `fmtShort` = «03.10.26»; ISO intern «JJJJ-MM-TT». Geldformat `money` = de-CH mit 2 Nachkommastellen («1’284.50»). Toasts verschwinden nach 2.4 s, ein neuer Toast ersetzt den alten.
Hilfsbegriffe: `titleOf(c)` = label, sonst partner, sonst name, sonst «Ohne Namen». `holdersOf(c)` = holders[] oder []. `termEnd(c)` = nächstes mögliches Vertragsende (Rechenkern, siehe tests/). `isActiveC(c)` = nicht status cancelled und nicht `cancelPer < heute`.

Bekannte Fehler stehen in r4-findings.md. Wo der Nachbau bewusst abweichen sollte, steht hier **[Fix]**.

---

## 1. Vertragsdetail: Ende der Aktionen (3726–3731)

### 1.1 «Per E-Mail kündigen» (data-act `kmail`, Fortsetzung)
- Vorbedingung (3725): ohne `c.mail` die Rückfrage Titel «E-Mail-Adresse fehlt», Text «Trag die Kündigungsadresse des Vertragspartners beim Vertrag unter «Kontakt» ein.», OK «Eintragen». Bei OK schliessen sich alle Fenster und nach 180 ms öffnet das Vertragsformular auf der Seite «Weitere Angaben».
- Mit E-Mail: `letterParts(c)` liefert Betreff, Referenzzeilen (`ref[]`), Text (`body`) und Namen (`names[]`). Mailtext = `[ref.join("\n"), body, names.join("\n")]`, leere Teile weglassen, mit Leerzeile verbunden.
- Merkt `kPending = Vertrags-ID` und öffnet `mailto:<c.mail getrimmt>?subject=<URI-kodiert>&body=<URI-kodiert>`.
- SwiftUI: MFMailComposeViewController mit Empfänger, Betreff, Text; `kPending` auslösen, wenn die Mail-Ansicht schliesst.

### 1.2 Fenster öffnen
- Danach wird `#sheetDetail` geöffnet (Scrim an, Fenster an, nach oben gescrollt).

### Kontext aus dem Nachbarabschnitt (3706–3725, nur zur Orientierung)
Detail-Aktionen: «Schliessen»; «Bearbeiten» (Formular nach 180 ms); «Duplizieren» (Formular als Kopie ohne Dokumente und Sonderzahlungen); «Pausieren» öffnet die Pausen-Auswahl, «Fortsetzen» setzt paused=false, pausedAt="", pausedUntil="" mit Toast «Fortgesetzt»; «Als gekündigt ins Archiv» setzt status="cancelled" und cancelledAt=heute mit Toast «Ins Archiv verschoben»; «Wieder aktiv setzen» setzt status="active" und cancelledAt="" mit Toast «Wieder aktiv»; «Kündigung zurücknehmen» setzt cancelPer="" und cancelledOn="" mit Toast «Kündigung zurückgenommen»; «Entscheid «Behalten» zurücksetzen» setzt keptFor="" mit Toast «Wieder offen»; «Vertrag löschen» fragt Titel «Vertrag löschen?», Text ««<Titel>» wird endgültig gelöscht. Angehängte Dateien bleiben erhalten.», OK «Löschen» (rot), danach Toast «Gelöscht». Kündigungsknopf je Weg: «Online kündigen» / «Per E-Mail kündigen» / «Kündigungsschreiben» / «Kündigen …». Er fehlt bei `cancelPer` oder status cancelled. «Online kündigen» ohne Link: Toast «Kein Link hinterlegt. Trag Website oder Kündigungslink ein.» und Formular «Weitere Angaben». Mit Link: `kPending`, Toast «Nach der Kündigung hier bestätigen», Link nach 350 ms.

---

## 2. Gesten und Fenster-Verhalten

### 2.1 Wischen zum Schliessen (3732–3737)
- Gilt für `#sheetDetail`, `#sheetPick` und `#sheetMd` (nicht für Formular und Einnahme).
- Start nur, wenn das Fenster ganz oben gescrollt ist (`scrollTop<=0`). Zug nach unten verschiebt das Fenster live (translateY), nach oben passiert nichts.
- Loslassen bei mehr als 90 px schliesst: `#sheetMd` über `closeMd()`; `#sheetPick` mit Klasse `over` nur dieses Fenster (`closePick`), sonst alle (`closeSheets`); `#sheetDetail` alle. Bei 90 px oder weniger springt das Fenster zurück.
- SwiftUI: Standard-Sheet mit `.presentationDragIndicator`. Über einem anderen Sheet geöffnete Auswahl = verschachteltes Sheet.

### 2.2 Detail-Kopfzeile (3738)
- Scrollt `#sheetDetail` über 60 px, zeigt die Kopfzeile den Vertragsnamen (Klasse `scrolled`). SwiftUI: `.navigationTitle` mit inline-Darstellung beim Scrollen.

### 2.3 Scrim antippen (4043–4050): Reihenfolge der Prüfung
1. Rückfrage offen → wie «Abbrechen» (`askDone(false)`)
2. Zuschneiden offen → `closeCrop`
3. Unterschrift zeichnen offen → `closeSig`
4. Namenszug-Vorschläge offen → `closeSigPick`
5. Kündigungsschreiben offen → `closeLetter` **[Fix: Verwalten mit `over` müsste vor dem Brief kommen, siehe M2]**
6. Auswahl (`#sheetPick`) mit `over` → nur diese schliessen
7. Verwalten offen → `closeMd`
8. sonst alle Fenster schliessen (Formular und Einnahme ohne Rückfrage, Eingaben verworfen)

### 2.4 Monatswechsel auf der Monatskarte (3779–3831)
- Nur in den Tabs «Kosten» (`stat`) und «Budget» (`budget`), nur auf `.kcard`. Maus nur mit linker Taste.
- Modus beim Aufsetzen: auf Balken oder Monatslabels (`.chart`, `.bchart`, `.mlabels`) = **Scrubbing**, sonst = **Paging**.
- Richtungssperre: erst ab 6 px Bewegung. Ist die Bewegung vertikal stärker als horizontal, bricht die Geste ab (Seite scrollt). Sonst wird gesperrt und der Zeiger festgehalten.
- Scrubbing: Monatsindex = floor((x − Balken.links) / Balken.breite × 12), begrenzt auf 0…11. Bei Änderung `state.sel` setzen und neu zeichnen.
- Paging: Karte folgt dem Finger (translateX = dx, Deckkraft 1 − min(|dx|/Breite, 1) × 0.45). Beim Loslassen wird gewechselt, wenn |dx| > 22 % der Kartenbreite **oder** (|dx| > 30 px **und** |v| > 0.35 px/ms). Richtung: dx<0 → nächster Monat, dx>0 → vorheriger. Animation: 160 ms hinaus, nach 150 ms `shiftMonth(step,true)`, die neue Karte gleitet ein (Klasse inr/inl, 300 ms). Ohne Wechsel federt die Karte zurück (220 ms).
- Nach jeder gesperrten Geste werden Klicks auf der Karte 400 ms lang ignoriert (`state._swiped`).
- Abbruch (pointercancel) im Paging: Karte zurücksetzen.
- `canShift(step)`: verboten ist nur ein Schritt über Dezember hinaus, wenn das Jahr ≥ aktuelles Jahr + 5. Nach unten gibt es keine Grenze.
- `shiftMonth(step)`: Monat ± 1, über Dezember/Januar ins Nachbarjahr (`state.year`).
- SwiftUI: DragGesture mit `chartOverlay` (Scrubbing) bzw. TabView(.page) oder eigener Offset (Paging).

---

## 3. Kündigen, Behalten, Kündigungsweg

### 3.1 Rückkehr nach Online- oder E-Mail-Kündigung (`kPending`, 3740–3745)
- Wird die App wieder sichtbar und ist `kPending` gesetzt: Merker leeren. Existiert der Vertrag nicht mehr, nichts tun. Sonst nach 400 ms die Rückfrage:
  - Titel «Gekündigt?»
  - Text ««<Titel>» als gekündigt markieren, läuft bis <fmtD(termEnd)>. Der Vertrag zählt bis zum Ende weiter und wandert danach ins Archiv.» (den Teil «, läuft bis …» nur, wenn termEnd berechenbar ist)
  - OK «Ja, gekündigt», Abbrechen = Standard
- Bei OK `markCancelled(id, trial=false)`. **[Fix M6: trial mitführen]**
- SwiftUI: `scenePhase == .active` statt visibilitychange.

### 3.2 Kündigungsweg wählen (`openCancViaPick`, 3746–3754; Auswertung 3943–3945)
- Auswahl über dem Detail (`over`), Titel «Wie kündigst du «<Titel>»?».
- Drei Zeilen (links fett, rechts grau): «Online» | «Kundenkonto, Kündigungsbutton»; «Per E-Mail» | «Mail mit fertigem Text»; «Per Brief» | «PDF mit Unterschrift».
- Hinweis: «Wird beim Vertrag gespeichert. Miete braucht immer einen Brief mit Unterschrift.»
- Tippen speichert `cancF` = «Online / Kundenkonto» bzw. «E-Mail» bzw. «Brief». Dann Auswahl schliessen, neu zeichnen, alle Fenster schliessen, nach 180 ms das Detail neu öffnen, nach weiteren 150 ms zum Kündigungsknopf scrollen und ihn auslösen.
- Abbildung `cancVia`: «Online / Kundenkonto» → online; «E-Mail» → mail; «Brief» und «Einschreiben» → post; ohne Angabe: Miete (isRent) oder Kategorie «Versicherung» → post, sonst offen. SwiftUI: `enum CancelChannel`.

### 3.3 Kündigen aus «Fristen» (`killOptions`, 3757–3768)
- Auswahl (normal, nicht `over`), Titel «Wechseln: <Titel>» bei Pflichtvertrag (`mand`), sonst «Kündigen: <Titel>».
- T = Probeabo-Datum (bei Probeabo) oder `termEnd(c)`.
- Zeile 1 (`letter`): links je Weg «Online kündigen» / «Per E-Mail kündigen» / «Kündigungsschreiben erstellen» / «Kündigen: Weg wählen …», rechts `c.cancF` (Text des Wegs, falls gesetzt).
- Zeile 2 (`done`): links «Gekündigt, neuen Anbieter erfassen» (mand) bzw. «Als gekündigt markieren», rechts «läuft bis <fmtShort(T)>» (wenn T).
- Hinweis, wenn T vorhanden: Probeabo «Kündigung muss vor dem <fmtD(T)> sein. », sonst «Kündigung muss bis <fmtD(Kündigungstermin)> beim Anbieter sein. ». Kündigungstermin = `nDl(c,T)`. Danach immer «Nach dem Markieren zählt der Vertrag bis zum Ende weiter und wandert danach ins Archiv.»
- Auswertung (3946–3951): `done` → `markCancelled(id, trial)`. `letter` → alle Fenster schliessen, nach 180 ms Detail öffnen, nach 120 ms den Kündigungsknopf auslösen und hinscrollen.

### 3.4 Als gekündigt markieren (`markCancelled`, 3769–3778)
- Kündigungsende T: Probeabo → Probeabo-Datum − 1 Tag; sonst `termEnd(c)`. **[Fix N10: Anzeige und Speicherung angleichen]**
- Speichert `cancelPer = T` (ohne T: heute), `cancelledOn = heute`. `status` bleibt "active". Der Vertrag zählt bis `cancelPer` weiter und ist ab dem Folgetag archiviert.
- Fenster schliessen, neu zeichnen, Toast «Gekündigt — läuft bis <fmtD(cancelPer)>».
- Pflichtvertrag (`mand`): Kopie als neuer Vertrag mit cancelPer="", cancelledOn="", keptFor="", partner="", logoId="", logoBg="", start = cancelPer + 1 Tag, due = start, custNo="", contrNo="", docs=[], prices=[], extras=[]. Nach 250 ms öffnet das Formular als Kopie mit Titel «Neuer Anbieter» und Toast «Neuen Anbieter erfassen — ab <fmtD(start)>». **[Fix M4: zusätzlich web, mail, tel, addr, cancUrl, cancF, note, trial, trialKept, paused* leeren; Titel auch nach Unterseite behalten]**

### 3.5 Behalten (`data-keep`, 3834–3837)
- Probeabo-Karte: `trialKept = trial`. Fristkarte: `keptFor = ISO(termEnd(c))`.
- Neu zeichnen, Toast «Behalten — erledigt bis zum nächsten Termin».
- Regel: «behalten» gilt, solange `keptFor === termEnd`. Rückt termEnd weiter (Verlängerung oder nächster Termin), ist der Vertrag wieder offen.

### 3.6 Pausieren aus der Auswahl (`pause-<id>`, 3930–3936)
- Optionen (`openPausePick`, Nachbarabschnitt): 1, 3 oder 6 Monate («bis <fmtD>») und «Ohne Enddatum» («bis du fortsetzt»), dazu ein Datumsfeld mit Knopf «Pausieren».
- Datumsknopf: leer oder ≤ heute → Toast «Bitte ein Datum in der Zukunft wählen», sonst `applyPause(id, Datum)`.
- Option: `applyPause(id, heute + n Monate)` bzw. ohne Ende "".
- `applyPause`: paused=true, pausedAt=heute, pausedUntil=Datum oder "", Toast «Pausiert bis <fmtD>» bzw. «Pausiert — bis du fortsetzt».

---

## 4. Klicks im Hauptbereich (#view, 3832–3892), Reihenfolge = Priorität
Klicks auf `.kcard` werden 400 ms nach einer Wischgeste ignoriert.

| Auslöser | Wirkung |
|---|---|
| `data-keep` | siehe 3.5 |
| `data-tfold=<key>` | Gruppe in «Fristen» auf- oder zuklappen (`state.tfold[key]`), neu zeichnen |
| `data-kill` (+`data-trial`) | `killOptions(id, trial)` |
| `data-bm=<i>` | Budget: Monat i wählen |
| `data-inc=<id>` | Einnahme bearbeiten |
| `data-incall` | Fenster «Alle Einnahmen» (`openIncAll`) |
| `#incAdd` | neue Einnahme |
| `data-archtog` | Archiv in «Verträge» ein- oder ausblenden (`state.showArch`) |
| `data-sortpick` | (wird nirgends erzeugt, tot) |
| `data-rv="ok"` | Quartals-Check: `lastReview=heute`, `reviewSnooze=""`, Toast «Geprüft — nächste Erinnerung in drei Monaten» |
| `data-rv="later"` | `reviewSnooze = heute + 7 Tage` (kein Toast) |
| `data-bh=<Name>` | Budget-Personenfilter setzen (`state.bHolder`, "" = alle) |
| `data-bhdel` | Budget-Personenfilter entfernen |
| `data-bsheet` | Auswahl «Inhaber»: Zeile «Alle Inhaber» und je Person eine Zeile (gewählt markiert), Hinweis «Gemeinsame Verträge und Einnahmen zählen anteilig.»; Tippen setzt `bHolder` und schliesst |
| `data-msort=date/amt` | Kosten: Monatsliste nach Datum oder Betrag sortieren |
| `data-paidtog` | «Bereits bezahlt (n)» auf- oder zuklappen |
| `data-onb="c"` | neuer Vertrag |
| `data-onb="i"` | Tab Budget, dann neue Einnahme |
| `data-onb="b"` | Tab «Mehr», dann Backup laden auslösen |
| `data-fsheet` | (tot) |
| `data-hfdel` | Hero-Filter entfernen |
| `data-fdel=<dim>` | Kosten-Filter dim entfernen, Monat automatisch wählen (`autoSel`) |
| `data-fdim=<dim>` | Filter-Auswahl für dim öffnen |
| `data-fh=<Name>` | Kosten-Inhaber-Chip ("" = alle) |
| `data-fmore` | Weitere Filter auf- oder zuklappen; ist Kategorie oder Vertragspartner aktiv: Toast «Erst Kategorie und Vertragspartner zurücksetzen» |
| `data-fclear2` | Kategorie und Vertragspartner zurücksetzen, «Weitere» zuklappen |
| `data-fclear` | alle Kosten-Filter zurücksetzen |
| `data-sf="<G>\|<Wert>"` | Aufteilung: Segment wählen oder abwählen (`state.ringSel`), Scrollposition halten |
| `data-sg=cat/partner` | Aufteilen nach (`state.sg`), «Alle» zuklappen |
| `data-ss=year/month` | Zeitraum der Aufteilung (`state.ss`) |
| `data-sgall` | «Übrige» auf- oder zuklappen |
| `data-sort` | (tot) |
| `data-y=±1` | Jahr wechseln; aktuelles Jahr → aktueller Monat, sonst Januar |
| `data-m=<i>` | Kosten: Monat i wählen |
| `data-open=<id>` | Vertragsdetail |

### 4.1 Weitere Bedienelemente
- Tabbar (3893–3899): Tab setzen, `aria-selected`, neu zeichnen, FAB anpassen, nach oben scrollen.
- Hero-Chips (3900–3901): «n aktiv ›», «n pausiert ›», «n noch nicht aktiv ›» schalten `state.heroF` (act/paused/fut) um.
- `#hFlag` (3902–3906) und `#reviewCard` (3908–3912): tot (immer verborgen bzw. leer). **Nicht portieren.**
- «+» (`#addBtn`): neuer Vertrag.
- Suchfeld (`#q`): `state.q` bei jeder Eingabe, neu zeichnen.
- Sortierknopf: Auswahl «Sortieren nach».
- Filterknopf → `openFilterSheet`.

### 4.2 Filter-Auswahl (`openFilterSheet`, 3917–3925)
- Titel «Filter», drei Zeilen: «Kategorie» / «Vertragspartner» / «Inhaber», rechts der aktuelle Wert oder «Alle», gefolgt von « ›».
- Bei aktiven Filtern zusätzlich «Alle Filter zurücksetzen». Das setzt alle drei zurück, wählt den Monat automatisch und schliesst.
- Zeile antippen → Werteliste der Dimension (`openPick(dim)`).

### 4.3 Auswahl-Fenster `#sheetPick`: Auswertung nach Art (3926–3965)
- `incall`: Einnahme-Zeile oder «Einnahme erfassen» schliesst alles, nach 180 ms öffnet das Einnahmen-Formular.
- `pause-<id>`: siehe 3.6.
- `bholder`: siehe Tabelle.
- `tplpick`: Länder-Chip filtert den Katalog, ein Eintrag übernimmt die Vorlage (`applyTpl`) und schliesst.
- `cvia-<id>`: siehe 3.2. `kill-<id>[-t]`: siehe 3.3.
- `catpick-c` / `catpick-i`: Kategorie für Vertrag bzw. Einnahme übernehmen. «Hinzufügen» (nur Vertrag) legt eine eigene Kategorie an. Enter im Feld wirkt wie «Hinzufügen» (4051).
- `sort`: `settings.sort` = Wert, Standard «cat».
- `cat` / `partner` / `holder`: Kosten-Filter = Wert, "" = alle, Monat automatisch wählen, schliessen.
- Adress-Auswahl (`addrpe`, `addrpick`) hat eigene Handler (ausserhalb).
- Schliessen-Knopf (3966): mit `over` nur die Auswahl, sonst alle.

---

## 5. Einnahmen-Formular (3967–4042)

### 5.1 Daten (`incomes[id]`)
name (Quelle), label (Bezeichnung), cat (Art), amount, cur, cycle (0 = einmalig, 1, 2, 3, 6, 12, 24), due (Zahltag), start, end, holders[], prices[{from, amount}], note, logoId, logoBg, color, status ("active"), t (Erstellzeit).
Arten (fest, nicht verwaltbar): Lohn, Nebeneinkommen, Bonus, Kapitalerträge, Vermietung, Rente, Sonstiges.

### 5.2 Öffnen (`openIncome(id|null)`)
- Titel «Einnahme bearbeiten» bzw. «Neue Einnahme». Logo-Bereich zugeklappt, Logo-Vorschläge leeren.
- Vorbelegung: neu = Art «Lohn», Betrag leer, Währung = Hauptwährung, Turnus monatlich, Zahltag heute, Empfänger = erster Inhaber. Bestehend = gespeicherte Werte, Betrag mit 2 Nachkommastellen.
- «Einnahme löschen» nur bei bestehender Einnahme sichtbar.

### 5.3 Felder und Anzeige
- Logo-Vorschau (`iPaintLogo`): vorhandenes Logo auf `logoBg` (Standard weiss), sonst Kategorie-Farbe mit Kategorie-Symbol. «Logo entfernen» nur bei Logo, «Hochladen» nur mit Dateispeicher. «Hochladen» → Datei wählen → Zuschneiden (Ziel Einnahme). «Logo entfernen» → logoId="", logoBg="".
- Empfänger (`iPaintChips`): Chips für alle Inhaber plus bereits zugeordnete, unbekannte Namen. Gewählte sind markiert. Tippen setzt **genau diese eine Person** (`[x]`). Überschrift im HTML: «Empfänger — genau eine Person».
- Betragslabel: «Anfangsbetrag netto», wenn Änderungen vorhanden sind, sonst «Betrag netto».
- Änderungsliste (`iPaintPrices`), sortiert nach Datum: erste Zeile «Anfangsbetrag» mit Feldbetrag (sonst «—») und Währung, danach je Änderung «ab <fmtD(from)>», Betrag, Währung und «×». Markierung «aktuell» an der letzten Änderung mit Datum ≤ heute (ohne solche am Anfangsbetrag), «geplant» an künftigen. Neu zeichnen bei Eingabe im Betrag und bei Währungswechsel.
- «Änderung hinzufügen» (`iPAdd`): ohne Datum Toast «Datum fehlt»; Betrag ungültig oder < 0 → «Betrag prüfen». Eine bestehende Änderung mit gleichem Datum wird ersetzt, Betrag auf 2 Stellen gerundet. Danach Felder leeren.
- «×» entfernt die Änderung mit diesem Datum.

### 5.4 Sichern (`iSave`)
- Prüfungen: Quelle und Bezeichnung beide leer → «Bezeichnung fehlt». Betrag leer, ungültig oder < 0 → «Betrag prüfen» (0 ist erlaubt).
- Speichert ein neues Objekt mit allen Feldern aus 5.1. color und t kommen aus dem alten Stand, status immer "active". Fehlt der Zahltag, gilt heute.
- Neue ID bei Neuerfassung. Fenster schliessen, neu zeichnen, Toast «Aktualisiert» bzw. «Einnahme erfasst».
- Neu, ohne Logo, mit Quelle oder Bezeichnung: Logo-Suche im Hintergrund (`autoAttach`) mit Toast «Logo für «<Name>» ergänzt». **[Fix N13: nur als Vorschlag]**

### 5.5 Abbrechen und Löschen
- «Abbrechen» schliesst alle Fenster ohne Rückfrage.
- Löschen: Titel «Einnahme löschen?», Text ««<Bezeichnung oder Quelle>» wird endgültig gelöscht.», OK «Löschen» (rot). Danach entfernen, schliessen und Toast «Gelöscht».

---

## 6. Vertragspartner-Gruppen (`partnerGroups`, 4054–4072)
- Gruppierung aller Verträge (auch gekündigter) nach `partner.trim().toLowerCase()`. Ohne Partner kein Eintrag.
- Je Gruppe: key; names (Schreibweise → Anzahl); ids (in der Reihenfolge der Verträge); web = erste vorhandene Website; addr = erste vorhandene Adresse; logoC = erster Vertrag mit vorhandenem Logo; cost = Summe Monatskosten × 12 aller Verträge ohne status cancelled und ohne cancelPer. **[Fix N3: Regel wie `perMonth`: `isActiveC && !isPaused`]**
- name = häufigste Schreibweise, bei Gleichstand die zuerst gesehene.
- pk = normierter Vergleichsschlüssel (`pkey`: Wörter ohne Stoppwörter/Rechtsformen). dup = mehr als eine Gruppe mit gleichem pk.
- Sortierung nach Name (de-CH, ohne Gross-/Kleinschreibung).
- SwiftUI: eigene Entität Partner (Name, Web, Logo, Adresse). Dubletten-Erkennung über den normierten Schlüssel.

---

## 7. Datenqualität

### 7.1 Ignorieren
- `settings.qIgn` = {Schlüssel: 1}. Ignorierte Punkte zählen nirgends, werden aber unten gezählt.
- Schlüssel: `c:<id>:<feld>`, `i:<id>:<feld>`, `p:<partnerkey>:<feld>`, `h:<Inhaber>:sender`.

### 7.2 Prüfregeln (`qualItems`, 4075–4114), vollständig
Geprüft werden **alle Verträge ausser status "cancelled"** **[Fix M5: zusätzlich gekündigte (cancelPer) und archivierte ausnehmen]**. Anzeigename = label, sonst partner, sonst «Ohne Namen». Zusatz = partner, wenn label und partner gesetzt sind.

| Gruppe | Schlüssel | Bedingung | Grund (wörtlich) |
|---|---|---|---|
| A Kosten und Budget | `c:id:holder` | keine Inhaber | «Kein Inhaber» |
| A | `c:id:amount` | Betrag nicht > 0 | «Betrag fehlt oder ist 0» |
| A | `c:id:cat` | Kategorie leer / «Sonstiges» / nicht in der Kategorienliste | «Keine Kategorie» / «Kategorie «Sonstiges»» / «Kategorie «<X>» gibt es nicht mehr» |
| A | `c:id:cycle` | Turnus nicht > 0 | «Zahlungsweise fehlt» |
| B Fristen | `c:id:due` | kein gültiges Fälligkeitsdatum | «Kein Fälligkeitsdatum» |
| B | `c:id:notice` | nur wenn kein cancelPer, nicht «nicht beobachtet», kein Pflichtvertrag, keine Steuer (Kategorie beginnt mit «Steuern») **und** Kündigungstermin nicht berechenbar | ohne Frist und ohne «Kündbar per»: «Keine Kündigungsfrist», sonst «Laufzeit oder Rhythmus fehlt» **[Fix N2: «jederzeit» mit Frist nicht melden]** |
| D Kündigen (nicht bei Steuern) | `c:id:via` | Kündigungsweg offen | «Kündigungsweg festlegen» |
| D | `c:id:ref` | Weg gesetzt, weder Kunden- noch Vertragsnummer | «Kundennummer fehlt» |
| D | `c:id:link` | Weg online, kein Link (cancUrl, sonst web) | «Kündigungslink fehlt» |
| D | `c:id:mail` | Weg E-Mail, keine E-Mail | «E-Mail-Adresse fehlt» |
| D | `p:key:addr` | Partner mit mindestens einem Brief-Vertrag (der einen Partner hat) und Gruppe ohne Adresse | «Adresse fehlt (Kündigung per Brief)», Zusatz «n Vertrag/Verträge» |
| D | `h:Name:sender` | Bedarf 2 (Inhaber eines Brief-Vertrags): Absender nicht vollständig (Vor- oder Nachname **und** Strasse **und** Ort) | «Absender unvollständig», Zusatz «Inhaber · für Kündigung per Brief» |
| D | `h:Name:sender` | Bedarf 1 (nur E-Mail-Verträge): weder Vor- noch Nachname | «Name des Absenders fehlt», Zusatz «Inhaber · für Kündigung per E-Mail» |
| A (Einnahmen, alle) | `i:id:holder` | keine Empfänger | «Kein Inhaber», Zusatz «Einnahme» |
| A (Einnahmen) | `i:id:amount` | Betrag nicht > 0 | «Betrag fehlt oder ist 0» |
| C Vertragspartner | `p:key:logo` | Gruppe mit mindestens einem Vertrag ohne status cancelled und ohne Logo | «Kein Logo» (Suchen möglich) |

- Partner-Prüfungen (C Logo, D Adresse) laufen nur für Gruppen mit mindestens einem Vertrag ohne status cancelled. Der Brief-Bedarf (pNeed) stammt nur aus geprüften Verträgen.
- Reihenfolge der Ausgabe je Gruppe: zuerst Verträge (in Speicherreihenfolge), dann Einnahmen, dann Partner (alphabetisch), dann Inhaber.
- Bedarf pro Inhaber = Maximum über seine Verträge mit gesetztem Weg (Brief 2, E-Mail 1, online 0). Verträge mit offenem Weg zählen nicht.
- Absender-Auflösung: Hat eine Person «gleich wie Y», kommen Strasse, PLZ, Ort und Land von Y (nur eine Stufe) **[Fix M1]**.
- Bewusst nicht geprüft: Währung, Start, Preisänderungen, Verträge ohne Partner beim Brief-Adressbedarf **[Fix N4]**.

### 7.3 Zähler
- `qualOpenContracts`: Anzahl **betroffener Einträge** (Vertrag, Einnahme, Partner, Inhaber je einmal) über alle Gruppen.
- Statuskarte: Anzahl **Punkte** (alle Hinweise).

### 7.4 Seite «Datenqualität» (`paintMdQual`, 4190–4199)
- N = Verträge ohne status cancelled **[Fix M5: laufende Verträge]**.
- N = 0: «Noch keine laufenden Verträge. Sobald du welche erfasst, siehst du hier, was fehlt.» (ohne Checkliste)
- Mit offenen Punkten: Karte fett «<n> offener Punkt.» / «<n> offene Punkte.», darunter «Tippe unten auf «offen», um sie zu erledigen.»
- Ohne offene Punkte: grüne Karte mit Häkchen, fett «Sauber gepflegt. Dein Vertrag ist vollständig.» (N = 1) bzw. «Sauber gepflegt. Alle <N> Verträge sind vollständig.», darunter «Kosten, Budget, Fristen und Kündigungen stimmen.»
- Bei N > 0 folgt die Checkliste (7.5).
- Gibt es Ignorierte: «<k> ignoriert · Zurücksetzen» (Link). «Zurücksetzen» leert `qIgn`.

### 7.5 Checkliste «Was geprüft wird» (`qualChecklist` + `Q_ROWS`, 4167–4181)
- Kopf «Was geprüft wird» klein «<N> Vertrag/Verträge[, <NI> Einnahme/Einnahmen]».
- Gruppen in dieser Reihenfolge, je ein weisser Block. Die Überschrift trägt die grüne Pille «vollständig» nur bei 0 Punkten in der Gruppe:
  - **Kosten und Budget:** Inhaber · Betrag · Kategorie · Zahlungsweise · Einnahmen: Betrag, Inhaber (nur wenn es Einnahmen gibt)
  - **Fristen:** Fälligkeit · Kündigungsfrist und Laufzeit
  - **Kündigen:** Kündigungsweg gewählt · Kunden- oder Vertragsnummer · Link (Online) · E-Mail-Adresse (E-Mail) · Adresse des Vertragspartners (Brief) · Absender der Inhaber
  - **Vertragspartner:** Logo
- Zeile mit Treffern: Name, «<m> offen», «›», antippbar → Seite `qlist` (Gruppe, Feld, Titel = Zeilenname). Ohne Treffer: Name und «✓».
- Zuordnung Zeile → Punkte (`qSel`): «Einnahmen…» = alle Einnahmen-Punkte; sonst letztes Schlüsselsegment = Feld. In Gruppe A nur Verträge.
- Fusstext: «Tippe auf «offen», um die Einträge zu sehen. Gekündigte Verträge und ignorierte Hinweise zählen nicht. Nicht überwachte Verträge, Pflichtverträge und Steuern brauchen keine Frist. Adresse, E-Mail und Link werden nur für den gewählten Kündigungsweg verlangt.»

### 7.6 Zeilen der Seite qlist (`qRows`, 4182–4189)
- Zeile: Marke (Einnahme-Logo, Personenbild/Initiale oder Vertrags-/Partner-Logo), Name fett, darunter klein. Bei Feldern mit Inline-Editor (ausser Frist und Einnahmen) nur der Zusatz, sonst «Grund · Zusatz».
- Antippen: Vertrag → Formular, Einnahme → Einnahmen-Formular, Inhaber → Absender-Seite, Partner → Partner-Seite.
- Rechts: bei Logo «Suchen», immer «Ignorieren». Darunter der Inline-Editor (`qEditor`, ausserhalb; Felder laut `QE_INLINE`: holder, amount, cat, cycle, due, via, ref, link, mail, notice, inc, addr, sender).

### 7.7 Übersicht in «Mehr → Verwalten» (`paintMdSummary`, 4200–4211)
- Vertragspartner rechts: «<d> Dublette»/«<d> Dubletten» (orange, fett), sonst Anzahl der Gruppen, ohne Gruppen «–».
- Inhaber rechts: bis 2 Personen die Namen mit «, », ab 3 «<n> Personen».
- Kategorien rechts: Anzahl.
- Datenqualität rechts: ohne laufende Verträge «–»; mit offenen Einträgen «<n> Eintrag offen»/«<n> Einträge offen» (orange); sonst «Sauber gepflegt ✓» (grün). Fett, sobald Verträge vorhanden sind. Untertitel: «Alles da, nichts fehlt. Gut gemacht.» bei sauber, sonst «Was bei deinen Verträgen noch fehlt».
- Aufruf bei jedem Zeichnen von Verwalten und beim Füllen der Seite «Mehr».

---

## 8. Automatische Logo-Suche mit Bestätigung (4115–4163)
- Start: «Suchen» je Partner öffnet die Partner-Seite und löst dort «Logo automatisch finden» aus. «Alle suchen» → `qSearch("*")`.
- `qSearch`: läuft schon eine Suche, nichts tun. Offline → Toast «Keine Internetverbindung». Kandidaten = Logo-Punkte (Gruppe C, nicht ignoriert). Seite «Suche läuft …» mit «Suche 0/<n>», laufend «Suche <i>/<n> …».
- Je Partner (`qFindOne`): Kandidaten aus `allCands(Name, Währung des ersten Vertrags oder CHF, null, Website)`. Bester Kandidat = erster. «sicher», wenn score ≥ 3. Sichere sind vorausgewählt. Ohne Kandidaten landet der Name in «Nichts gefunden».
- Ergebnisseite (`paintQs`), Titel «Vorschläge» bzw. «Keine Treffer»:
  - Hinweis «Tippe auf einen Eintrag, um ihn an- oder abzuwählen. Unsichere Treffer sind nicht vorausgewählt. «Andere …» zeigt alle Vorschläge wie im Vertrag.»
  - Zeile: Auswahlpunkt, Name fett, darunter «Guter Treffer» bzw. «Unsicher» [« · Wikipedia» / «Website» / «Website-Symbol» / «Profilbild»], Vorschaubild 40×40 auf weiss (bei Ladefehler entfernt). Daneben «Andere …» → Partner-Seite mit Suche.
  - Knopf «<n> Vorschlag übernehmen» / «<n> Vorschläge übernehmen», bei 0 deaktiviert «Nichts ausgewählt».
  - «Nichts gefunden: <A, B>. Diese über die Vertragspartner-Pflege oder «Logo automatisch finden» im Vertrag ergänzen.»
  - Gar nichts: «Kein Ergebnis.»
- Übernehmen (`qApply`): je gewähltem Partner Toast «Übernehme <i>/<n> …». Logo nur laden, wenn die Gruppe noch keines hat und ein Dateispeicher existiert. Auf alle Verträge der Gruppe ohne eigenes Logo schreiben (logoBg Standard #FFFFFF). Danach Ergebnisseite schliessen, neu zeichnen, Toast «<n> Logo übernommen» / «<n> Logos übernommen» (n zählt Verträge) **[Fix N11: Partner zählen]**.

---

## 9. Verwalten: Fenster und Navigation (4212–4271)

### 9.1 Stapel
- `md.stack` = Liste von Seiten {k: Art, weitere Parameter}. Seiten: partner, pe (key), pmerge (to), holder, he (name), hs (name), henew, hassign (flt), hbulk (from, to), cat, ce (n), cenew, cdel (src), qual, qlist (g, f, title), raw (title, html).
- `openMd(k)`: Stapel = [k], Kategorien-Bearbeitungsmodus aus, Partner-Entwurf leeren, Fenster öffnen.
- `openMdAt(p)`: Stapel = [p], öffnen falls zu.
- `mdPush(p)`: offene Eingabe übernehmen, dann anhängen und einblenden. `mdPop(n=1)`: übernehmen, entfernen oder bei zu kurzem Stapel schliessen. `mdSwap(p, n=1)`: oberste n Seiten durch p ersetzen.
- `closeMd`: übernehmen, `over` entfernen, Fenster schliessen (Scrim weg, falls kein Fenster mehr offen), Stapel leeren. Wurde aus einem Vertragsdetail geöffnet und ist dieses noch offen, wird es neu gezeichnet. Ein offener Brief aktualisiert «Wer kündigt?» und den Absender.
- `mdFlush`: ist der Fokus in `peName`, `heName`, `ceName` oder einem Adressfeld `pa*`, wird der Wert gespeichert **[Fix M3: auch Absender `hs*` und `input.qein`]**.

### 9.2 Kopfzeile (`paintMd`, `mdTitle`)
- Titel je Seite: partner «Vertragspartner», holder «Inhaber», cat «Kategorien», qual «Datenqualität», hs «Absender», henew «Neuer Inhaber», cenew «Neue Kategorie», hassign «Verträge zuordnen», hbulk «Alle übertragen», pmerge «Zusammenführen», hdel «Inhaber löschen», cdel «Kategorie löschen». Sonst p.title, p.name oder p.n; bei pe der Gruppenname.
- Links «‹ <Titel der Vorseite>», bei mehr als 12 Zeichen «Zurück», auf der ersten Seite ausgeblendet. Rechts «Fertig» = `closeMd`.
- Übergänge: vorwärts hineinschieben, zurück herausschieben, beim Wechsel nach oben scrollen. Nach jedem Zeichnen Partner-Logo aktualisieren (bei pe) und die Übersicht in «Mehr» auffrischen.

### 9.3 Bausteine
- Abschnittskopf (`mdSec`): Titel links, optional Element rechts.
- Vertragszeile (`mdCRow`): Logo, Titel fett, klein «<aktueller Preis> <Währung> · <Turnus>» und « · beendet», wenn nicht `isActiveC`. Turnus: monatlich, alle 2 Monate, quartalsweise, halbjährlich, jährlich, alle 2 Jahre. Antippen schliesst Verwalten und öffnet nach 200 ms das Vertragsdetail.
- Leertext (`mdEmpty`): grauer Absatz.
- Ergebnisseite raw (`openMe`/`closeMe`): ersetzt eine oberste raw-Seite oder legt eine neue an. `closeMe` entfernt sie, wenn sie oben liegt.

### 9.4 Hilfsregeln
- `holderStats`: Personen = settings.holders, ergänzt um alle Namen auf Verträgen und Einnahmen (Reihenfolge: Liste, dann neu gefundene). Je Person Anzahl Verträge (alle, auch gekündigte) und Einnahmen.
- `mapHolders(fn)`: auf allen Verträgen und Einnahmen jeden Namen durch fn(Name) ersetzen. Leere Ergebnisse fallen weg, Duplikate werden entfernt. Nur Geänderte werden gespeichert, Rückgabe = Anzahl.
- `catCount(n)`: Verträge mit dieser Kategorie (ohne Kategorie = «Sonstiges»), alle Status.
- `perMonth(list)`: Summe Monatskosten (in Hauptwährung) der Verträge, die `isActiveC` und nicht pausiert sind.
- `cntTxt(n, eins, mehr)`: «<n> <eins|mehr>», Einzahl nur bei n = 1.

---

## 10. Verwalten: Vertragspartner (4273–4351)

### 10.1 Liste (MD_PAGES.partner)
- Suchfeld, Platzhalter «Vertragspartner suchen», filtert nach Teilstring im Namen (Gross-/Kleinschreibung egal). Die Eingabe bleibt bis zum nächsten Öffnen erhalten (`md.q`).
- Ohne Suchtext je Dubletten-Gruppe ein Hinweis: fett «Gleicher Vertragspartner?», Text ««A» und «B» sehen gleich aus.», Knopf «Zu «<Ziel>» zusammenführen». Ziel (`mergeTarget`) = meiste Verträge, dann mit Logo.
  - Knopf (Handler ausserhalb): Rückfrage Titel «Zu «<Ziel>» zusammenführen?», Text «<«A», «B»> (<n> Vertrag/Verträge) läuft/laufen danach unter «<Ziel>».», OK «Zusammenführen». Danach `mergePartners` und Toast «Zusammengeführt».
- Leer: «Kein Vertragspartner gefunden.» (mit Suche) bzw. «Noch keine Verträge mit Vertragspartner.»
- Zeile: Logo (oder Marke des ersten Vertrags), Name fett, klein «<n> Vertrag/Verträge[ · <Kosten/12> <Hauptwährung>/Mt.]» (Kosten nur bei > 0). Antippen → Partner-Seite.

### 10.2 Partner-Seite (MD_PAGES.pe, paintPeMark)
- Gruppe weg: «Dieser Vertragspartner existiert nicht mehr.»
- Entwurf `pe` je Key: key, ids, name, web, logoId/logoBg der Gruppe, Währung des ersten Vertrags **[Fix N7: immer vollständig aufbauen]**.
- Kopf: grosse Marke (Logo des Entwurfs, sonst Kategorie-Farbe/Symbol des ersten Vertrags) und Feld «Name». Speichern bei change, Enter oder Wegnavigieren.
- Abschnitt «Logo»: «Logo automatisch finden» mit Vorschlagsleiste, «Einfügen», «Hochladen» (nur mit Dateispeicher), «Google», «Bild entfernen» (nur bei vorhandenem Logo), Hinweis «Gilt für alle Verträge dieses Vertragspartners.» Jede Logo-Änderung schreibt beim nächsten Zeichnen auf alle Verträge der Gruppe, deren Logo abweicht (ohne Logo: logoBg ""). Nur bei Änderungen nach 900 ms Toast «Logo gespeichert» bzw. «Logo entfernt». Die Vertragszeilen erhalten das neue Logo sofort.
- Abschnitt «Adresse» mit rechts «Suchen». Felder (Platzhalter): «Firma, z.B. Sunrise GmbH», «Zusatz, z.B. Kundendienst oder Postfach», «Strasse und Nr.», «PLZ» | «Ort», «Land (optional)». Hinweis «Für die Kündigung per Brief. Gilt für alle Verträge dieses Vertragspartners.» Speichern und Suche: ausserhalb (paSave, setPartnerAddr).
- Abschnitt «<n> Vertrag/Verträge», rechts «<Kosten/12> <Hauptwährung>/Mt.», darunter die Vertragszeilen.
- Gibt es andere Partner: «Mit anderem Vertragspartner zusammenführen …» → Seite pmerge.

### 10.3 Umbenennen (`peRename`)
- Leerzeichen trimmen und zusammenfassen. Leer → Feld zurücksetzen, Toast «Name darf nicht leer sein». Unverändert → nichts tun.
- Neuer Name entspricht (ohne Gross-/Kleinschreibung) einem anderen Partner: Rückfrage Titel ««<anderer>» gibt es schon», Text «<n> Vertrag wird / <n> Verträge werden mit «<anderer>» zusammengeführt.», OK «Zusammenführen». Abbrechen → Feld zurücksetzen. OK → `mergePartners([alt], anderer)`, Seite durch dessen Partner-Seite ersetzen, Toast «Zusammengeführt mit «<anderer>»». **[Fix N8: Stapel prüfen, falls inzwischen wegnavigiert]**
- Sonst: partner auf allen Verträgen der Gruppe ersetzen (Adresse, Logo und Website bleiben am Vertrag), Key nachführen, Toast «Umbenannt».

### 10.4 Zusammenführen (MD_PAGES.pmerge, `mergePartners`)
- Seite: ««<Quelle>» (<n> Vertrag/Verträge) zusammenführen mit:», darunter alle anderen Partner als Auswahlliste (Logo, Name, Anzahl, Radiopunkt). Gleicher Vergleichsschlüssel steht zuerst und ist vorausgewählt, sonst alphabetisch.
- Mit Auswahl: «<n> Vertrag läuft / Verträge laufen danach unter «<Ziel>». Ein fehlendes Logo wird ergänzt.»
- Knopf «Zusammenführen» (ohne Auswahl deaktiviert). Ausführung (ausserhalb): `mergePartners`, beide Seiten durch die Ziel-Partner-Seite ersetzen, Toast «Zusammengeführt mit «<Ziel>»».
- `mergePartners(quellen, ziel)`: je Quell-Vertrag partner = Zielname, fehlende Website = Ziel-Website, fehlendes Logo = Ziel-Logo (logoBg Standard #FFFFFF). **[Fix N1: Logo, Website und Adresse in beide Richtungen angleichen und Adresse auf alle schreiben]**

---

## 11. Verwalten: Inhaber (4353–4434)

### 11.1 Liste (MD_PAGES.holder)
- Bei mindestens 2 Personen und mindestens einem Vertrag oder einer Einnahme oben die Zeile mit Gruppen-Symbol: fett «Verträge zuordnen», klein «Wer zahlt was: pro Vertrag mit einem Tipp wechseln» → Seite hassign.
- Abschnitt «Personen»: je Person Bild oder Initiale (`avHtml`), Name fett, klein «<n> Vertrag/Verträge[ · <m> Einnahme/Einnahmen]» → Personenkarte (he). Am Ende «+ Inhaber hinzufügen» → henew.
- Hinweis: «Inhaber sind die Personen in deinem Haushalt. Tippe auf eine Person für Absender, Unterschrift und Verträge.» Bei weniger als 2 Personen zusätzlich « Mit zwei oder mehr Personen kannst du Verträge gemeinsam oder getrennt zuordnen.»

### 11.2 Absender und Unterschrift (MD_PAGES.hs, `hsSave`, `openHs`)
- Daten: settings.senders[Name] = {first, last, street, zip, city, country, same?}, settings.sigs[Name] = JPEG-Data-URL.
- Text oben: «Steht oben im Kündigungsschreiben, wenn <Name> kündigt.»
- Gruppierte Felder (Platzhalter, Autofill): «Vorname» (given-name) | «Nachname» (family-name); «Strasse und Nr.» (address-line1); «PLZ» (postal-code, Ziffernblock) | «Ort» (address-level2); «Land (optional)» (country-name). Grossschreibung je Wort, Enter springt ins nächste Feld, im letzten wird gespeichert.
- Mit gültigem «gleich wie» sind nur Vor- und Nachname sichtbar, darunter die übernommene Adresse grau als «Strasse, PLZ Ort, Land».
- Chips (nur wenn es andere Personen mit eigener Adresse und ohne «gleich wie» gibt): «Eigene Adresse» und je Person «Gleich wie <X>». Tippen speichert zuerst die Felder, setzt oder entfernt dann same (Handler ausserhalb).
- Abschnitt «Unterschrift»: Bild oder «Noch keine Unterschrift». Knöpfe «Zeichnen», «Vorschläge», «Entfernen» (nur mit Unterschrift; Handler ausserhalb). **[Fix N9: Bild-URL escapen bzw. als Data validieren]**
- Hinweis: «Nur <Name> selbst sollte die Unterschrift zeichnen oder wählen. Sie bleibt auf diesem Gerät. Ohne Unterschrift bleibt im Brief eine Linie zum Unterschreiben von Hand.»
- `hsSave` (bei change bzw. Enter im letzten Feld): Werte trimmen und Leerzeichen zusammenfassen. Nur bei Änderung speichern. Brief aktualisieren, nach 300 ms Toast «Absender gespeichert» (entprellt). **[Fix M1: ungültiges same beim Speichern entfernen]**
- `openHs(Name)`: ist Verwalten offen, die Seite anhängen, sonst Verwalten mit dieser Seite öffnen. Aus dem Brief heraus über dem Brief anzeigen. **[Fix M2: muss sichtbar über dem Brief liegen]**

### 11.3 Verträge zuordnen (MD_PAGES.hassign, `hAllItems`, `hSet`)
- Einträge: alle Verträge ohne status cancelled **[Fix M5: nur laufende]** und alle Einnahmen. Verträge vor Einnahmen, jeweils nach Titel.
- Filter-Chips: «Alle», je Person ein Chip, «Ohne Inhaber[ · <n>]». Kommt die Seite von einer Personenkarte, ist die Person vorgewählt.
- Leertexte: «Alle Einträge haben einen Inhaber.» (Filter ohne Inhaber), ««<X>» ist nichts zugeordnet.» (Personenfilter), «Noch keine Verträge oder Einnahmen.»
- Zeile: Marke, Titel fett, Zusatz (Partner oder «Einnahme»). Steuerung:
  - genau 2 Personen: Segment [A | B | «Beide»]. A ist gewählt, wenn genau A zugeordnet ist, «Beide», wenn alle zugeordnet sind.
  - ab 3 Personen: Chip je Person (gewählt, wenn zugeordnet) und Chip «Alle».
- `hSet(Eintrag, Wert)`: «*» = alle Personen. Bei 2 Personen = genau diese eine. Ab 3 Personen wird die Person umgeschaltet, Reihenfolge wie in der Personenliste (alle abwählen ergibt «ohne Inhaber»). Unverändert → nichts tun. Sonst sofort speichern, neu zeichnen, Toast «<Titel> → Beide» (alle bei mehr als 1 Person), «<Titel> → A, B» oder «<Titel> → ohne Inhaber». **[Fix N5: ab 3 «Alle»; Fix N6: bei Einnahmen nur eine Person]**
- Unten: «Alle Einträge einer Person übertragen …» → hbulk.

### 11.4 Alle übertragen (MD_PAGES.hbulk)
- Abschnitt «Von»: alle Personen als Auswahlliste (Bild, Name, Anzahl). Vorauswahl = erste Person. Wechsel von «Von» hebt ein gleiches «An» auf.
- Abschnitt «An»: alle ausser «Von».
- Hinweis mit Auswahl: «<n> Eintrag geht / Einträge gehen von «<Von>» an «<An>». Gemeinsame Einträge bleiben gemeinsam. «<Von>» bleibt als Person bestehen.» n zählt alle Verträge (auch gekündigte) und Einnahmen von «Von». Ohne Auswahl: «Zum Beispiel nach einem Umzug oder wenn jemand die Verträge übernimmt.»
- Knopf «Übertragen», deaktiviert ohne «An» oder bei n = 0. Ausführung (ausserhalb): `mapHolders(Von → An)`, zurück, Toast «<n> Eintrag/Einträge an «<An>» übertragen». Achtung: aus [Von, An] wird [An] **[Fix M7]**. Absender, Unterschrift und Bild von «Von» bleiben unverändert.

---

## 12. Hinweise für SwiftUI
- Verwalten = NavigationStack im Sheet, Seiten als Enum. Autosave über `onChange`/`onSubmit` und zusätzlich beim Verlassen (`onDisappear`) für alle Felder (vermeidet M3).
- Person als Entität mit UUID (heute dient der Name als Schlüssel in holders, senders, sigs, avatars, qIgn). Adresse «gleich wie» als Referenz auf eine Adress-Entität statt Kette.
- Partner als Entität (Name, Web, Logo, Adresse). Zusammenführen = Verträge umhängen und Felder vereinigen.
- Datenqualität als reine Funktion `qualItems(state) -> [Issue]` mit stabilen Schlüsseln, Ignorieren als Set<String>. Vor dem Nachbau die Regeln aus 7.2 mit den Fixes M5, N2 und N4 festlegen.
- Kündigungs-Rückfrage über `scenePhase` und einen Merker {id, trial}.
- Tote Handler (#reviewCard, #hFlag, data-fsheet, data-sortpick, data-sort) nicht übernehmen.
