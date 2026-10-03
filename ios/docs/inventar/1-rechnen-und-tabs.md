# Portierungs-Inventar R1: index.html Zeilen 1604–2297

Geltungsbereich: Helfer, Kategorien, Absender-Helfer, Rechenkern, Speicher, Hero, Vertragskarte, Tabs «Verträge», «Fristen», «Archiv», Theme, Filter, Auswahlblatt, Pop-up bei langem Drücken, Anfang «Kosten» (Aggregation + Balkendiagramm).
Notation: JS-Name in Klammern; sichtbare Texte wörtlich in «»; `HW` = Hauptwährung (settings.home); Datum immer lokales Kalenderdatum ohne Uhrzeit (Mitternacht lokal), nie UTC.
Wo das Verhalten einen Fund aus r1-findings.md hat, steht «⚠ Fund X»: vor dem Nachbau entscheiden, ob 1:1 (golden.json) oder korrigiert.

---

## 0. Konstanten und Startzustand

- Ausgaben-Kategorien (CATS), Reihenfolge fix: «Wohnen», «Energie & Wasser», «Versicherung», «Gesundheit», «Mobilfunk & Internet», «Abos & Medien», «Mobilität», «Familie & Bildung», «Freizeit & Sport», «Steuern & Gebühren», «Finanzen», «Sonstiges».
- Kategorie-Farben (CAT_COLOR): Wohnen #6B4E9E, Energie & Wasser #B0562A, Versicherung #0E5A5E, Gesundheit #B03A5B, Mobilfunk & Internet #1F4E8C, Abos & Medien #A93227, Mobilität #3F4A55, Familie & Bildung #2F86A6, Freizeit & Sport #2E6A4E, Steuern & Gebühren #6E7B3A, Finanzen #8A6A1F, Sonstiges #5F666E; Einnahmen: Lohn #2E6A4E, Nebeneinkommen #0E5A5E, Bonus #8A6A1F, Kapitalerträge #1F4E8C, Vermietung #6B4E9E, Rente #B0562A.
- Hash-Farben ohne Kategorie (COLORS, 8): #0E5A5E, #A93227, #1F4E8C, #6B4E9E, #8A6A1F, #2E6A4E, #B0562A, #3F4A55.
- Alt-Kategorien (CAT_MIG): «Energie»→«Energie & Wasser», «Streaming & Software»→«Abos & Medien», «Fitness & Freizeit»→«Freizeit & Sport», «Steuern»→«Steuern & Gebühren», «Kinderbetreuung»→«Familie & Bildung».
- Symbole (CAT_ICON): je Kategorie und Einnahmeart ein 24×24-Linien-Symbol (SVG-Pfade im Code; SwiftUI: SF Symbols oder eigene Assets mit gleichem Namen als Schlüssel), plus TAG_ICON (Etikett) für eigene Kategorien.
- Turnus (CYCLE, Monate → Text): 1 «monatlich», 2 «alle 2 Monate», 3 «quartalsweise», 6 «halbjährlich», 12 «jährlich», 24 «alle 2 Jahre». (Einnahmen zusätzlich 0 «einmalig», ausserhalb.)
- Kündigungstermine (TERMS): "" «jederzeit», p «Ende der Zahlungsperiode», m «Monatsende», q «Quartalsende», h «Halbjahresende», y «Jahresende», a «Ende Vertragsjahr».
- Monatsnamen kurz (MS): «Jan» «Feb» «Mär» «Apr» «Mai» «Jun» «Jul» «Aug» «Sep» «Okt» «Nov» «Dez»; lang (MON): «Januar» … «Dezember».
- Zahlenformat: `nf` = de-CH, genau 2 Nachkommastellen, Tausendertrenner «’» (U+2019), Dezimalpunkt «.» (z.B. «1’284.50»), gilt auch für EUR (Entscheid). `nf0` = de-CH, 0 Nachkommastellen (gerundet).
- Speicher-Schlüssel (LS): «vertraege.v1».
- Startwerte Kurse (RATE0, CHF pro Einheit): EUR 0.94, USD 0.80, GBP 1.07, TRY 0.02.
- Startzustand: settings {home "CHF", rates {}, holders ["Ich"]}, contracts {}, incomes {}, tab "list", sel = aktueller Monat (0–11), year = aktuelles Jahr. Weitere Laufzeit-Zustände: heroF, q (Suche), flt {cat, partner, holder}, showArch, tfold {}, sg ("cat"|"partner"), fMore, autoSel, _rvDue.

## 1. Allgemeine Helfer

