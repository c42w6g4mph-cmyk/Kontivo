# Portierungs-Inventar R2: index.html Z. 2298–3009

Bereiche: Kosten (Rest von renderStat), Kopf/Navigation, Einnahmen-Fenster, Leere Seiten, Budget, Formular-Hilfen, Vertragsformular, Anbieterkatalog.
Texte in «» sind wörtlich. JS-Funktionsnamen stehen in Klammern. Formatierung: `money(v)` = de-CH mit 2 Nachkommastellen (1’284.50). `nf0` = de-CH ohne Nachkommastellen. `fmtD` = «3. Oktober 2026». `fmtShort` = «03.10.26». MON = volle Monatsnamen, MS = «Jan, Feb, Mär, Apr, Mai, Jun, Jul, Aug, Sep, Okt, Nov, Dez». H = Hauptwährung (`settings.home`).
Zum Speichern: Das Formular speichert in Z. 3025ff, knapp ausserhalb des Abschnitts. Es ist hier trotzdem vollständig beschrieben, weil es zum Formular gehört.

---

## 1. Kosten-Tab, zweite Hälfte (renderStat ab Z. 2298)

**Eingaben aus der ersten Hälfte (Z. 2256–2297):**
- `months[12] = {sum, paid, open, items[]}`. Jedes Item hat `{c, d (Datum), v (Betrag in H × Anteil), a (Betrag in Vertragswährung × Anteil), sh (Anteil), ex (Sonderzahlung oder null)}`.
- `paid` = Zahlungen mit d < heute, `open` = d ≥ heute.
- Anteil `sh` = `holderShare(c)`: 1 ohne Personenfilter, sonst 1/Anzahl Inhaber (0, wenn die Person nicht Inhaber ist).
- `gY` (Jahr) und `gM[m]` (Monat) sind Summen je Gruppenschlüssel (Kategorie oder Vertragspartner). Sie nutzen alle Filter **ausser** der Gruppierungsdimension (`fltMatch(c,G)`).
- `tot` = Jahressumme, `avg = tot/12`, `sel` = gewählter Monat (0–11), `chartH` = Balkendiagramm.

### 1.1 Vorjahresmonat (Z. 2301–2321)
- `pmS` = Summe aller Zahlungen im selben Monat des Vorjahrs (gefilterte Verträge × Anteil, in H).
- Die Anzeige entfällt, wenn ein Item des gewählten Monats keinen Vertragsbeginn (`start`) hat, oder wenn `pmS < 0.005`.
- Die Differenz `pmD = sum − pmS` wird auf ganze Einheiten gerundet (`pr`):
  - `pr < 1` → «gleich wie {Monat} {Jahr−1}» (ohne Farbe, Pfeil trotzdem, siehe F15)
  - sonst «{pr nf0} {H} mehr als {Monat} {Jahr−1}» (Klasse up, Pfeil «↑») bzw. «… weniger als …» (down, «↓»)

### 1.2 Monatskarte (Z. 2322–2333)
- **Kopf:** links «{Monat} {Jahr}», rechts das Filterlabel (aktive Filter mit « · » verbunden, nur wenn Filter aktiv).
- **Grosse Zahl:** `money(sum)`, die Nachkommastellen kleiner (`<small>`), dahinter H. Darunter die Vorjahreszeile (1.1).
- **Zeile Bezahlt/Offen:**
  - Ohne Zahlung im Monat: «In diesem Monat ist nichts fällig.»
  - Sonst links «Bezahlt» mit Punkt (Teal), dahinter «✓», wenn Offen < 0.005, und `money(paid)`. Rechts «Offen» mit Punkt (Ink) und `money(open)`.
  - Ein Wert < 0.005 wird blass (Klasse nil).
- **Diagramm:** `chartH`.
- **Fuss:** links «Ø pro Monat» `nf0(avg)`, rechts «Total {Jahr}» `nf0(tot)`.
- **Danach** ggf. der Hinweis (nur bei Vorjahren und Verträgen ohne Beginn): «{n} Vertrag hat / {n} Verträge haben keinen Vertragsbeginn und wird/werden deshalb rückwirkend voll gezählt.»

### 1.3 Liste «Fällig im {Monat}» (Z. 2310–2316, 2334–2338)
- **Sortierknopf:** nur bei mehr als 1 Zahlung, Segment «Datum | Betrag» (`state.mSort` = "date"|"amt", Standard Datum, aria «Sortierung»).
- **Aufteilung:** offen = d ≥ heute, bezahlt = d < heute. Nach Datum aufsteigend, bei «Betrag» beide Listen nach `v` absteigend.
- **Anzeige:**
  - Zuerst alle offenen Zahlungen.
  - Gibt es offene **und** bezahlte, folgt die Falte «Bereits bezahlt ({n})» (`state.showPaid`, Standard zu).
  - Bezahlte Zahlungen erscheinen, wenn die Falte offen ist oder es keine offenen gibt.
  - Leer: «In diesem Monat ist nichts fällig.»
- **Zeile (`mrow`):** Logo/Mark, Titel (Bezeichnung, sonst Vertragspartner).
  - **Zweitzeile:** [«Anteil {n} %» bei Anteil < 1, Vertragspartner (nur wenn ≠ Bezeichnung), «Sonderzahlung»/«Gutschrift» + « · Notiz»], verbunden mit « · ».
  - **Rechts:** Betrag in Vertragswährung (Gutschrift als «−{Betrag}»), die Währung als kleiner Zusatz.
  - **Status rechts unten:**
    - vergangen: «am {dd.mm.yy}»
    - heute: «heute fällig» (neutral)
    - 1–7 Tage: «in 1 Tag» / «in {n} Tagen» (Warnfarbe)
    - später: «fällig {dd.mm.yy}»
  - Vergangene Zeilen blass (Klasse past). Tippen öffnet das Vertragsdetail (`data-open`).

### 1.4 Aufteilung (Z. 2339–2386)
- **Überschrift:** «Aufteilung {Monat Jahr}» (Zeitraum Monat) bzw. «Aufteilung {Jahr}».
- **Segmente:**
  - Zeitraum «Jahr | {MS}» (`state.ss` = "year"|"month", Standard Jahr, aria «Zeitraum»)
  - Gruppierung «Kategorie | Vertragspartner» (`state.sg` = "cat"|"partner", Standard Kategorie, aria «Aufteilen nach»)
  - Ein Wechsel setzt `state.sgAll=false`.
- **Schlüssel:** Werte > 0.004, nach Betrag absteigend. Prozent = Wert / Summe der gezeigten Schlüssel.
- **Leer:** «Im {Monat} ist nichts fällig.» (derselbe Text auch im Jahresmodus)
- **Ring (SVG 132×132, R=52, Start oben):**
  - Bei ≤ 5 Schlüsseln alle, sonst die Top 4 plus «Übrige» (grau #9AA0A6).
  - Lücke 2.2 zwischen Segmenten (nur bei > 1 Segment), Mindestlänge 0.6.
  - Farben: bei Kategorie die Kategoriefarbe. Bei Vertragspartner die Palette [#0E5A5E, #8A6A1F, #1F4E8C, #6B4E9E, #A93227, #2E6A4E, #B0562A, #3F4A55] nach Rang.
- **Auswahl (`state.ringSel`):**
  - Tippen auf einen Legendeneintrag wählt ihn aus bzw. ab (Scrollposition bleibt).
  - Andere Segmente werden dann blass (dim), das gewählte hervorgehoben (on).
  - Die Mitte zeigt den gewählten Namen und Betrag, sonst «Total {Jahr}» bzw. «Total {MS}».
  - Ist der gewählte Schlüssel im aktuellen Zeitraum nicht vorhanden, gilt keine Auswahl.
- **Beträge:** Jahr mit `nf0`, Monat mit `money`.
- **Legende:** je Segment Farbpunkt, Name, «{Betrag} {H} · {n} %». Der Eintrag «Übrige» hat «▾/▴» und klappt die Restliste auf (`state.sgAll`, aria-expanded). Die Restliste hat Zeilen im gleichen Format mit grauem Punkt, ebenfalls auswählbar.

### 1.5 SwiftUI-Hinweise
- Ring: `Chart` mit `SectorMark`.
- Segmente: `Picker(.segmented)`.
- Liste: `DisclosureGroup` für «Bereits bezahlt».

---

## 2. Kopf, Tabs, Jahresnavigation (Z. 2387–2423)
- **Titel je Tab (`TITLES`):** list «Verträge», stat «Kosten», budget «Budget», term «Fristen», arch «Archiv», set «Mehr».
- **`goTab(t)`:** setzt `state.tab`, zeichnet neu, aktualisiert Plus-Knopf und Kopf, scrollt nach oben.
- **`paintFab`:**
  - Plus-Knopf (Klasse `hasplus`) nur im Tab Verträge.
  - Hero und Suchfeld nur im Tab Verträge **und** wenn mindestens ein Vertrag existiert.
  - Tab «Mehr»: #view aus, #setPage an. Beim ersten Einblenden wird `fillSettings()` aufgerufen.
  - Seitentitel aus TITLES. Ausserhalb von Kosten/Budget wird die Jahresnavigation entfernt. Die Tabbar markiert den aktiven Tab (aria-selected).
- **`setTopYear(Y, nowY)`:**
  - `Y==null` → Navigation leer und versteckt.
  - Sonst «‹ {Jahr} ›» mit aria «Vorjahr» bzw. «Folgejahr». «›» ist deaktiviert ab `Y ≥ aktuelles Jahr + 5`, nach hinten gibt es keine Grenze.
- **Klick (Z. 2418):** Jahr ±1. Gewählter Monat = aktueller Monat, wenn das Zieljahr das aktuelle Jahr ist, sonst Januar. Danach Neuzeichnen.
- **`updMini`:** kleine Titelleiste (#miniBar). Text «{Titel}» bzw. «{Titel} · {Jahr}», wenn die Jahresnavigation sichtbar ist. Sichtbar, sobald die Unterkante von #topHead < 8 px liegt (beim Scrollen). Tippen scrollt sanft nach oben.
- **SwiftUI:** `navigationTitle` + Toolbar mit Jahrespfeilen; Mini-Titel = Inline-Titel beim Scrollen (Standard).

---

## 3. Einnahmen: Konstanten und Fenster «Alle Einnahmen» (Z. 2424–2438)
- **INC_CATS (fest, nicht verwaltbar):** Lohn, Nebeneinkommen, Bonus, Kapitalerträge, Vermietung, Rente, Sonstiges.
- **ICYCLE:** 0 «einmalig», 1 «monatlich», 2 «alle 2 Monate», 3 «quartalsweise», 6 «halbjährlich», 12 «jährlich», 24 «alle 2 Jahre».
- **`incList()`:** alle Einnahmen als Kopie mit `_id`.
- **`incMark(c)`:** Mark wie bei Verträgen (Vertragspartner = name).
- **`openIncAll()`:**
  - Fenster sheetPick, Titel «Alle Einnahmen», Modus `incall`.
  - Alle Einnahmen nach aktuellem Betrag (in H umgerechnet) absteigend.
  - **Zeile:** Mark, Bezeichnung (sonst Name, sonst «Einnahme»), Zweitzeile:
    - «beendet», wenn das Ende vor heute liegt
    - «ab {dd.mm.yy}», wenn der Beginn nach heute liegt
    - sonst der Turnus aus ICYCLE (unbekannt → «monatlich»)
    - Beendete und künftige Einnahmen blass (off).
  - **Rechts:** aktueller Betrag; die Währung nur, wenn sie ≠ H ist.
  - **Unten:** Knopf «Einnahme erfassen».
  - **Tippen** auf eine Zeile oder den Knopf: Fenster schliessen, nach 180 ms Einnahme-Formular öffnen (bestehend bzw. neu). Der Handler liegt in Z. 3928.
- **SwiftUI:** Sheet mit List; Turnus als Enum.

---

## 4. Leere Seiten (Z. 2439–2483)

### 4.1 Muster `emptyHero({icon, title, text, hooks, preview, illu, btn, sub})`
- Aufbau: Symbol (SVG 24×24, Strich), Titel (zweizeilig, Umbruch fest), ein Satz, bis zu 3 Punkte mit Häkchen, optional die Vorschau-Karte, Knopf, optional Zusatz unten.
- Punkte: einzeilig (nowrap), 15 px, bei Breite ≤ 374 px 14 px.
- Die Vorschau mit `illu` ist nicht klickbar, hat 90 % Deckkraft und ist bei Höhe ≤ 700 px ausgeblendet.
- Regel: Die Seite passt ohne Scrollen auf ein iPhone 393×852.
- Symbole (ES_ICON): list = Dokument, stat = 4 Balken, budget = Geldbörse, term = Stoppuhr.

### 4.2 Verträge (`emptyList`)
- **Bedingung:** keine Verträge überhaupt, keine Suche (Z. 2029).
- **Titel:** «Jeden Vertrag im Griff.» / «Jede Frist im Blick.»
- **Satz:** «Erfasse einen Vertrag, den Rest übernimmt Kontivo.»
- **Punkte:**
  - «Nie wieder ein Jahr zu viel bezahlen»
  - «Kein Vertrag verlängert sich mehr ungewollt»
  - «Kündigungsschreiben in einer Minute»
- **Knopf:** «Ersten Vertrag erfassen» → neues Vertragsformular.
- **Zusatz:**
  - Schild-Symbol + «Ohne Bankanbindung. Deine Daten bleiben auf deinem Gerät.»
  - Link «Ich habe ein Backup» → Tab «Mehr» und Dateiauswahl für das Backup (`bkLoad`).

### 4.3 Kosten (`emptyStat`)
- **Bedingung:** keine Zahlungen im Jahr **und** keine Verträge (Z. 2282). Die Jahresnavigation wird ausgeblendet.
- **Titel:** «Dein Monat,» / «im Voraus geplant»
- **Satz:** «Sobald Verträge da sind, siehst du hier, was wann abgebucht wird.»
- **Punkte:**
  - «Was geht nächsten Monat wirklich weg?»
  - «Jahresrechnungen, bevor sie dich treffen»
  - «Teurer als letztes Jahr? Sofort sichtbar»
- **Knopf:** «Ersten Vertrag erfassen».
- (Mit Verträgen, aber ohne Zahlungen im Jahr: «Keine Zahlungen in {Jahr}» + «Für dieses Jahr sind keine Zahlungen erfasst oder berechenbar.», Z. 2283.)

### 4.4 Fristen (`emptyTerm`)
- **Bedingung:** die Fristen-Seite hat sonst keinen Inhalt (Z. 2124), praktisch ohne aktive Verträge.
- **Titel:** «Nie mehr eine» / «Frist verpassen»
- **Satz:** «Kontivo rechnet den Kündigungstermin aus und meldet sich rechtzeitig.»
- **Punkte:**
  - «Behalten oder kündigen? Du entscheidest»
  - «Kündigung als PDF: mailen oder drucken»
  - «Auch Probe-Abos und Jahresverträge»
- **Illustration** (illu):
  - Kopf «Als Nächstes».
  - Zeile mit Kategorie-Symbol «Freizeit & Sport» (Farbe aus catColor), «Fitnessstudio», klein darunter in Warnfarbe «Frist 30.11. · noch 29 Tage».
  - Zwei Schein-Knöpfe «Behalten» und «Kündigen».
- **Knopf:** «Ersten Vertrag erfassen».

### 4.5 Budget (`budgetEmpty`)
- **Bedingung:** keine Einnahmen und kein Personenfilter.
- **Titel:** «Weisst du, was dir» / «jeden Monat bleibt?»
- **Satz:**
  - Mit laufenden, bereits begonnenen Verträgen (`running()` ohne `notStarted`): «Deine Fixkosten sind schon da: {money(Summe monthlyCost)} {H} im Monat. Es fehlt nur dein Lohn.»
  - Sonst: «Trag deinen Lohn ein, die Fixkosten kommen aus deinen Verträgen.»
- **Punkte:**
  - «Lohn rein, Fixkosten raus: der Rest gehört dir»
  - «Was bleibt dir übrig? Sofort sichtbar»
  - «Fair geteilt: wer zahlt wie viel im Haushalt»
- **Knopf:** «Einnahme erfassen» (id incAdd) → neue Einnahme.

### 4.6 SwiftUI
`ContentUnavailableView` mit eigenem `description` (Satz + `Label`-Liste mit Häkchen) und `actions`.

---

## 5. Budget-Tab (renderBudget, Z. 2484–2579)

### 5.1 Daten
- **Jahr Y:** `state.year` oder das aktuelle Jahr.
- **12 Monate:** {inc, fix, free = inc − fix}.
- **Personen (HL):** `settings.holders` ∪ Inhaber aller Verträge ∪ Inhaber aller Einnahmen.
- **Personenfilter BH:** `state.bHolder`, nur gültig, wenn die Person in HL vorkommt.
- **Anteil `shr(c)`:** ohne Filter 1; ist BH kein Inhaber, 0; sonst 1/Anzahl Inhaber.
- **inc:** Termine (`occurrences`) jeder Einnahme im Jahr × `priceAt` × Kurs × Anteil.
- **fix:** `payments` (Termine + Sonderzahlungen) jedes Vertrags × Kurs × Anteil, im Monat des Datums.

### 5.2 Personenfilter (oben)
- **Chips:** wenn die Namen passen (`holderNamer(HL, 361)`: 2–4 Personen, Namen ggf. auf Vorname bzw. «Vorname N.» gekürzt). Reihe «Alle | Name …», ein Tipp setzt den Filter.
- **Keine Zeile:** bei ≤ 1 Person.
- **Sonst Auswahlknopf:** «Inhaber» bzw. der gewählte Name, dazu «×» (aria «Filter zurücksetzen»). Er öffnet die Auswahl (Z. 3855): Titel «Inhaber», «Alle Inhaber», Namen, Hinweis «Gemeinsame Verträge und Einnahmen zählen anteilig.»

### 5.3 Inhaltszustände
1. **Filter aktiv, keine Einnahmen dieser Person:** «Keine Einnahmen für {Name}» + «Weise einer Einnahme diese Person als Empfänger zu, dann erscheint hier ihr Budget.», darunter Knopf «+ Einnahme erfassen».
2. **Keine Einnahmen:** Leerseite 4.5.
3. **Sonst:** Jahresnavigation und Karte (5.4) sowie die Listen 5.5 und 5.6.

### 5.4 Karte «Verfügbar»
- **Kopf:** «{Monat} {Jahr}», rechts der gekürzte Filtername.
- **Grosse Zahl:** `free` des Monats mit «−» bei negativem Wert (Klasse neg), Nachkommastellen klein, H.
- **Zeile darunter:** «verfügbar nach Fixkosten», plus « · {round(free/inc×100)} % der Einnahmen», wenn Einnahmen > 0 und der Prozentwert > 0.
- **Vorjahresmonat:**
  - Einnahmen und Fixkosten des Vorjahresmonats mit derselben Regel. Nur, wenn dort Einnahmen oder Fixkosten > 0.005.
  - Differenz gerundet: < 1 → «gleich wie {Monat} {Jahr−1}», sonst «{n} {H} mehr/weniger als {Monat} {Jahr−1}».
  - **Farbe invers:** mehr verfügbar = Klasse down (grün), weniger = up.
- **Zeile:** «Einnahmen» `money(inc)` | «Fixkosten» `money(fix)` (blass, wenn < 0.005).
- **Diagramm «Verfügbar pro Monat»:**
  - Nulllinie bei `zp = −min/(max−min)·100 %`, wobei min ≤ 0 ≤ max.
  - Balken je Monat, Höhe `|free|/Spanne`, mindestens 0.8 %, wenn ≠ 0. Positive Werte stehen auf der Nulllinie, negative hängen darunter (Klasse neg).
  - Vergangene Monate und der laufende Monat kräftig (bp), künftige blass (bo).
  - Ø-Linie (Jahresverfügbar/12), wenn |Ø| > 0.005.
  - Monatslabels MS, gewählter Monat (on), aktueller Monat (now).
  - Legende «Defizit», wenn ein Monat negativ ist.
  - Balken-aria «{Monat}: {money} {H}». Tippen wählt den Monat (`state.sel`).
- **Fuss:** «Ø pro Monat» (nf0, mit «−» und rot bei negativem Wert) | «Verfügbar {Jahr}» (dito).

### 5.5 «Einnahmen {Monat}»
- **Kopf:** rechts `money(inc des Monats)` H.
- **Zeilen:** Einnahmen mit mindestens einem Termin im Monat, Betrag = Summe `priceAt` in Einnahmewährung (ohne Anteil, siehe F16), absteigend nach umgerechnetem Betrag.
- **Zeile:** Mark, Bezeichnung (sonst Name, sonst «Einnahme»), Betrag; die Währung nur, wenn sie ≠ H ist. Tippen öffnet die Einnahme.
- **Leer:** «Keine Einnahmen im {Monat}».
- **Fuss:** «+ Einnahme» (neue Einnahme) | «Alle Einnahmen ({n}) ›» (Fenster 3). n = Einnahmen mit Anteil > 0.

### 5.6 «Ausgaben {Monat}»
- **Kopf:** rechts Summe in H.
- **Zeilen:** jede Zahlung (Termin oder Sonderzahlung) im Monat mit Anteil > 0, Betrag in H × Anteil, absteigend nach Betrag.
- **Zeile:**
  - Mark, Titel.
  - Zweitzeile [Vertragspartner ≠ Bezeichnung, «Anteil {n} %», «Sonderzahlung/Gutschrift · Notiz»].
  - Rechts der Betrag (ohne Währung) und darunter die Kategorie («Sonstiges», wenn leer). Tippen öffnet das Vertragsdetail.
- **Begrenzung:**
  - Die grössten 5 werden gezeigt. Bei ≤ 6 Einträgen alle.
  - Ab 7 der Knopf «Alle {n} anzeigen» / «Nur die grössten 5» (`state._xAll`, gilt für alle Monate).
- **Leer:** «Keine Ausgaben im {Monat}».
- **Summenblock:** «Einnahmen» {inc} / «− Ausgaben» {fix} / «= Verfügbar» {free} {H}.

### 5.7 SwiftUI
- Diagramm: `Chart` mit `BarMark` (yStart/yEnd), `RuleMark` für Ø und Null.
- Filter: `Picker(.segmented)` bzw. `Menu`.

---

## 6. Sheets und Auswahl-Hilfen (Z. 2582–2650)
- **`openSheet(el)`:** Abdunklung an, Sheet an, nach oben gescrollt.
- **`closeSheets()`:** schliesst Abdunklung und alle Sheets (Form, Detail, Crop, Inc, Pick, Md, Letter, Sig, SigPick) und leert #csvOut.
- **Überlagerte Auswahl:** sheetPick mit Klasse `over` liegt über einem anderen Sheet, ohne eigene Abdunklung. `closePick()` entfernt `on` und `over`.
- **`#xAll`** (globaler Klick-Handler): schaltet `state._xAll` um.
- **`buildCatChips`:** #fCats öffnet die Kategorieauswahl für Verträge, #iCats die für Einnahmen.
- **`paintCatField(pre, cat)`:** Symbol mit Kategoriefarbe und Name. Leer: grauer Hintergrund, «Kategorie wählen» (Platzhalterstil).
- **`openCatPick(kind)`** (überlagert, Titel «Kategorie»):
  - Liste = `allCats()` (Verträge, benutzerdefinierte Reihenfolge) bzw. INC_CATS (Einnahmen). Je Eintrag Farbsymbol und Name, aria-pressed für den aktuellen.
  - Nur bei Verträgen unten das Feld «Eigene Kategorie, z.B. Haustier» (max. 30 Zeichen) und der Knopf «Hinzufügen». Enter im Feld wirkt wie der Knopf.
  - Tippen auf eine Kategorie setzt `draft.cat` bzw. `idraft.cat` und schliesst die Auswahl.
- **`addCustomCat`:**
  - Der Name wird getrimmt, Mehrfach-Leerzeichen werden zu einem. Leer: nichts passiert.
  - Existiert der Name schon (Gross/Klein egal), wird die vorhandene Kategorie gewählt.
  - Sonst wird eine neue angelegt: Farbe `COLORS[(Anzahl+3) % 8]`, Symbol «tag». Sie wird sofort gespeichert, auch wenn das Formular danach abgebrochen wird.
  - Toast «Kategorie gewählt» bzw. «Kategorie «{Name}» angelegt».
- **`openPausePick(id)`** (überlagert, Titel «Pausieren für»):
  - Optionen «1 Monat», «3 Monate», «6 Monate» (rechts «bis {fmtD(heute + n Monate)}») und «Ohne Enddatum» (rechts «bis du fortsetzt»).
  - Darunter «Oder bis zu einem Datum», Datumsfeld und Knopf «Pausieren». Hinweis «Danach läuft der Vertrag automatisch weiter. Zahlungen während der Pause zählen nicht in die Summen.»
  - **Validierung** (Z. 3932): das Datum muss nach heute liegen, sonst Toast «Bitte ein Datum in der Zukunft wählen».
- **`applyPause(id, until)`:**
  - Setzt `paused=true`, `pausedAt=heute`, `pausedUntil=until` oder "". Schliesst alles.
  - Toast «Pausiert bis {fmtD}» bzw. «Pausiert — bis du fortsetzt».
  - Wirkung: Zahlungstermine d mit pausedAt ≤ d < pausedUntil (ohne Ende: alle ab pausedAt) entfallen. `isPaused` = paused und (kein Ende oder heute < Ende). Siehe F4.
- **Farbwahl (`buildSwatches`/`paintSwatches`/`rgbEq`):**
  - Knopf «A» (aria «Farbe der Kategorie», Hintergrund = Kategoriefarbe) bedeutet `draft.color=""`.
  - Dazu 8 Farben: #0E5A5E, #A93227, #1F4E8C, #6B4E9E, #8A6A1F, #2E6A4E, #B0562A, #3F4A55.
  - Der aktive Knopf hat aria-pressed. Jede Wahl aktualisiert das Logo.
- **`clearCands`:** leert die Logo-Kandidaten von Vertrag und Einnahme.

---

## 7. Vertragsformular (#sheetForm)

### 7.1 Entwurf `draft` (nicht im DOM)
| Feld | Bedeutung | Start beim Öffnen (`openForm`) |
|---|---|---|
| cat | Kategorie | c.cat oder "" |
| color | Farbe ohne Logo | c.color oder "" |
| logoId, logoBg | Logo (Blob-ID) und Hintergrund | aus c oder "" |
| docs[] | Dokumente {id, name, type} | Kopie von c.docs; beim Duplizieren leer |
| extras[] | Sonderzahlungen {date, amount, note} | `extrasOf(c)`; beim Duplizieren leer |
| prices[] | Preisänderungen {from, amount} | Kopie von c.prices (auch beim Duplizieren) |
| holders[] | Inhaber | bestehend: c.holders. Neu: `settings.lastHolders` (nur noch existierende Personen), sonst [erster Inhaber] |
| tplHint | Name der übernommenen Vorlage | "" |
| stdTpl, stdDone | Vorschlag «übliche Frist» aus dem Internet-Treffer | undefiniert |
Dazu globale Werte: `editId` (null bei neu und beim Duplizieren), `termMode` ("open"/"fixed"), `xKind` ("pay"/"cr").

### 7.2 Öffnen `openForm(c, asCopy)`
- **Aufrufer:**
  - neu: Plus-Knopf, Leerseiten, Onboarding
  - bearbeiten: Detail «Bearbeiten», Datenqualität, fehlender Kündigungslink bzw. fehlende E-Mail (dann direkt «Weitere Angaben»)
  - duplizieren: Detail «Duplizieren»
  - Wechsel eines Pflichtvertrags: `markCancelled` mit Kopie, Titel danach «Neuer Anbieter»
- **Titel:** «Duplizieren» (asCopy), «Bearbeiten» (c) bzw. «Neuer Vertrag». Er wird in `dataset.t` gemerkt.
- **Felder** werden mit den Werten aus 7.4 vorbelegt. Danach wird zurückgesetzt bzw. neu gezeichnet:
  - Preis- und Sonderzahlungs-Eingabe geleert, Art = Zahlung
  - Kündigungsmodus: «Feste Laufzeit», wenn c.end oder c.renew gesetzt ist, sonst «Jederzeit kündbar»
  - Logo-Panel zu, Vorlage-Hinweis leer, Vorschläge versteckt
  - Kategorie, Farben, Logo, Dokumente und Inhaber neu gezeichnet
  - «Hochladen» (Logo und Dokument) versteckt, wenn kein Dateispeicher (`assets`) vorhanden ist
- **Ende:** Hauptseite zeigen und Sheet öffnen.

### 7.3 Seiten (`formPage(more)`)
- **Hauptseite #fMain:** Kopf «Abbrechen | {Titel} | Sichern».
- **Unterseite #fMore:** Kopf «Zurück | Weitere Angaben | Sichern», kurze Einblend-Animation, nach oben gescrollt.
- **«Abbrechen»:** Auf der Unterseite führt es zurück, auf der Hauptseite schliesst es ohne Rückfrage. Auch ein Tipp auf die Abdunklung schliesst ohne Rückfrage (F18).
- **Zeile «Weitere Angaben ›»** mit Zusammenfassung #fMoreN (`paintOptCounts`):
  - Teile in dieser Reihenfolge, mit « · » verbunden:
    - «{n} Preisänderung(en)», «{n} Sonderzahlung(en)»
    - «Pflichtvertrag» bzw. «nicht in Fristen»
    - «Kündigungsweg», «Kündigungslink», «Probeabo»
    - «Kundennummer», «Vertragsnummer», «Zahlungsart», «Belastet über»
    - «Adresse», «Website», «Telefon», «E-Mail», «Notiz», «{n} Datei(en)»
  - Ohne Angaben: «Preisänderungen, Sonderzahlungen, Kundennummer, Kontakt, Dateien …» (Klasse on nur mit Angaben).
  - Wird bei jeder Eingabe auf der Unterseite aktualisiert.
- **Zähler hinter den Abschnittstiteln:** «{n} erfasst» (Sonderzahlungen), «{n} Änderung(en)» (Preise), «{n} Datei(en)» (Dokumente).

### 7.4 Felder der Hauptseite
| ID | Label / Platzhalter | Typ | Pflicht | Standard (neu) | Vorbelegung (bestehend) | Speichern als |
|---|---|---|---|---|---|---|
| logoTap / logoPrev | «Logo» (aria «Logo und Farbe ändern») | Knopf + Vorschau | – | Farbe + Kategoriesymbol | Logo | – (klappt #oLogo) |
| oLogo | «Logo & Farbe»: «Logo automatisch finden», «Einfügen», «Hochladen», «Google», logoAll, «Bild entfernen», «Farbe, wenn kein Bild», Farben | details | – | zu | zu | logoId, logoBg, color |
| fLabel | «Bezeichnung» / «z.B. Handy-Abo» | Text | ja, wenn fPartner leer | "" | c.label | label (getrimmt) |
| fPartner | «Vertragspartner» / «z.B. Swisscom», Katalog-Knopf im Feld (aria «Aus Katalog wählen») | Text | ja, wenn fLabel leer | "" | c.partner | partner (getrimmt) |
| fCats | «Kategorie», Wert «Kategorie wählen» | Auswahl-Zeile | **ja** | "" | c.cat | cat (Rückfall «Sonstiges», praktisch nie) |
| fHolders (in fHoldWrap) | «Inhaber — mehrere möglich» | Chips, Mehrfachwahl | nein | siehe 7.1 | c.holders | holders[] |
| fAmt (Label fAmtL) | «Betrag» bzw. «Anfangspreis», wenn Preisänderungen existieren / «59.90» | Text, decimal | **ja**, ≥ 0 | "" | c.amount mit 2 Stellen | amount (auf 0.01 gerundet) |
| fCur | «Währung»: CHF, EUR, USD, GBP, TRY | Select | – | settings.home | c.cur | cur |
| fCycle | «Turnus»: 1 «monatlich», 2 «alle 2 Monate», 3 «quartalsweise», 6 «halbjährlich», 12 «jährlich», 24 «alle 2 Jahre» | Select | – | 1 | c.cycle | cycle (Zahl) |
| fDue | «Nächste Zahlung am» (fachlich: Stichtag, ab dem alle Termine gerechnet werden) | Datum | – | heute | c.due | due (leer → heute) |
| termSeg | «Jederzeit kündbar» (open) / «Feste Laufzeit» (fixed) | Segment | – | open | fixed, wenn end oder renew | steuert end/renew/cancTerm |
| fStart | «Vertragsbeginn» | Datum | – | "" | c.start | start |
| fEnd (.tmfixed) | «Vertragsende» | Datum | – | "" | c.end | end, nur im Modus fixed, sonst "" |
| fNotice | «Kündigungsfrist» / «–» | Text, numeric | – | "" | c.notice | notice = Zahl oder 0 |
| fNoticeU | m «Monate», w «Wochen», d «Tage», k «. im Monat» | Select | – | m | c.noticeU | noticeU |
| fTermP (.tmopen) | «Kündbar per»: "" «jederzeit», p «Ende Periode», m «Monatsende», q «Quartalsende», h «Halbjahresende», y «Jahresende», a «Ende Vertragsjahr» | Select | – | "" | c.cancTerm | cancTerm, nur im Modus open, sonst "" |
| fRenew (.tmfixed) | «Verlängert sich um»: "" «— nicht automatisch», 1 «1 Monat», 3, 6, 12, 24 «n Monate» | Select | – | "" | c.renew | renew (String), nur im Modus fixed |
| tmHint | Hinweistext (7.7) | Text | – | – | – | – |
**Sichtbarkeit:** `.tmfixed` (Vertragsende, Verlängerung) nur im Modus fixed, `.tmopen` (Kündbar per) nur im Modus open. fHoldWrap nur bei mindestens 2 Personen (settings.holders ∪ draft.holders). Werte bleiben beim Moduswechsel im Feld, gespeichert wird nur der Teil des aktiven Modus.

### 7.5 Felder der Unterseite «Weitere Angaben»
| Abschnitt | ID | Label / Platzhalter | Typ | Standard | Speichern als |
|---|---|---|---|---|---|
| Preisänderungen | pList, pFrom «Gültig ab», pAmt «Neuer Betrag» / «74.90», pAdd «Preisänderung hinzufügen» | Liste + Datum + decimal | leer | prices[] |
| | Hinweis | «Der Betrag unter «Kosten» ist der Anfangspreis. Jede Änderung gilt ab ihrem Datum.» | | | |
| Sonderzahlungen | xList, xKind «Zahlung | Gutschrift», xDate «Datum», xAmt «Betrag» / «120.00», xNote «Bezeichnung (optional)» / «z.B. Nebenkostenabrechnung» (max. 60), xAdd «Sonderzahlung hinzufügen» | Liste + Segment + Felder | Zahlung | extras[] |
| | Hinweis | «Zum Beispiel Nebenkostenabrechnung oder Aktivierungsgebühr. Zählt in «Kosten» und «Budget» im jeweiligen Monat, nicht in den monatlichen Fixkosten.» | | | |
| Fristen | fWatch «In «Fristen» anzeigen»: "" «Ja», mand «Nein – Pflichtvertrag», nowatch «Nein – z.B. Miete»; Hinweis «Pflichtvertrag: nur Wechsel möglich, z.B. Grundversicherung.» | Select | Ja | mand, noWatch über die versteckten Checkboxen fMand/fNoWatch |
| | fCancF «Kündigungsweg»: "" «—», «Online / Kundenkonto», «E-Mail», «Brief», «Einschreiben» | Select (Wert = Anzeigetext) | — | cancF |
| | fTrial «Probeabo endet» | Datum | "" | trial |
| | fCancUrl (in fCancUrlW) «Kündigungslink» / «netflix.com/cancelplan»; Hinweis «Seite im Kundenkonto, auf der du kündigst. Leer: die Website des Vertragspartners wird geöffnet.» | URL | "" | cancUrl (getrimmt) |
| Kundendaten | fCustNo «Kundennummer», fContrNo «Vertragsnummer» | Text | "" | custNo, contrNo |
| | fPayM «Zahlungsart»: "" «—», «Lastschrift (LSV/SEPA)», «eBill», «Kreditkarte», «QR-Rechnung», «Dauerauftrag», «TWINT», «PayPal», «Sonstiges» | Select | — | payM |
| | fPayA «Belastet über» / «z.B. Visa …4417» | Text | "" | payA |
| Kontakt & Notiz | fAddr «Adresse des Vertragspartners — für die Kündigung per Brief» / «Firma AG⏎Strasse Nr.⏎PLZ Ort» | mehrzeilig | c.addr, sonst die Adresse der Partnergruppe (gleicher Name, klein geschrieben) | addr (getrimmt) |
| | fWeb «Website oder Kundenportal» / «swisscom.ch/login» | URL | "" | web |
| | fTel «Telefon», fMail «E-Mail» | tel / email | "" | tel, mail |
| | fNote «Notiz» / «Zugangsweg, Ansprechpartner, Besonderheiten» | mehrzeilig | "" | note |
| Dokumente | docList, docUp «Datei anhängen — PDF oder Bild» (Dateityp PDF/PNG/JPEG/WebP) | Liste + Upload | leer | docs[] |
**Sichtbarkeit:** fCancUrlW nur bei «Online / Kundenkonto». Die Prüfung läuft beim Öffnen und bei `change` von fCancF, **nicht** nach einer Vorlage (F9). docUp nur mit Dateispeicher.
**fWatch ↔ Checkboxen (`syncWatch`):** Anzeige mand hat Vorrang vor nowatch. Eine Auswahl setzt fMand bzw. fNoWatch exklusiv.

### 7.6 Live-Verhalten auf der Hauptseite
- **`paintLogo`** (bei Eingabe in Vertragspartner und Bezeichnung, bei Kategorie/Farbe):
  - Mit vorhandenem Logo: Bild auf logoBg (Standard weiss), «Bild entfernen» sichtbar.
  - Sonst Farbe = draft.color bzw. Kategoriefarbe bzw. Hash-Farbe aus dem Namen, dazu das Kategoriesymbol.
  - Ruft `paintDup` und `paintLogoAll` auf.
- **`paintDup`** (auch bei Betrag und Währung):
  - Sucht andere Verträge desselben Vertragspartners. Schlüssel `pkey` = normalisierte Wörter ohne Stoppwörter, ohne den bearbeiteten Vertrag.
  - Treffer, wenn die Bezeichnung (normalisiert) gleich ist **oder** der aktuelle Betrag gleich und > 0 ist und die Währung gleich.
  - Text: «Mögliches Duplikat: «{Bezeichnung oder Vertragspartner}» ({Betrag} {Währung}) existiert bereits. Du kannst trotzdem speichern.» Nur ein Hinweis, er blockiert nichts.
- **`paintLogoAll`:**
  - Nur mit Logo und Vertragspartner. Zählt Verträge desselben Vertragspartners mit anderem Logo.
  - Knopf «Logo für 1 weiteren Vertrag von «{Name}» übernehmen» bzw. «Logo für {n} weitere Verträge von «{Name}» übernehmen».
  - Tippen schreibt das Logo **sofort** in diese Verträge (unabhängig von «Sichern»). Toast «Logo bei {n} Vertrag/Verträgen übernommen».
- **`paintHolders`:**
  - Chips für alle Personen (settings.holders, ergänzt um unbekannte aus dem Entwurf). Tippen schaltet um.
  - Keine Pflicht. Leer erlaubt, das meldet dann die Datenqualität.
- **`paintDocs`:** Zeile «📄 {Name}» (PDF) bzw. «🖼 {Name}». Tippen öffnet die Datei, «×» entfernt sie aus dem Entwurf (die Datei bleibt im Speicher).
- **Turnus geändert** (Z. 2949): im Modus open, wenn «Kündbar per» leer ist und der Turnus ≥ 6, wird «Ende Periode» gesetzt. Toast «Kündbar per «Ende Periode» vorgeschlagen».

### 7.7 Hinweis Laufzeit (`updTermHint`)
Neu berechnet bei Änderungen an fTermP, fNotice, fNoticeU, fStart, fDue, fCycle, fEnd und fRenew sowie beim Moduswechsel.
- **Modus fixed:**
  - `E = effEnd({end, renew})` (Ende, bei Verlängerung bis ≥ heute weitergerollt).
  - Ohne E: «Vertragsende angeben, dann rechnet die App den Kündigungstermin aus.»
  - Sonst: «Kündigen bis {fmtD(nDl(E))}», dann «, sonst +{n} Monat(e).» bzw. «, Vertrag endet dann.» (Achtung F13: ohne Weiterrollen bei verpasster Frist.)
- **Modus open, ohne «Kündbar per»:**
  - Turnus ≥ 3: «Achtung: Bei {Turnustext}er Zahlung ist ein Abo meist nur auf Ende der bezahlten Periode kündbar. Dann «Kündbar per: Ende Periode» wählen.» (Grammatikfehler F14)
  - sonst: «Unbefristet — du kannst mit der angegebenen Frist jederzeit kündigen.»
- **Modus open, mit «Kündbar per»:**
  - T = `nextTerm` mit den Formularwerten.
  - Ohne T: bei «a» «Für «Ende Vertragsjahr» bitte den Vertragsbeginn angeben.», sonst leer.
  - «p» und Turnus > 1: «Das Abo-Jahr endet {Datum} · kündigen bis {Datum}» (Turnus 12) bzw. «Das bezahlte Periode endet …» (F14).
  - sonst: «Nächster Termin: per {Datum} · kündigen bis {Datum}».
  - Ohne Frist folgt « (keine Frist erfasst)», am Ende immer «.».
- **Rechenregeln dazu (Rechenkern, Z. 1846–1879):**
  - `nDl`: Frist 0 → Ende; k → Tag n (max. 28) im Monat des Endes; w → −7n Tage; d → −n Tage; m → −n Monate (Monatsende-Klemmung).
  - `nextTerm`:
    - p = Tag vor der nächsten Zahlung, so lange weitergerollt, bis die Frist ≥ heute ist
    - a = Jahrestag (Beginn, sonst Stichtag) − 1 Tag
    - m/q/h/y = nächstes Monats-, Quartals-, Halbjahres- bzw. Jahresende mit Frist ≥ heute

### 7.8 Preisänderungen (`paintPrices`, pAdd, pList)
- **Liste:**
  - Zeile «Anfangspreis» mit dem Betrag aus fAmt (oder «—») und der Währung, Tag «aktuell», wenn noch keine Änderung gilt.
  - Je Änderung, nach Datum sortiert: «ab {fmtD}», Tag «aktuell» (letzte mit Datum ≤ heute) bzw. «geplant» (Zukunft), Betrag, Währung, «×» (löscht nach Datum).
- **Hinzufügen:**
  - Datum fehlt → «Datum für die Preisänderung fehlt»
  - Betrag fehlt oder < 0 → «Neuen Betrag prüfen» (0 erlaubt)
  - Ein vorhandenes gleiches Datum wird ersetzt, der Betrag auf 0.01 gerundet. Felder leeren, Toast «Preisänderung ab {fmtD} vorgemerkt».
- **Aktualisiert** bei Betrag und Währung. Das Label fAmtL wechselt auf «Anfangspreis».

### 7.9 Sonderzahlungen (`setXKind`, `paintExtras`, xAdd, xList)
- **Liste:**
  - Nach Datum sortiert (`extrasOf` filtert ungültige Daten und Betrag 0).
  - Zeile «{fmtD} · {Notiz}», Tag «Gutschrift» (negativer Betrag) und «geplant» (Zukunft), Betrag «−{Betrag}» bei Gutschrift, Währung, «×» (löscht nach Index der sortierten Liste).
- **Hinzufügen:**
  - Datum fehlt → «Datum der Sonderzahlung fehlt»
  - Betrag fehlt oder ≤ 0 → «Betrag prüfen»
  - Betrag = |x| auf 0.01 gerundet, bei Gutschrift negativ. Felder leeren.
  - Toast «Sonderzahlung am {fmtD} vorgemerkt» bzw. «Gutschrift am …». Danach wieder Art «Zahlung».

### 7.10 Speichern (Z. 3025–3070)
**Prüfungen** in dieser Reihenfolge:
1. Vertragspartner **und** Bezeichnung leer → «Bezeichnung fehlt».
2. Keine Kategorie → «Bitte eine Kategorie wählen», zum Feld scrollen, Kategorieauswahl öffnen.
3. Betrag nicht lesbar oder < 0 → «Betrag prüfen» (0 erlaubt).

Weitere Prüfungen gibt es nicht: keine für Datumsreihenfolge, Frist ≥ 0 (F19) oder Ende im Modus fixed.

**Datensatz:**
- Alle Felder aus 7.4 und 7.5.
- `status` = alter Status oder «active», `cancelledAt` = alt oder "", `t` = alt oder jetzt.
- **Achtung F1:** Alle übrigen alten Felder gehen verloren (cancelPer, cancelledOn, keptFor, trialKept, paused, pausedAt, pausedUntil). Für den Nachbau: alten Stand übernehmen und nur die Formularfelder überschreiben.

**Nur bei neuen Verträgen:**
- Ohne Logo übernimmt der Vertrag das Logo eines anderen Vertrags desselben Vertragspartners.
- Bei mindestens 2 Personen und geänderter Inhaberwahl: `settings.lastHolders` = gewählte Inhaber.

**Danach:**
- Speichern, alles schliessen, neu zeichnen. Toast «Aktualisiert» bzw. «Vertrag angelegt».
- Bei neuen Verträgen ohne Logo startet die Logo-Suche im Hintergrund (`autoAttach`, nur ein Vorschlag).

**Nicht** gemacht wird:
- Adresse an andere Verträge des Partners weitergeben (F7).
- `cancUrl` bei anderem Kündigungsweg leeren (F9).

---

## 8. Anbieterkatalog (TPL, Z. 2754–2922)

### 8.1 Struktur
- **TPL:** Array mit **98 Einträgen**. Jeder Eintrag ist ein Array mit 11 Feldern, Indizes in `TPLI` (dokumentarisch, im Code werden die Zahlen direkt verwendet):

| Idx | TPLI | Inhalt | Werte |
|---|---|---|---|
| 0 | n | Name (Vertragspartner), eindeutig | Text |
| 1 | cc | Land | «CH» (55), «DE» (28), "" = international (15, angezeigt als «CH · DE») |
| 2 | cat | Kategorie (Name der Vorbelegung) | Versicherung 29, Abos & Medien 16, Mobilfunk & Internet 14, Finanzen 13, Energie & Wasser 9, Mobilität 7, Freizeit & Sport 5, Sonstiges 5 (F10) |
| 3 | lab | Bezeichnung-Vorschlag | z.B. «Krankenkasse», «Handy / Internet» |
| 4 | web | Domain ohne Protokoll | "" bei M-Budget, Coop Mobile, Deutschlandticket |
| 5 | no | Kündigungsfrist (Zahl) | 0 = unbekannt bzw. keine |
| 6 | nu | Einheit | m (90), d (7), k (1, «. im Monat») |
| 7 | tm | Kündbar per | "" (31), p (17), m (12), y (13), a (25) |
| 8 | cf | Kündigungsweg (Anzeigetext von fCancF) | «Online / Kundenkonto» 33, «Brief» 15, «Einschreiben» 13, «E-Mail» 1, "" 34, **Zahl 0** bei Serafe/Rundfunkbeitrag (F10) |
| 9 | md | Pflichtvertrag | 1 bei 24 Einträgen (CH-Krankenkassen, DE-GKV, CH-Strom, Serafe, Rundfunkbeitrag), sonst 0 |
| 10 | h | Hinweistext | H_* oder eigener Text |

- Der Kommentar in Z. 2755 nennt Feld 8 «Kündigung per». Gemeint ist der Kündigungsweg.
- Gleiche Domain mehrfach: apple.com (Apple One, Apple Music, Apple TV+, iCloud+) und swisspass.ch (SBB Halbtax, SBB GA).

### 8.2 Hinweistexte (H_*, wörtlich)
- **H_KVG** (13×): «Grundversicherung: per 31.12. kündbar, Kündigung muss bis 30.11. eingetroffen sein. Mit Mindestfranchise und Standardmodell (freie Arztwahl) zusätzlich per 30.06., Kündigung bis 31.03. Zusatzversicherungen haben eigene Fristen.»
- **H_VVG** (9×): «Nach 3 Jahren per Ende Versicherungsjahr kündbar (VVG). Genaue Frist in der Police prüfen.»
- **H_TCH** (6× allein, dazu 1× bei M-Budget mit Zusatz « Nur schriftlich.»): «60 Tage auf Monatsende, frühestens auf Ende der Mindestlaufzeit.»
- **H_TDE** (5×): «Nach der Mindestlaufzeit monatlich mit 1 Monat Frist kündbar (TKG).»
- **H_STR** (14×): «Jederzeit kündbar, gilt ab der nächsten Abrechnungsperiode.»
- **H_BNK** (13×): «Konto jederzeit kündbar. Guthaben vorher übertragen.»
- **H_FIT** (4×): «Abos laufen meist 12 Monate. Verlängerung und Frist im Vertrag prüfen.»
- **H_ECH** (5×): «Grundversorgung: Haushalte können den Stromanbieter nicht wechseln.»
- **H_EDE** (4×): «Sondervertrag: nach Mindestlaufzeit meist 1 Monat Frist. Grundversorgung: 2 Wochen.»
- **H_GKV** (4×): «Gesetzliche Krankenkasse: 2 Monate zum Monatsende, nach mindestens 12 Monaten Mitgliedschaft.»
- **H_VDE** (3×): «Meist 3 Monate zum Ende des Versicherungsjahres, neuere Verträge oft 1 Monat. Police prüfen.»
- **H_PRF** (8× allein, 2× als Zusatz): «Frist im Vertrag prüfen.»
- **10 eigene Texte direkt im Eintrag:** SBB Halbtax, SBB GA, Serafe, Adobe, DAZN, ADAC, Deutschlandticket, BahnCard, Rundfunkbeitrag, M-Budget (Zusatz).
- Die H_*-Konstanten nutzt auch STD_RULES (Z. 4798, ausserhalb).

### 8.3 Nutzung
1. **Vorschlags-Chips unter dem Vertragspartner (`paintSugg`, #fSugg)**, neu gezeichnet bei Eingabe in Vertragspartner und Bezeichnung. Suchtext q = Vertragspartner, sonst Bezeichnung, klein geschrieben.
   - **a)** Es gibt einen Internet-Vorschlag `draft.stdTpl` und dessen Name = Vertragspartner: Hinweistext (Feld 10). Dazu der Chip «Übliche Frist übernehmen», wenn noch nicht übernommen und Frist oder Pflicht gesetzt sind. Tippen → `applyTpl(stdTpl, keepName)`, danach gilt er als erledigt.
   - **b)** Vertragspartner = Katalogname (exakt, Gross/Klein egal) und diese Vorlage wurde übernommen (`tplHint`): nur der Hinweistext.
   - **c)** q kürzer als 2 Zeichen **oder** exakter Katalogtreffer ohne Übernahme: nichts (F8).
   - **d)** Sonst Label «Vorlage» und bis zu 5 Chips mit Einträgen, deren «Name Bezeichnung» q enthält. Tippen → `applyTpl(Eintrag)`.
   - Jede Eingabe in Vertragspartner setzt `tplHint` und `stdTpl` zurück.
2. **Katalog-Fenster (`openTplPick`, Knopf im Feld Vertragspartner):**
   - Überlagertes sheetPick, Titel «Anbieter-Katalog».
   - Suchfeld «Anbieter suchen» (sucht in Name + Bezeichnung + Kategorie). Segment Land «Alle | CH | DE» (`tplCC`, bleibt bis zum Neuladen erhalten). Bei CH bzw. DE erscheinen die internationalen Einträge immer mit.
   - Liste alphabetisch (de): Kategoriesymbol, Name, darunter die Bezeichnung, rechts das Land.
   - Leer: «Kein Anbieter gefunden. Du kannst ihn einfach selbst eintippen.»
   - Fuss: «Fristen sind typische Werte. Massgebend ist immer dein Vertrag.»
   - Tippen → `applyTpl` und Fenster schliessen.
3. **`applyTpl(t, keepName, quiet)`:**
   - Ohne keepName wird Vertragspartner = Name gesetzt.
   - Bezeichnung = Feld 3, nur wenn leer.
   - Kategorie = Feld 2, **immer**, wenn nicht leer (F3, F12).
   - Frist und Einheit nur, wenn Feld 5 > 0 (sonst bleibt der alte Wert, F3).
   - Kündbar per = Feld 7 oder "", nur im Modus open.
   - Kündigungsweg = Feld 8, wenn gesetzt (ohne `syncCancUrl`, F9).
   - Website = Feld 4, nur wenn leer.
   - Pflicht = Feld 9 (fNoWatch bleibt, F3), danach `syncWatch`.
   - Währung: DE → EUR, CH → CHF, nur wenn der Betrag leer ist.
   - Danach `tplHint` = Name; Logo, Farben, Chips und Laufzeit-Hinweis neu. Ohne quiet Toast «Vorlage übernommen — bitte prüfen».
4. **Internet-Treffer (`pickWebPartner`, Z. 4846, ausserhalb):**
   - Sucht den Katalogeintrag mit gleicher registrierbarer Domain (`regDom` = letzte 2 Teile). Mit Treffer: `stdTpl` = [Name aus Wikidata] + Katalogfelder 1–10. Sonst `stdFor` (Branche + Land aus STD_RULES im selben Format).
   - Setzt die Kategorie nur bei leerer Kategorie, die Bezeichnung nur bei leerer Bezeichnung.
   - Sind Frist **und** «Kündbar per» leer und hat der Vorschlag Frist, «Kündbar per» oder Pflicht, folgt `applyTpl(stdTpl, keepName, quiet)` (direkt eingetragen, Hinweis bleibt).
   - Ein Eintrag ohne Hinweistext wird verworfen.
5. **CSV-Import (Z. 5369ff, ausserhalb):**
   - `tplFind(Vertragspartner) || tplFind(Bezeichnung)` (exakter Name).
   - Füllt fehlende Werte: Kategorie (2), Frist und Einheit (5/6, nur ohne Fristspalte), Kündbar per (7, nur ohne Ende), Pflicht (9, nur ohne Pflichtspalte und ohne Tag «Pflicht»), Kündigungsweg (8), Website (4).
6. **`tplFlag(t)`:** Land oder «CH · DE».

### 8.4 SwiftUI-Hinweise
- Katalog als JSON im Bundle, Struct mit benannten Feldern statt Array:
  - `country: String?`, `notice: Int`, `noticeUnit: enum`, `cancelTerm: enum`, `channel: CancelChannel?`, `mandatory: Bool`, `hint: String`
  - Vorher die Zahl 0 in Feld 8 bereinigen (F10).
- Die Auswahl als `.searchable` List mit Segment-Picker.
- Die Regel «nur leere Felder» sauber trennen von «ausdrückliche Übernahme» (F3).