- Betrag anzeigen (money): `nf.format(v || 0)`.
- Zahl einlesen (parseNum): `'` entfernen, erstes «,» → «.», parseFloat; nicht endlich → null. ⚠ Fund M6 («’» und «1.234,50» werden falsch gelesen).
- HTML-Escaping (esc): & < > " (nicht '). In SwiftUI entfällt; Texte immer als Text, nie als Markup.
- ID (uid): Zeitstempel ms base36 + 5 Zufallszeichen base36. SwiftUI: UUID.
- Toast (toast): Text einblenden, nach 2.4 s ausblenden; neuer Toast ersetzt alten.
- Heute (today): lokales Datum ohne Zeit; Testhaken `window.__KONTIVO_TODAY` (JJJJ-MM-TT) überschreibt. SwiftUI: injizierbare Uhr (`Calendar.current.startOfDay(for: now)`).
- Datum lesen (parseD): «JJJJ-MM-TT» → lokales Datum; ohne 3 Teile oder NaN → null. Ungültige Tage rollen über (31.02. → 03.03., bewusst nicht validiert).
- Datum lang (fmtD): «3. Oktober 2026»; leer/ungültig → «—».
- Datum kurz (fmtShort): «03.10.26» (TT.MM.JJ); null → «—».
- ISO (iso): JJJJ-MM-TT aus lokalen Feldern.
- Monate addieren (addMonths): Zielmonat = Monat + n (Jahr läuft mit, auch negativ); Tag = min(Tag, letzter Tag des Zielmonats). Bsp. 31.01. + 1 = 28./29.02.
- Tage addieren (addDays): Kalendertage (DST-sicher über Datumskomponenten).
- Tage dazwischen (daysBetween): `round((b − a) / 86 400 000)` → Kalendertage, DST-neutral. SwiftUI: `Calendar.dateComponents([.day], from:to:)`.
- Titel (titleOf): label → partner → name → «Ohne Namen».
- Inhaber (holdersOf): holders, wenn nicht leer, sonst [].
- URL (normUrl): getrimmt; ohne http(s):// wird «https://» vorangestellt. Domain (domainOf): Hostname ohne «www.», Fehler → "".
- Zweitzeile Vertragspartner (metaOf): partner (getrimmt) nur, wenn label vorhanden und partner ≠ label (Vergleich ohne Gross/Klein, getrimmt); sonst leer.

## 2. Währung

- Kurs (rateOf): CHF oder leer → 1; sonst settings.rates[cur] wenn > 0, sonst RATE0[cur], sonst 1.
- Umrechnung (conv(a, cur)): cur leer → «CHF»; cur == HW → a unverändert; sonst `a × rateOf(cur) / rateOf(HW)`. Keine Rundung in der Rechnung, nur in der Anzeige (2 Stellen).

## 3. Kategorien und Darstellung

- Kategorienliste (catList): settings.catList, wenn nicht leer (Einträge {n Name, c Farbe, i Symbolschlüssel}); sonst die 12 Standardkategorien (Farbe CAT_COLOR, Symbol = Name) plus Alt-Einträge aus settings.cats, die keine Standardkategorie sind (Symbol «tag»).
- Speichern (saveCatList): catList setzen, settings.cats löschen, sichern.
- Eintrag/Namen (catEntry, allCats): Suche per Name; Liste der Namen in Reihenfolge.
- Farbe (catColor): Eintragsfarbe → CAT_COLOR[Name] → #5F666E.
- Symbol (catIcon): mit Eintrag: i=="tag" → Etikett, sonst Symbol i (unbekannt → Etikett). Ohne Eintrag: Symbol des Namens; sonst Etikett, ausser Name leer oder Einnahmeart → Symbol «Sonstiges».
- Markenfarbe (colorFor): c.color → catColor(c.cat) → Hash über partner/label/name: `h = (h×31 + Zeichencode) mod 8` → COLORS[h].
- Logo-Kachel (markHtml): hat der Vertrag ein Logo (logoId vorhanden im Dateispeicher) → Bild auf Hintergrund logoBg (Standard Weiss); sonst Kachel in colorFor mit Kategorie-Symbol (Kategorie leer → «Sonstiges»).

## 4. Migration beim Laden und Backup-Einspielen (migModel, migCats, senderParse)

- settings.rate (alt) → rates.EUR, nur wenn rates.EUR nicht > 0 und rate > 0; rate löschen.
- Vertrag/Einnahme holder (alt) → holders = [holder], wenn holders leer; holder löschen.
- settings.sender (Freitext) → senderF über senderParse; sender löschen.
- senderF/sig (global, alt) → pro Inhaber: Ziel = Inhaber, dessen Name (ohne Gross/Klein) dem Vornamen in senderF entspricht, sonst erster Inhaber (ohne Inhaber «Ich»). Nur setzen, wenn Ziel noch nichts hat; danach senderF/sig löschen.
- Kategorien: Vertragskategorie gemäss CAT_MIG umbenennen; catList-Einträge umbenennen (auch Symbolschlüssel), danach Dubletten nach Name entfernen (erster gewinnt); settings.cats ohne Alt-Namen. Bei jeder Änderung sofort sichern.
- senderParse (Freitext → {first,last,street,zip,city,country}): Zeilen getrimmt, leere weg. PLZ-Zeile = erste Zeile, die passt auf «optional 1–2 Grossbuchstaben + optional - , dann 4–5 Ziffern, Leerzeichen, Text». Erste Zeile (wenn nicht PLZ-Zeile) = Name: letztes Wort = Nachname (nur bei ≥ 2 Wörtern), Rest = Vorname. Mit PLZ-Zeile: zip/city daraus, Strasse = Zeilen 2 bis vor PLZ (mit «, » verbunden), Land = Zeilen danach (mit «, »). Ohne PLZ-Zeile: Strasse = alle Zeilen ab 2.

## 5. Absender, Unterschrift, Bild pro Inhaber (Schlüssel = Inhabername)

- Daten: settings.senders {Name: {first,last,street,zip,city,country, same?: anderer Name}}, settings.sigs {Name: JPEG-Data-URL}, settings.avatars {Name: Datei-ID}.
- Absender auflösen (sndOf): alle Felder getrimmt; hat der Eintrag `same` (≠ eigener Name), werden street/zip/city/country vom anderen Inhaber genommen (nur eine Ebene).
- Adresszeilen (sndAddr): [Strasse, «PLZ Ort» (ohne Leerteile), Land], leere weg.
- Anzeigename (sndName): «Vorname Nachname», sonst Inhabername.
- Vollständig (sndOk): (Vorname oder Nachname) und Strasse und Ort.
- Unterschrift (sigOf), setzen (setSnd, setSig: leer = löschen) → jeweils sofort sichern.
- Bild (avOf, avHtml, setAv): Kreis mit Bild, sonst erster Buchstabe des Namens gross («?» bei leer).
- Umbenennen/Zusammenführen (sndRename(alt, neu)): Bild, Absender, Unterschrift wandern zu «neu», nur wenn «neu» noch keine eigenen hat (sonst bleiben die von «neu», die alten werden verworfen). Wer `same = alt` hatte: zeigt jetzt auf «neu»; ist das «neu» selbst, wird `same` entfernt und die Adresse von «alt» kopiert.
- Löschen (sndDrop(h)): Bild/Absender/Unterschrift von h entfernen; wer `same = h` hatte, bekommt h's Adresse kopiert und `same` entfernt.

## 6. Rechenkern (Prüffälle tests/golden.json)

### 6.1 Preise und Sonderzahlungen
- Preisstufen (pricesOf): prices mit gesetztem `from` und numerischem Betrag, aufsteigend nach `from` (Textvergleich JJJJ-MM-TT).
- Preis an Datum (priceAt(c, d)): Start = c.amount (Anfangspreis); jede Stufe mit from ≤ d überschreibt.
- Aktueller Preis (curPrice): priceAt(heute).
- Nächste Preisänderung (nextChange): erste Stufe mit from > heute.
- Sonderzahlungen (extrasOf): Einträge mit gültigem Datum, numerischem Betrag ≠ 0; Notiz leer erlaubt; aufsteigend nach Datum. Negativ = Gutschrift.
- Bezeichnung (exLabel): «Gutschrift» (Betrag < 0) bzw. «Sonderzahlung», plus « · Notiz» wenn vorhanden.
- Zahlungen im Zeitraum (payments(c, von, bis)): reguläre Termine (occurrences) mit Betrag priceAt(Termin) + Sonderzahlungen mit von ≤ Datum ≤ bis (ohne Rücksicht auf Pause, Ende oder Beginn). Beträge in Vertragswährung.

### 6.2 Monatskosten
- monthlyCost(c) = conv(curPrice(c), cur) / Turnus (Turnus leer/0 → 1). Ohne Sonderzahlungen, ohne Pause, ohne Beginn-Prüfung (Aufrufer filtern).

### 6.3 Zahlungstermine (occurrences(c, von, bis))
- Anker a = due («Nächste Zahlung am»); fehlt → keine Termine.
- Turnus 0/"0" (nur Einnahmen «einmalig»): genau a, wenn im Zeitraum.
- Sonst m = Turnus (Standard 1). Termine = addMonths(a, k×m) für ganze k (auch negativ, also auch vor dem Anker; immer vom Anker, kein Drift bei 29.–31.). Start-k = floor(Monatsdifferenz(von, a)/m) − 1; höchstens 400 Schritte.
- Termin wird übersprungen, wenn < von, oder < Vertragsbeginn (start), oder in der Pause: pausiert (paused true) und Termin ≥ Pausebeginn (pausedAt, fehlt → heute) und (kein pausedUntil oder Termin < pausedUntil).
- Abbruch, wenn Termin > bis oder Termin > Grenze (limitOf).
- Grenze (limitOf): Gekündigt (status cancelled): e = end; mit Verlängerung und cancelledAt: e so lange + Verlängerung, bis e ≥ cancelledAt (max. 200); Basis = e, sonst cancelledAt, sonst keine. Nicht gekündigt: Basis = end nur ohne Verlängerung. Mit cancelPer: Grenze = min(Basis, cancelPer) bzw. cancelPer. Termin genau am Grenzdatum zählt noch. ⚠ Fund M2 (Fortschreibung driftet).
- Nächste Zahlung (nextDue): erster Termin in [heute, heute + 13 Monate], sonst null. ⚠ Fund N1 (Turnus 24).

### 6.4 Vertragsende, Fristen, Termine
- Effektives Ende (effEnd): end fehlt → null; ohne Verlängerung → end; mit Verlängerung r: end so lange + r Monate, bis ≥ heute (max. 200). ⚠ Fund M2.
- Frist zu Termin e (nDl(c, e)): notice n = 0 → e selbst. Einheit «k» («bis zum n. des Monats»): Tag min(n, 28) im Monat von e. «w»: e − 7n Tage. «d»: e − n Tage. Sonst Monate: addMonths(e, −n). ⚠ Fund M1 (Monatsende).
- Nächster Kündigungstermin bei unbefristeten Verträgen (nextTerm(c, basis = heute)): nur wenn kein end und cancTerm gesetzt, sonst null.
  - «p» (Ende Zahlungsperiode): nd = nextDue; fehlt → null. T = nd − 1 Tag. Solange Frist(T) < basis (max. 40): T = (T + 1 Tag) + Turnus Monate − 1 Tag. Rückgabe T.
  - «a» (Ende Vertragsjahr): Anker b = start, sonst due; fehlt → null. Für k = 1…299: T = addMonths(b, 12k) − 1 Tag; erster T mit T ≥ basis und Frist(T) ≥ basis.
  - «m/q/h/y»: Monatsletzte ab aktuellem Monat der Basis, bis 60 Monate; q nur Monate 3/6/9/12, h nur 6/12, y nur 12; erster mit Frist(T) ≥ basis.
- Nächstes mögliches Vertragsende (termEnd): ohne effEnd → nextTerm. Mit effEnd e und Verlängerung r und ohne cancelPer: solange Frist(e) < heute, e += r Monate (max. 200). Damit verschwindet ein Vertrag mit verpasster Frist nicht aus «Fristen».
- Steuern (isTax): Kategorie beginnt mit «Steuern» (ohne Gross/Klein) → nie Frist, nie in «Fristen».
- Kündigungsfrist (noticeDeadline): Steuern → null; sonst Frist(termEnd), wenn termEnd vorhanden.
- Jederzeit kündbar (isAnytime): kein end und cancTerm «p» oder «m». ⚠ Fund H1 (gilt auch für Jahresabos mit «p»).
- Behalten (isKept): keptFor == ISO(termEnd).
- Entscheidung nötig (needsAction): false bei cancelPer, ohne termEnd, isAnytime, noWatch, behalten. Sonst Tage = daysBetween(heute, Frist(termEnd)); true bei 0 ≤ Tage ≤ 90. (Steuern filtern die Aufrufer.)
- Probeabo (trialNeeds): trial-Datum ≥ heute, ≤ 90 Tage entfernt, trialKept ≠ trial, kein cancelPer.
- Dringlichkeit (urgency): ohne Frist → {lvl "", days null}. Tage = bis zur Frist; lvl: < 0 → "", ≤ 30 → «alert», ≤ 90 → «warn», sonst «ok»; lvl "" erzwungen bei isAnytime, noWatch, cancelPer oder behalten.
- Verlängert bis (renewTo): effEnd + Verlängerung, nur bei end und Verlängerung. ⚠ Fund M3.

### 6.5 Zustände und Listen
- Pausiert (isPaused): paused true und (kein pausedUntil oder heute < pausedUntil).
- Noch nicht aktiv (notStarted): start > heute.
- Beendet durch Kündigung (endedByNotice): cancelPer < heute.
- Aktiv (active): alle Verträge mit status ≠ cancelled und nicht endedByNotice (inkl. pausiert und noch nicht aktiv). ⚠ Fund M4 (abgelaufene befristete bleiben aktiv).
- Laufend (running): aktiv und nicht pausiert.
- Archiv (archived): status cancelled oder endedByNotice.
- Anteil einer Person (holderShare(c, h)): h leer → aktueller Personenfilter; kein Filter → 1; h nicht unter den Inhabern → 0; sonst 1 / Anzahl Inhaber. Text (shareTxt): «Anteil x %» (x = gerundet).

### 6.6 Texte für Zeiträume
- In-Tagen (inDays): 0 «heute», 1 «morgen», ≤ 60 «in n Tagen»; sonst m = round(d/30.44): < 24 «in m Monat/Monaten»; sonst y = round(d/365.25) «in y Jahr/Jahren».
- Dauer (humanDays): 0 «heute», 1 «1 Tag», ≤ 60 «n Tage»; m = round(d/30.44) < 24 «m Monate»; sonst «y Jahre».
- Fristtext (noticeText): notice 0 → ""; «k» → «bis zum n. des Monats»; sonst «n Woche/Wochen», «n Tag/Tage», «n Monat/Monate».

## 7. Preisverlauf-Diagramm (priceChart), nur bei ≥ 1 Preisstufe

- Punkte: [Anfang mit c.amount] + Stufen (Datum, Betrag).
- Startdatum st: Vertragsbeginn, wenn gültig und vor der ersten Stufe; sonst erste Stufe − max(180 Tage, 25 % der Spanne erste→letzte Stufe).
- Enddatum: max(heute, letzte Stufe + max(60 Tage, 8 % der Spanne st→letzte)).
- Fläche 320×96; x links 4, rechts 316; y oben 16, unten 78. Y-Bereich min..max der Beträge; gleich → ±1; dann 18 % Polster oben/unten.
- Linie als Treppe (Stufe am Änderungsdatum), durchgezogen bis heute, danach gestrichelt (opacity .7) ab X(heute) auf altem Niveau; Linie läuft bis zum Enddatum. Fläche unter der durchgezogenen Linie: Teal 12 %.
- Punkte r 3.5 an jeder Stufe: Zukunft = Rand Warnfarbe; aktueller Preis (letzte Stufe ≤ heute) = Teal gefüllt; Vergangenheit = Feldfarbe mit Teal-Rand.
- Beschriftung: links über der Linie Anfangsbetrag, rechts letzter Betrag (rechtsbündig); unten links Jahr von st, wenn Vertragsbeginn vor erster Stufe, sonst «Anfang»; unten rechts «heute», wenn Ende = heute, sonst Jahr des Endes; zusätzlich «heute» mittig unter X(heute), wenn st < heute < Ende und Platz (x zwischen L+44 und R−58).
- Kopfzeile links: «Geplant ab <fmtD erste Stufe>», wenn noch keine Stufe ≤ heute, sonst «Veränderung bis heute». Rechts fett: Vorzeichen («+», «−», «±») + Betrag(|Diff|) + « » + Währung + (wenn Anfang ≠ 0) « (Vorzeichen x %)» mit max. 1 Nachkommastelle (de-CH). Diff = (geplant ? erste Stufe : aktueller Preis) − Anfang. Farbe: Diff > 0 Warnfarbe, < 0 Grün (ok).
- Bedienungshilfe: «Preisverlauf von <Anfang> auf <letzter> <Währung>». SwiftUI: Charts LineMark .stepEnd + AreaMark.

## 8. Speicher (saveLocal, loadLocal, put*/drop*)

- Ein JSON-Objekt {settings, contracts, incomes} unter «vertraege.v1»; jede Änderung schreibt alles neu. Fehler werden still ignoriert (⚠ Fund N9).
- Laden: settings werden in die Startwerte gemischt (fehlende Schlüssel behalten Standard), contracts/incomes ersetzt, danach Migration (Abschnitt 4).
- putContract/putIncome: Eintrag setzen und sichern; dropContract/dropIncome: löschen und sichern; saveSettings = sichern.
- SwiftUI: SwiftData-Modelle; Migration als einmaliger Import des JSON.

## 9. Kopfbereich «Hero» (renderHero)

- Gezählt: laufende, bereits begonnene Verträge (running ∧ ¬notStarted). Monatssumme = Σ monthlyCost (in HW).
- Grosse Zahl: money(Summe), daneben HW-Kürzel.
- Untertitel: «<nf0(Summe × 12)> <HW> pro Jahr», plus « · n aktiver Vertrag»/« · n aktive Verträge» nur, wenn es keine pausierten und keine künftigen gibt und n > 0.
- Chips (nur wenn pausierte oder künftige existieren): «<b>n</b> aktiv ›» (Filter act), wenn pausierte: «n pausiert ›» (paused), wenn künftige: «n noch nicht aktiv ›» (fut). Gewählter Chip gefüllt Teal mit weisser Schrift, sonst Teal 11 % Hintergrund. Tippen schaltet Filter heroF ein/aus. pausiert = active − (laufend+begonnen) − künftig.
- Quartals-Check fällig (_rvDue): Referenz = settings.lastReview, sonst frühester Erfassungszeitstempel t aller Verträge (auf Tag gekürzt); fällig, wenn ≥ 90 Tage seit Referenz, kein reviewSnooze > heute und mind. 1 aktiver Vertrag. Anzeige erfolgt im Fristen-Tab (Abschnitt 13).

## 10. Vertragskarte (cardHtml(c, Modus))

- Aufbau: Logo-Kachel | Titel (titleOf, einzeilig, s. fitTitles) + optional Zweitzeile Vertragspartner (metaOf) + Status-Etiketten | rechts Betrag-Spalte. Tippen öffnet Vertragsdetail.
- Etiketten (graue Pille): «gekündigt per <TT.MM.JJ>» (cancelPer), «ab <TT.MM.JJ>» (noch nicht aktiv), «pausiert» bzw. «pausiert bis <TT.MM.JJ>».
- Zustände: pausiert → Logo, Titel, Betrag 50 % Deckkraft; status cancelled → ganze Karte 60 %.
- Modus «list» (Standard): Betrag curPrice in Vertragswährung + Kürzel; Zweitzeile Turnus-Text, wenn Turnus ≠ monatlich.
- Modus «cost»: monthlyCost + «<HW>/Mt.»; Zweitzeile «monatlich», wenn Turnus 1 und Währung = HW, sonst «<curPrice> <Währung> <Turnus-Text>».
- Modus «pay» (Sortierung Fälligkeit): Betrag priceAt(nächste Zahlung) + Vertragswährung; Zustandszeile: Tage bis Zahlung 0 → «heute fällig» (neutral), 1–7 → «in n Tag/Tagen» (Warnfarbe, fett), sonst «fällig <TT.MM.JJ>».
- (Modus «term» und Zweig «bezahlt» sind tot, nicht portieren – ⚠ Fund N6.)
- Titel einpassen (fitTitles): ist der Titel breiter als der Platz, Schrift auf max(12, abgerundet(Basis × Breite/Inhaltsbreite, 0.1)) px verkleinern, danach «…». Läuft nach jeder DOM-Änderung, Grössenänderung, Schriftladen. SwiftUI: `.lineLimit(1).minimumScaleFactor(12/Basis)`.

## 11. Tab «Verträge» (renderView, tab list)

- Tabbar-Zähler: Verträge = Anzahl aktiv (leer bei 0); Archiv = Anzahl archiviert; Fristen = Σ(laufend ∧ needsAction ∧ ¬Steuer) + Σ(laufend ∧ trialNeeds ∧ ¬Steuer) (ein Vertrag kann doppelt zählen; identisch mit «n offen» in Fristen). ⚠ Fund M5 (pausierte fehlen).
- Suche (state.q): getrimmt, ohne Gross/Klein, Teilstring in label, partner, Kategorie, Inhaber (mit Leerzeichen), Kundennummer, Vertragsnummer, Notiz.
- Filter: Kategorie/Vertragspartner/Inhaber (state.flt, gemeinsam mit «Kosten»), dann Hero-Filter: fut = noch nicht aktiv, paused = pausiert, act = weder noch.
- Filterknopf: Beschriftung «Filter» bzw. «Filter · n», aktiv hervorgehoben.
- Leiste aktiver Filter (bei Filter oder Hero-Filter): Pillen «Noch nicht aktiv»/«Pausiert»/«Aktiv» und je Filterwert der Wert, jeweils mit «×» zum Entfernen.
- Archiv unten (wenn archivierte Treffer, Suche und Filter gelten, Hero-Filter nicht): Zeile «Archiv» | «n gekündigter Vertrag»/«n gekündigte Verträge» mit Pfeil; aufgeklappt (showArch) Karten im Modus list.
- Leerzustände: gar keine Verträge → Leerseite emptyList (ausserhalb). Keine aktiven Treffer mit Suche → «Keine Treffer» «Für «<Suche>» gibt es keinen aktiven Vertrag.»; mit Filter → «Keine Treffer» «Für «<Filter, mit « · » verbunden>» gibt es keinen aktiven Vertrag.»; sonst Logo + «Willkommen bei Kontivo» «Fixkosten, Verträge und Fristen – klar im Griff.» «Tippe oben auf + und leg den ersten Vertrag an. Mit «Aus Katalog wählen» geht es am schnellsten.» (⚠ Fund N5). Archiv-Zeile darunter.
- Sortierknopf zeigt «Sortiert / <Modus>»: cat «Kategorie», cost «Kosten», partner «Vertragspartner», due «Fälligkeit», holder «Inhaber». Standard cat.
- Gruppe: Kopf links Titel, rechts Summe «<money(Σ monthlyCost ohne pausierte)> <HW>/Mt.» (⚠ Fund N7: künftige zählen mit).
- Sortierungen:
  - cat: Gruppen in catList-Reihenfolge, danach unbekannte Kategorien in Auftretensreihenfolge; Vertrag ohne Kategorie → «Sonstiges»; innerhalb absteigend nach monthlyCost.
  - cost: eine Gruppe ohne Kopf, absteigend nach monthlyCost, Kartenmodus cost.
  - partner: alphabetisch nach Vertragspartner (de-CH, ohne Akzent-/Grossunterscheidung); Gruppen je erstem Zeichen (getrimmt, gross; leer → «#»), Kopf ohne Summe; Reihenfolge der Gruppen nach erstem Auftreten («Ä» ist eigene Gruppe).
  - due: Verträge mit nächster Zahlung aufsteigend; Gruppe je «<Monat lang> <Jahr>» der nächsten Zahlung, Kopf-Summe «<money(Σ conv(priceAt(nächste Zahlung)))> <HW>» (nur diese eine Zahlung je Vertrag), Kartenmodus pay; ohne nächste Zahlung Gruppe «Ohne Zahlungstermin» (Standardkopf, Modus list).
  - holder: absteigend nach monthlyCost, gruppiert nach Inhabern mit « & » verbunden bzw. «Ohne Inhaber»; Gruppen alphabetisch (de-CH, «Ohne Inhaber» wird mitsortiert). ⚠ Fund N3.
- Auswahlblatt Sortierung (openPick("sort")): Titel «Sortieren nach», Optionen «Fälligkeit», «Kosten, höchste zuerst», «Vertragspartner, A–Z», «Kategorie», «Inhaber»; gewählte markiert.

## 12. Tab «Archiv» (renderView, sonstiger Tab)

- Alle archivierten Verträge als Karten (Modus list) in einer Gruppe; leer: «Archiv leer» «Gekündigte Verträge landen hier und zählen nicht mehr in den Summen.»

## 13. Tab «Fristen» (renderView, tab term)

- Grundmenge a = laufende Verträge ohne Steuern (⚠ Fund M5). Datumsformat ddmm: «TT.MM.» im laufenden Jahr, sonst «TT.MM.JJ».
- Entscheidungen: todo = needsAction, aufsteigend nach Frist; triTodo = trialNeeds, aufsteigend nach Probeabo-Ende. n = Summe.
- Kopfzeile, wenn n > 0: «<b>n offen</b>» + « · k dringend» (k = Anzahl mit ≤ 30 Tagen, nur wenn 0 < k < n) + « · nächste Frist <inDays(früheste Frist/Probeende)>». Wenn n = 0 und a nicht leer: «<b>Alles erledigt</b> · keine offenen Entscheidungen» (grün).
- Entscheidungskarten (Probeabos zuerst, dann Fristen): Logo, Titel, Zeile «Probeabo endet <ddmm>» bzw. «Frist <ddmm>» + « · heute» (0 Tage) oder « · noch <humanDays>»; Farbe ≤ 30 Tage Alarm (rot), sonst Warnung (orange). Zweitzeile «<nf0(monthlyCost × 12)> <HW> pro Jahr» + « · Pflichtvertrag» bei mand. Knöpfe «Behalten» und «Kündigen» (bei Pflichtvertrag «Wechseln»), mit Probeabo-Kennung. Karte antippen → Detail. (Aktionen ausserhalb des Abschnitts.)
- «Kommende Termine» (Gruppe, nur wenn Einträge): für jeden Vertrag in a, der weder needsAction noch trialNeeds noch noWatch ist:
  - cancelPer: «gekündigt · endet <TT.MM.JJ>» (Farbe rot 80 %), Sortierdatum cancelPer.
  - isAnytime: übersprungen.
  - ohne termEnd: übersprungen.
  - behalten: Folgetermin T2 = befristet ? (mit Verlängerung termEnd + Verlängerung, sonst keiner) : nextTerm(Basis termEnd + 1 Tag); Text «behalten · Frist <TT.MM.JJ>» bzw. «behalten» (grün); Sortierdatum Frist(T2) oder termEnd. ⚠ Fund N2.
  - sonst Frist(termEnd); liegt sie vor heute → übersprungen; Text «Frist <TT.MM.JJ>».
  - aufsteigend nach Sortierdatum; Zeile: Logo, Titel, rechts Text.
- Klappgruppen (Titel «<Name> (n)», zugeklappt Standard, Zustand pro Schlüssel in tfold):
  - «Jederzeit kündbar» (any): ohne cancelPer, ohne noWatch und (isAnytime oder (keine Frist berechenbar und notice > 0)). Text: «zum Periodenende» (cancTerm p), sonst «nächste Frist <ddmm(Frist(nextTerm))>», sonst «Frist <noticeText>».
  - «Ohne Frist erfasst (n) · ergänzen» (none): ohne cancelPer, ohne noWatch, keine Frist berechenbar, notice 0, kein Pflichtvertrag. Text «ergänzen».
  - «Nicht beobachtet» (unw): noWatch ohne cancelPer. Text «Frist <noticeText>» oder leer.
- Quartals-Check (wenn _rvDue): «Quartals-Check», «Stimmen Beträge, Fristen und Preise noch?», Knöpfe «Alles geprüft» und «Später».
- Ganz leer (kein Inhalt) → Leerseite emptyTerm (ausserhalb).

## 14. Darstellung (applyTheme, render)

- settings.theme: «light», «dark» oder «auto» (System, reagiert live auf Systemwechsel). Segment-Knöpfe markieren Auswahl; Tippen speichert sofort. Statusleistenfarbe = Papierfarbe (#F3F1EC hell, #15171A dunkel).
- Farben hell/dunkel: Papier #F3F1EC/#15171A, Fläche #FBFAF7/#1E2125, Vertieft #E9E6DF/#272B30, Text #1B1E23/#E9EAE5, Text2 #5F666E/#9AA1A8, Text3 #687077/#8D949B, Linie #E1DED6/#2F343A, Teal #0E5A5E/#5FB3B5, Ok #2E6A4E/#6FB58E, Warnung #9A6710/#D9A545, Alarm #A93227/#E5776A.
- render() = Theme, Hero, aktueller Tab, Logo, Plus-Knopf.

## 15. Filter (state.flt, fltMatch, fltCount, fltLabel, statKey)

- Schlüssel (statKey): Kategorie (leer → «Sonstiges»); Vertragspartner getrimmt (leer → «Ohne Namen»).
- Treffer (fltMatch(c, ausser)): alle gesetzten Filter ausser der genannten Dimension müssen passen; Inhaber = Person ist unter den Inhabern.
- Anzahl (fltCount), Text (fltLabel: Werte mit « · »).
- Vorname (firstName): erstes Wort.
- Auswahlknopf (fselHtml): zeigt Wert oder Platzhalter; Inhabername > 12 Zeichen → nur Vorname.
- Namenskürzung für Personen-Chips (holderNamer(Liste, Breite)): fit = floor((Breite/(n+1) − 28)/8.2); ist ein Name länger als fit → nur Vornamen; kommen gleiche Vornamen vor → «Vorname N.» (Initiale des letzten Worts). Chips möglich (ok), wenn 2 ≤ n ≤ 4 und Gesamtlänge der Kurznamen ≤ floor(28 × Breite/361). In «Kosten» Breite 318.
- Filterleiste «Kosten» (statFilterBar): Personen = Inhaber mit ≥ 1 Vertrag (+ aktuell gefilterte Person, falls nicht dabei).
  - ≤ 1 Person: eine Zeile «Kategorie» | «Vertragspartner» (+ «×» zum Zurücksetzen, wenn eins aktiv). ⚠ Fund N8.
  - Chips möglich: Zeile «Alle» | Personen (Kurznamen) | Filter-Knopf (drei Striche, Zähler-Badge = Anzahl aktiver Kategorie/Vertragspartner-Filter).
  - sonst: Auswahlknopf «Alle Inhaber» + Filter-Knopf.
  - Zweite Zeile «Kategorie» | «Vertragspartner» (+ «×»), sichtbar wenn aufgeklappt (fMore) oder ein solcher Filter aktiv.
- Auswahlblatt Filter (openPick(cat|partner|holder)): Titel «Kategorie»/«Vertragspartner»/«Inhaber»; erste Zeile «Alle Kategorien»/«Alle Vertragspartner»/«Alle Inhaber»; danach alle Werte aus allen Verträgen (auch archivierten) mit rechts «n aktiver Vertrag»/«n aktive Verträge» oder «nur beendete». Sortierung: Kategorie nach catList-Reihenfolge (unbekannte hinten), sonst alphabetisch de-CH ohne Gross/Akzent. Hinweis unten «Lange drücken zeigt die Beträge».

## 16. Pop-up bei langem Drücken (showLpop, Gestenlogik)

- Auslösen: Finger 450 ms auf einem Filterwert im Auswahlblatt (Kategorie/Vertragspartner/Inhaber); Bewegung > 10 px bricht ab; während des Drückens leicht verkleinert (98 %). Kontextmenü des Systems unterdrückt. Der Klick beim Loslassen wird geschluckt (kein Auswählen). SwiftUI: `.contextMenu` mit Preview oder LongPressGesture(minimumDuration 0.45).
- Inhalt: Titel = Wert, rechts «<HW>/Mt.», Knopf «×» («Schliessen»). Zeilen: aktive Verträge dieses Werts, absteigend nach monthlyCost: Logo, Titel + « · Anteil x %» (nur bei Inhaber und gemeinsamem Vertrag) + « · pausiert», Betrag = monthlyCost × Anteil. Pausierte grau, nicht in Summe. Leer: «Keine aktiven Verträge.» Fuss: «Total pro Monat» | «<Summe> <HW>». Darunter «n beendeter Vertrag/beendete Verträge nicht mitgezählt».
- Schliessen: «×» oder Tippen ausserhalb (dieser Tipp löst sonst nichts aus, 800 ms Sperre). Im Pop-up scrollbar.

## 17. Tab «Kosten», Teil 1 (renderStat bis Diagramm)

- Jahr Y = state.year (Standard aktuelles Jahr); Zeitraum 01.01.–31.12. Y.
- Für jeden Vertrag (alle, auch archivierte; Grenzen via limitOf) jede Zahlung aus payments: Wert = conv(Betrag, Vertragswährung) × holderShare (Personenfilter).
  - Monatsbalken (nur Verträge, die alle Filter erfüllen): Summe, bezahlt (Datum < heute), offen (≥ heute), Positionen {Vertrag, Datum, Wert, Originalbetrag × Anteil, Anteil, Sonderzahlung}.
  - Aufteilung (Verträge, die alle Filter ausser der Aufteilungsdimension erfüllen): je Schlüssel statKey(c, sg) Jahres- und Monatssummen; sg = «cat» (Standard) oder «partner».
- Gewählter Monat sel (0–11, begrenzt). Automatische Wahl (einmalig, wenn autoSel gesetzt): hat der gewählte Monat 0 und das Jahr > 0 → nächster Monat (vorwärts, zyklisch) mit Summe > 0.
- Leer: gar keine Verträge → Leerseite emptyStat (ausserhalb, ohne Jahresleiste). Keine Zahlung im Jahr → Filterleiste + «Keine Zahlungen in <Y>» «Für dieses Jahr sind keine Zahlungen erfasst oder berechenbar.» (+ Hinweis).
- Hinweis (nur für vergangene Jahre, wenn nicht gekündigte Verträge ohne Beginn existieren): «n Vertrag hat keinen Vertragsbeginn und wird deshalb rückwirkend voll gezählt.» bzw. «n Verträge haben keinen Vertragsbeginn und werden deshalb rückwirkend voll gezählt.»
- Vorjahresvergleich: gleiche Rechnung für Y−1 (gleiche Filter und Anteile). Anzeige nur, wenn Vorjahr > 0 und kein gefilterter Vertrag ohne Beginn ist (auch archivierte zählen): |Δ| < 0.05 % → «±0 %», sonst «+x.x %»/«−x.x %» (1 Nachkommastelle, Punkt), Zustand up/down; sonst «—».
- Balkendiagramm: Max = grösster Monat (0 → 1). Ø-Linie (gestrichelt, Beschriftung «Ø») bei (Jahr/12)/Max, nur wenn Jahr ≠ 0. Je Monat ein Knopf mit zwei Segmenten: unten bezahlt (Höhe bezahlt/Max), oben offen (Höhe offen/Max); oberstes Segment mit runden Ecken. Farben: gewählter Monat bezahlt Teal voll, offen Text 72–78 %; übrige Monate bezahlt Teal 30–34 %, offen Text 12–14 %. Monate mit 0 → Zustand zero. Bedienungshilfe «Zahlungen pro Monat <Y>», je Balken «<Monat lang> <Y>: <Betrag> <HW>». Tippen wählt Monat (Handler ausserhalb).
- Monatsleiste darunter: Kurznamen; gewählter hervorgehoben, aktueller Monat (nur im laufenden Jahr) markiert «now».
