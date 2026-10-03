# Portierungs-Inventar r3 – index.html Z. 3010–3725

Zweck: Nachbau in SwiftUI mit identischem Verhalten. JS-Funktionsnamen in Klammern. Texte wörtlich in «». Masse: 1 pt = 0,3528 mm. Bekannte Fehler stehen in r3-findings.md (Fxx); wo der Nachbau bewusst abweichen sollte, steht «Swift: …».

Hilfsformate, die hier überall vorkommen (Definitionen ausserhalb des Abschnitts):
- `money(v)`: de-CH, genau 2 Nachkommastellen, Tausendertrennzeichen ’ (z.B. «1’234.50»).
- `fmtD(iso)`: «3. Oktober 2026» (Tag ohne führende Null, Monatsname ausgeschrieben, «März» mit ä); leer/ungültig → «—».
- `fmtShort(date)`: «03.10.26»; null → «—».
- `inDays(d)`: 0 «heute», 1 «morgen», ≤60 «in d Tagen», sonst Monate = round(d/30.44): <24 «in m Monat/Monaten», sonst «in y Jahr/Jahren» (y = round(d/365.25)).
- `noticeText(c)`: notice 0 → «»; Einheit k → «bis zum n. des Monats»; w → «n Woche/Wochen»; d → «n Tag/Tage»; sonst «n Monat/Monate».
- `CYCLE`: 1 «monatlich», 2 «alle 2 Monate», 3 «quartalsweise», 6 «halbjährlich», 12 «jährlich», 24 «alle 2 Jahre».
- `TERMS`: "" «jederzeit», p «Ende der Zahlungsperiode», m «Monatsende», q «Quartalsende», h «Halbjahresende», y «Jahresende», a «Ende Vertragsjahr».
- `toast(text)`: Kurzmeldung 2,4 s.
- `ask({title,text,ok,danger})`: Bestätigungs-Sheet, Abbrechen + OK-Knopf (rot bei danger), liefert Bool.

---

## 1. Vertragsformular: Sonderzahlungen, Sichern, Abbrechen (Z. 3010–3071)

### 1.1 Sonderzahlungen-Liste (`paintExtras`, Ende Z. 3010)
- Zeile pro Eintrag (nach Datum sortiert, aus `extrasOf`): links «<fmtD(date)>» + bei Notiz « · <Notiz>» + Tag «Gutschrift» (wenn Betrag < 0) + Tag «geplant» (wenn Datum > heute, orange); rechts Betrag fett «−» bei Gutschrift + money(|Betrag|) + « <Währung des Formulars>» (Gutschrift grün); Knopf «×» (aria «Entfernen») löscht den Eintrag sofort aus dem Entwurf.
- Währungswechsel im Formular malt Liste und Preisänderungen neu.

### 1.2 Sonderzahlung hinzufügen (`xAdd`, Z. 3013–3021)
- Felder: Datum (xDate), Betrag (xAmt, `parseNum`: Apostrophe entfernt, erstes Komma → Punkt), Notiz (xNote, getrimmt), Segment Zahlung/Gutschrift (`xKind` "pay"|"cr").
- Prüfungen in dieser Reihenfolge: kein Datum → Toast «Datum der Sonderzahlung fehlt»; Betrag fehlt oder ≤ 0 → «Betrag prüfen».
- Betrag = round(|a|·100)/100; gespeichert als negativ bei Gutschrift. Felder leeren, Liste neu, Toast «Sonderzahlung am <fmtD> vorgemerkt» bzw. «Gutschrift am <fmtD> vorgemerkt», Segment zurück auf Zahlung.

### 1.3 Sichern (`saveForm`, Z. 3025–3070)
Prüfungen (Reihenfolge):
1. Vertragspartner und Bezeichnung beide leer → «Bezeichnung fehlt».
2. Keine Kategorie → «Bitte eine Kategorie wählen», Kategorie-Feld in die Mitte scrollen und Kategorie-Auswahl öffnen.
3. Betrag fehlt oder < 0 → «Betrag prüfen» (0 ist erlaubt).

Gespeicherte Felder: partner (trim), label (trim), cat, amount (auf 2 Stellen gerundet), cur, cycle (Zahl), due (leer → heute), start, end (nur Modus «befristet», sonst ""), notice (parseNum oder 0), noticeU, renew (nur befristet), cancTerm (nur unbefristet), mand, noWatch, custNo, contrNo, holders (Kopie), payM, payA, cancF, cancUrl, trial, web, addr, tel, mail, note, color, logoId, logoBg, prices (Kopie), extras (bereinigt), docs, status (bisheriger oder "active"), cancelledAt (bisheriger oder ""), t (bisheriger oder jetzt).
- Swift: ALLE übrigen Felder des bestehenden Vertrags behalten (cancelPer, cancelledOn, keptFor, trialKept, paused, pausedAt, pausedUntil) – im Web gehen sie verloren (F1).

Nur bei neuem Vertrag:
- Ohne Logo und mit Vertragspartner: erstes anderes Vertragsobjekt mit gleichem Partnerschlüssel (`pkey`) und vorhandenem Logo-Blob → dessen logoId und logoBg (Standard «#FFFFFF») übernehmen.
- Bei mehr als einer Person und gesetzten Inhabern, die von `settings.lastHolders` abweichen → lastHolders = diese Inhaber.
- Danach, wenn immer noch kein Logo und Partner oder Bezeichnung vorhanden: Hintergrund-Logosuche (`autoAttach`), die ein Logo ohne Rückfrage setzt und «Logo für «<Name>» ergänzt» meldet. Swift: als Vorschlag mit Bestätigung umsetzen (Produktprinzip, F9).
- Abschluss: alle Sheets schliessen, neu zeichnen, Toast «Aktualisiert» bzw. «Vertrag angelegt».

### 1.4 Abbrechen (`cancelForm`, Z. 3071)
- Ist die Unterseite «Weitere Angaben» offen → zurück zur Hauptseite (Knopf heisst dort «Zurück»); sonst Sheet schliessen (Knopf «Abbrechen»).

### 1.5 Uploads (Z. 3073–3087)
- «Logo hochladen» (logoUp): Ziel = Vertrag, Dateiauswahl (Bild) → Zuschneiden (§2). Dieselbe Dateiauswahl wird für Vertragspartner (Ziel «p»), Einnahme («i») und Personenbild («h») genutzt.
- «Logo entfernen» (logoDel): logoId leeren (logoBg bleibt).
- «Dokument anhängen» (docUp): Datei → Toast «Lade Datei…» → im Gerätespeicher ablegen → Eintrag {id, name (Dateiname), type (MIME oder aus Endung geraten)} → Liste neu, «Angehängt»; Fehler «Upload fehlgeschlagen». Nicht verfügbar, wenn kein Speicher (Knopf ausgeblendet).

---

## 2. Logo zuschneiden (Z. 3089–3199)

### 2.1 Ansicht (#sheetCrop)
- Titel «Logo zuschneiden», bei Personenbild (Ziel «h») «Bild zuschneiden».
- Hinweis «Mit einem Finger verschieben, mit zwei Fingern oder dem Regler zoomen. So sieht die Kachel später aus.»
- Vorschau: Quadrat, Breite min(280 pt, 74 % Bildschirmbreite), Ecken 22 % Radius, 1-px-Rand + weicher Schatten.
- Zoom-Regler 0…100, Schritt 1, links «−», rechts «+».
- «Hintergrund»: drei Chips mit Farbpunkt: «Automatisch» (erkannte Farbe), «Weiss» (rgb 255,255,255), «Schwarz» (rgb 0,0,0); gewählter Chip hervorgehoben.
- Knöpfe: «Übernehmen» (primär), «Automatisch einpassen», «Abbrechen».

### 2.2 Bild laden (`openCrop`)
1. Bild dekodieren; Fehler → «Bild konnte nicht gelesen werden».
2. Auf max. 1600 px lange Seite verkleinern (nie vergrössern), min. 1 px; ohne Mass 512×512 annehmen.
3. Analysekopie mit max. 500 px langer Seite (`analyze`):
   - Vier Eckpixel. Hintergrund «transparent», wenn ≥ 2 Ecken Alpha < 30 → Hintergrundfarbe Weiss. Sonst Mittelwert der vier Ecken (je Kanal gerundet).
   - Inhaltsrahmen: alle Pixel mit Alpha > 30 (transparent) bzw. Alpha > 30 und |ΔR|+|ΔG|+|ΔB| > 48 zur Hintergrundfarbe; Bounding-Box; keine Treffer → ganzes Bild.
   - Box auf Originalmassstab zurückrechnen (÷ Skalierung).
4. Hintergrundmodus «Automatisch», Ansichtsbreite V = tatsächliche Breite der Vorschau (Standard 280).
5. Automatisch einpassen (`cropAutoFit`): kAuto = V·0,74 / max(Box-Breite, Box-Höhe) (Inhalt füllt 74 % der Kachel), Zoom = kAuto, Mittelpunkt = Box-Mitte, Regler = 50.

### 2.3 Darstellung (`renderCrop`)
- Fläche S×S mit Hintergrundfarbe füllen; Bild skaliert mit k·S/V so zeichnen, dass Bildpunkt (cx, cy) in der Kachelmitte liegt; hohe Interpolationsqualität.

### 2.4 Gesten
- Regler ↔ Zoom: k = kAuto · 2^((v−50)/25); v = clamp(0…100, 50 + 25·log2(k/kAuto)). Bereich kAuto/4 … kAuto·4.
- Ein Finger: cx −= dx/k, cy −= dy/k (Bild folgt dem Finger).
- Zwei Finger: k ← k · Abstand/vorheriger Abstand, begrenzt auf Reglerbereich, Regler nachführen (Zoom um die Kachelmitte, nicht um den Pinch-Mittelpunkt).
- Mausrad: Regler −= deltaY·0,08.
- SwiftUI: DragGesture + MagnificationGesture, Slider.

### 2.5 Übernehmen (`cropOk`)
- Ohne Speicher: «Hochladen ist in dieser Ansicht nicht verfügbar».
- Ausgabe 512×512 px PNG mit gewähltem Hintergrund; Toast «Speichere Logo…».
- Ziel «h» (Person): Personenbild setzen, Sheet zu, «Bild gesetzt». Ziel «p» (Vertragspartner-Seite), «i» (Einnahme), sonst Vertrag: logoId + logoBg (als «rgb(r,g,b)»-Text!) setzen, Vorschau neu, «Logo gesetzt». Fehler «Upload fehlgeschlagen» bzw. «Bild konnte nicht erzeugt werden».
- Achtung Datenformat: logoBg ist mal «#FFFFFF», mal «rgb(…)». Swift: als Farbe (RGB) speichern, beim Import beide Formate parsen.
- Abbrechen: Sheet zu, Bild verworfen.

---

## 3. Dokumente ansehen (Viewer, Z. 3201–3281)

### 3.1 Typen (`guessType`, `isPdf`)
- Endung .pdf → application/pdf, .png, .jpg/.jpeg, .webp → Bildtypen, sonst unbekannt. Gespeicherter MIME-Typ hat Vorrang.

### 3.2 Aufbau (#viewer, Vollbild über allem)
- Kopfleiste (3 Spalten): links Zurück-Knopf mit Chevron und Text «Schliessen» (Dokument) bzw. «Zurück» (erzeugter Brief); Mitte Titel (fett, einzeilig, abgeschnitten): Titel oder Dateiname oder «Dokument».
- Inhalt grau (sunken), Seiten als weisse «Papier»-Blätter, max. Breite 100 %, Radius 6, Schatten, Abstand 14 pt.
- Aktionsleiste unten (gleich breite Kacheln mit Symbol + Text): «Text ändern» (nur erzeugter Brief), «Als E-Mail-Text» (nur wenn Mail-Daten vorhanden = Brief und nicht Miete), Hauptknopf (teal) «PDF teilen» (Brief) bzw. «Teilen».

### 3.3 Laden (`openDoc`)
- Sofort «Wird geladen…».
- Datei nicht auf dem Gerät: «Diese Datei ist auf diesem Gerät nicht vorhanden. Spiele ein Backup mit Dateien ein oder hänge sie neu an.»
- Bild: anzeigen; Fehler «Das Bild konnte nicht geladen werden.»
- PDF: alle Seiten untereinander, Breite = min(Inhaltsbreite − 28, 900) pt, Auflösung × min(2, Bildschirmskalierung), höchstens 40 Seiten; mehr → «Weitere <n> Seiten — mit «Teilen» vollständig öffnen.»
- PDF-Fehler: erzeugter Brief → «Die Vorschau braucht beim ersten Mal eine Internetverbindung. Senden, Drucken und Sichern funktionieren trotzdem über die Knöpfe unten.»; Dokument → «Das PDF lässt sich hier nicht anzeigen. Tippe auf «Teilen», dann öffnet es sich in der Dateien-App.»
- Andere Typen: «Für diesen Dateityp gibt es keine Vorschau. Tippe auf «Teilen».»
- Wird währenddessen ein anderes Dokument geöffnet oder geschlossen, wird das ältere Laden verworfen.
- Swift: PDFKit/QuickLook statt pdf.js (offline, kein 40-Seiten-Limit).

### 3.4 Knöpfe
- Schliessen: Viewer zu, Inhalt leeren.
- «Text ändern»: Viewer schliessen → Briefformular liegt mit allen Eingaben darunter.
- «Teilen» (`shareCur`): Datei an Teilen-Menü (Mail, Drucken, In Dateien sichern). Dateiname = name; ohne Endung + «.pdf» bzw. «.jpg». Abbruch durch Nutzer still, sonst «Teilen fehlgeschlagen»; ohne Funktion «Teilen ist in dieser Ansicht nicht verfügbar». Swift (laut Doku vorgemerkt): eigene Knöpfe Mail mit Anhang (MFMailComposeViewController) und Drucken (UIPrintInteractionController) + ShareLink.
- «Als E-Mail-Text»: Text in die Zwischenablage, Toast «Text kopiert, Mail wird geöffnet» (mit Empfänger) bzw. «Text kopiert. Empfänger in Mail eintragen» (ohne), nach 0,5 s mailto: an E-Mail des Vertrags, Betreff = Briefbetreff, Text = Mailtext (§4.9). Zwischenablage nicht möglich → Mail direkt öffnen.

---

## 4. Kündigungsschreiben (Z. 3282–3552)

### 4.1 Kündigungsweg (`CANC_VIA`, `cancVia`, `cancLink`)
- cancF-Text → Weg: «Online / Kundenkonto» → online; «E-Mail» → mail; «Brief» und «Einschreiben» → post.
- Ohne cancF: Miete (`isRent`) oder Kategorie «Versicherung» → post; sonst offen ("").
- Link für Online = cancUrl, sonst web; ohne «http(s)://» wird «https://» vorangestellt.
- Swift: cancF als Enum (Doku), bei Miete immer post (F3).

### 4.2 Miete erkennen (`isRent`)
- Text = Bezeichnung + « » + Vertragspartner. Miete, wenn Text (ohne Gross/Klein) «miete», «mietvertrag», «wohnungsmiete» oder «untermiete» enthält, ODER Kategorie = «Wohnen» und Text enthält «wohnung», «zimmer», «apartment», «vermiet», «verwaltung» oder «immobilien».
- Bekannte Lücken siehe F3 (z.B. «Mietzins» wird nicht erkannt). Swift: Heuristik nur als Vorbelegung eines expliziten Schalters.

### 4.3 Standard-Unterzeichner (`ltDefaultSigners`)
- H = alle Personen (Einstellungen + alle in Verträgen/Einnahmen vorkommenden Inhaber, Reihenfolge Einstellungen zuerst).
- Vorbelegung = Inhaber des Vertrags, die in H sind; keine → bei genau einer Person diese, sonst leer.

### 4.4 Brief-Bausteine (`letterParts(c, signers)`)
- Pro Unterzeichner: Name = «Vorname Nachname» aus dem Absender (Person, `same` = Adresse einer anderen Person übernehmen) oder, wenn leer, der Personenname; Adresse = [Strasse, «PLZ Ort», Land] ohne leere Zeilen; Ort.
- Absenderblock: Unterzeichner mit identischen Adresszeilen werden gruppiert. Je Gruppe eine Zeile «Name1 und Name2 …», dann deren Adresszeilen. Gesamtblock auf 7 Zeilen gekürzt (F12).
- Empfänger: Adresszeilen aus c.addr, sonst Adresse der Vertragspartner-Gruppe (gleicher Name ohne Gross/Klein); Zeilen getrimmt, leere entfernt. Der Vertragspartnername wird als erste Zeile vorangestellt, ausser die erste Adresszeile enthält ihn schon (ohne Gross/Klein, Teilstring).
- Referenzen: «Kundennummer: <custNo>», «Vertragsnummer: <contrNo>» (nur vorhandene).
- Wir-Form, wenn mehr als ein Unterzeichner.
- Text (wörtlich, \n = Zeilenumbruch):
  - «Sehr geehrte Damen und Herren\n\nhiermit kündige ich den oben genannten Vertrag ordentlich zum nächstmöglichen Termin, nach meiner Berechnung zum <fmtD(termEnd)>.\n\nBitte bestätigen Sie mir die Kündigung und das Vertragsende schriftlich.\n\nFreundliche Grüsse»
  - Wir-Form: «kündigen wir», «nach unserer Berechnung», «bestätigen Sie uns».
  - Ohne berechenbares Vertragsende entfällt «, nach meiner Berechnung zum …» (Satz endet nach «Termin»).
- Betreff: «Kündigung <Bezeichnung oder Vertragspartner>» + « bei <Vertragspartner>», wenn beide vorhanden (F14: bei Gleichheit doppelt).
- Ort (Datumszeile) = Ort des ersten Unterzeichners.
- Frist = noticeDeadline(c).
- Textfeld-Inhalt (`ltBodyText`): Referenzzeilen (je Zeile) + Leerzeile + Text; ohne Referenzen nur Text.

### 4.5 Sheet-Aufbau (#sheetLetter, über dem Detail)
Kopf: links «Schliessen», Mitte «Kündigung», rechts «PDF». Darunter:
1. «Wer kündigt?» (nur ab 2 Personen): genau 2 Personen → Chips «A» | «B» | «Beide» (Einzelwahl; «Beide» aktiv, wenn beide gewählt). Ab 3 → ein Chip je Person, Mehrfachauswahl (Reihenfolge immer wie Personenliste).
2. Absenderzeile (klein): ohne Auswahl «**Wer kündigt?** Bitte oben wählen.»; sonst «**Absender:** <Absenderzeilen mit «, » verbunden>»; fehlt bei gewählten Personen die Adresse (Kriterium: Vor- oder Nachname UND Strasse UND Ort), zusätzlich orange Zeile «Adresse fehlt: <Name> ergänzen, …» – jeder Name ist ein Link zur Absender-Seite der Person.
3. «Empfänger» (mehrzeilig, Platzhalter «Firma AG / Strasse Nr. / PLZ Ort», min. ~92 pt hoch) mit Knopf «Adresse suchen» und Statustext daneben («Keine Adresse hinterlegt», wenn Empfänger ≤ 1 Zeile).
4. «Fehlt noch — wird beim Vertrag gespeichert» (nur wenn Kunden- oder Vertragsnummer fehlt): Felder «Kundennummer» / «Vertragsnummer» (nur die fehlenden), beim Öffnen leer.
5. «Betreff» (einzeilig).
6. «Text» (mehrzeilig, min. 260 pt, 15 pt Schrift, Zeilenhöhe 1,45, Rechtschreibprüfung an).
7. «Unterschrift»:
   - Miete: Hinweiskasten (orange getönt) «Mietvertrag: PDF ausdrucken, von Hand unterschreiben (alle Mieter) und per Post senden, am besten eingeschrieben. Eine eingefügte Unterschrift oder eine E-Mail genügt hier nicht.» – «(alle Mieter)» nur bei > 1 Unterzeichner.
   - Sonst je Unterzeichner: Name (fett, klein), weisse Box 72 pt hoch mit Unterschriftbild (max. 60 pt hoch, 90 % breit) oder Text «Keine Unterschrift · Linie bleibt frei»; Knöpfe «Zeichnen», «Vorschläge», «Entfernen» (nur wenn vorhanden). Darunter «Jede Person unterschreibt selbst.». Ohne Auswahl: «Zuerst oben wählen, wer kündigt.»
8. Hinweiszeile (`ltHint`), Sätze mit Leerzeichen verbunden, in dieser Reihenfolge:
   - Wenn Frist berechenbar: «Spätester Absendetermin nach hinterlegter Frist: <fmtD>.» (inhaltlich falsch, F4 – Swift: «Muss spätestens am <fmtD> beim Vertragspartner sein.»)
   - Vertrag hat > 1 Inhaber und weniger Unterzeichner als Inhaber: «Gemeinsamer Vertrag: In der Regel müssen alle Vertragsparteien kündigen.»
   - Miete: «Mietverträge verlangen Schriftform mit eigenhändiger Unterschrift (CH Art. 266l OR, DE § 568 BGB).» und bei < 2 Unterzeichnern zusätzlich «Familienwohnung in der Schweiz: Ehe- oder eingetragene Partner müssen ausdrücklich zustimmen, am besten mitunterschreiben (Art. 266m OR).»
   - Immer: «Vorlage ohne Gewähr. Prüf Adresse, Frist und die im Vertrag verlangte Form.»

### 4.6 Verhalten
- Öffnen (`openLetter`): Felder aus letterParts mit Standard-Unterzeichnern füllen; Sheet nach oben scrollen. Swift: Vertrag frisch aus dem Speicher lesen (F2).
- Wechsel der Unterzeichner (`ltSetSigners`): Text nur ersetzen, wenn er noch exakt dem zuletzt automatisch gesetzten Text entspricht (`ltAuto.body`); Empfänger und Betreff bleiben unverändert; Absender, Unterschriften, Hinweise neu.
- Rückkehr von Absender-/Unterschrift-Seiten (`ltRefresh`) zeichnet Absender/Unterschriften/Hinweise neu, wenn der Brief offen ist.
- Schliessen (`closeLetter`): Sheet zu; Abdunklung weg, wenn kein anderes Sheet offen.

### 4.7 Adresse suchen (`findAddresses`, `addrWikidata`, `addrOsm`, Z. 3418–3468)
- Statustext «Suche …». Name = Vertragspartner oder Bezeichnung; offline oder leer → keine Treffer.
- Parallel:
  - Wikidata: Suche (bis 6 Treffer, de). Je Treffer offizielle Website (P856); ist am Vertrag eine Domain hinterlegt und hat der Treffer Websites, die alle nicht zur selben registrierbaren Domain (letzte zwei Labels) passen → verwerfen. Nur Treffer mit Strasse (P6375) zählen; PLZ P281; Sitz P159 → Ortsname (de, sonst en). Zeilen: [Label, Strasse, «PLZ Ort»], Quelle «Wikidata».
  - OpenStreetMap/Nominatim: bis 6 Treffer, Länder nach Währung (EUR → de,at,ch; sonst ch,de,at). Name des Objekts muss alle Suchwörter enthalten (`nameHas`); Strasse + Hausnummer und PLZ Pflicht. Zeilen: [Name, «Strasse Nr», «PLZ Ort»], Quelle «OpenStreetMap · <Typ>».
- Doppelte (gleiche Zeilen ab Zeile 2) entfernen, höchstens 5.
- Keine Treffer: «Keine Adresse gefunden — bitte von der Website oder Rechnung übernehmen.»
- Treffer: Auswahl-Sheet «Adresse wählen» über dem Brief, je Kandidat Zeilen untereinander + Quelle klein; Fussnote «Quellen: Wikidata und OpenStreetMap, ohne Gewähr. Bei mehreren Standorten den Hauptsitz oder Kundendienst wählen.» Tipp → Zeilen ins Empfängerfeld, Auswahl zu, «Adresse eingesetzt — bitte prüfen». (Gleiche Auswahl auf der Vertragspartner-Seite: Adresse übernehmen, «Adresse übernommen, bitte prüfen».)

### 4.8 «PDF» (Z. 3529–3552) – Reihenfolge
1. Kein Unterzeichner → «Bitte wählen, wer kündigt», zu «Wer kündigt?» scrollen.
2. Empfänger = Zeilen getrimmt, leere weg; leer → «Empfänger fehlt», Fokus Empfänger.
3. Betreff leer → Standardbetreff. Text (getrimmt) leer → «Der Text ist leer».
4. Empfängeradresse am Vertrag speichern: erste Zeile weglassen, wenn sie (ohne Gross/Klein) exakt dem Vertragspartner entspricht; Rest mit Zeilenumbruch. Wenn anders als gespeichert → am Vertrag speichern und, falls nicht leer, auf alle Verträge desselben Vertragspartners übertragen (`setPartnerAddr`).
5. Referenzen: führende Textzeilen, die mit «Kundennummer: » oder «Vertragsnummer: » beginnen, werden aus dem Text gelöst. Eingetragene «Fehlt noch»-Werte werden am Vertrag gespeichert (nur wenn dort leer) und als Referenzzeile angehängt. Swift: Referenz immer einsetzen, wenn Wert eingegeben und noch nicht vorhanden (F2).
6. Empfänger nur 1 Zeile → ask «Ohne Empfängeradresse?» / «Im Anschriftfeld steht nur der Name. Für den Postversand fehlt die Adresse.» / OK «Trotzdem erstellen»; Abbruch → Ende.
7. Unterzeichner ohne vollständige Adresse → ask «Absender unvollständig» / «Bei <A und B> fehlt die Adresse. Der Anbieter kann die Kündigung so schlechter zuordnen.» / «Trotzdem erstellen».
8. PDF erzeugen (§5) mit: Absender, Empfänger, Ort, Betreff, Referenzen, Text (ohne Referenzzeilen), Namen, Unterschriften (bei Miete keine). Fehler → «PDF konnte nicht erstellt werden».
9. Dateiname «Kuendigung-<Vertragspartner|Bezeichnung|«Vertrag»>-<YYYY-MM-DD>.pdf», alle Zeichen ausser A–Z a–z 0–9 _ - werden zu «_» (Folgen zu einem). Swift: Umlaute transliterieren (F14).
10. Viewer öffnen: Titel «Kündigung · <Vertragspartner|Bezeichnung|«Vertrag»>», Mail-Daten nur wenn keine Miete.

### 4.9 Mailtext (für «Als E-Mail-Text»)
- Blöcke mit Leerzeile getrennt (leere Blöcke weg): Referenzzeilen; Text; Namen (je Zeile) + bei mehr als einer Absenderzeile die Absenderzeilen ab der zweiten.
- Empfänger = E-Mail beim Vertrag (getrimmt, darf leer sein), Betreff = Betreff.

---

## 5. PDF-Brief (`letterPdf`, Z. 3469–3528)

Seite A4 595 × 842 pt (209,9 × 297,0 mm). Schriften Helvetica (normal) und Helvetica-Bold, Kodierung WinAnsi. Alle Positionen unten als Grundlinie, gemessen von der Blattoberkante (PDF-intern y = 842 − Wert).

| Element | Schrift | x | Grundlinie ab oben | Zeilenschritt |
|---|---|---|---|---|
| Absender (max. 7 Zeilen) | 9,5 pt normal | 71 pt (25,0 mm) | 57 pt (20,1 mm) | 12 pt (4,23 mm) |
| Anschrift (beliebig viele Zeilen) | 11 pt normal | 71 pt | 142 pt (50,1 mm) | 15,5 pt (5,47 mm) |
| Ort, Datum | 11 pt normal | rechtsbündig an 524 pt | 255 pt (90,0 mm) | – |
| Betreff (umbrochen) | 11 pt fett | 71 pt | 298 pt (105,1 mm) | 15,5 pt |

- Satzspiegel: links 71 pt, rechts 524 pt (Rand 71 pt = 25 mm), Satzbreite 453 pt (159,8 mm); unterste zulässige Grundlinie 70 pt über Blattunterkante (24,7 mm); Folgeseiten beginnen mit Grundlinie 70 pt unter Oberkante (y=772). Keine Kopf-/Fusszeile, keine Seitenzahlen.
- Ort-Datum-Text: «<Ort>, <fmtD(heute)>» bzw. nur Datum ohne Ort.
- Ablauf ab Betreff (Cursor y): Betreffzeilen; Abstand 0,6 × 15,5 = 9,3 pt; Referenzzeilen (je eine Zeile, nicht umbrochen); falls vorhanden Abstand 9,3 pt; Text.
- Text: «\r» entfernen; Absätze an 2+ aufeinanderfolgenden Zeilenumbrüchen; innerhalb eines Absatzes jede Zeile einzeln umbrochen; nach jedem Absatz 0,8 × 15,5 = 12,4 pt Abstand. Leere Einzelzeile = 15,5 pt.
- Zeilenumbruch (`pdfWrap`): an Leerzeichen, gierig; ein Wort kommt in die Zeile, solange die geschätzte Breite ≤ 453 pt ist; erstes Wort immer (kein Trennen langer Wörter, F10). Breite = Summe AFM-Breiten/1000 × 11 pt; ASCII 32–126 aus Helvetica- bzw. Helvetica-Bold-AFM, alle anderen Zeichen 556.
- Seitenumbruch: vor jeder Textzeile, wenn Cursor-Grundlinie unter 70 pt (von unten) läge → neue Seite, Cursor auf 772.
- Unterschriftenblock:
  - Spaltenbreite colW = min(220 pt, 453/n), Linien-/Bildbreite lw = min(170 pt, colW − 20); n = Anzahl Unterzeichner. Spalte i beginnt bei x = 71 + i·colW.
  - Vorher: wenn y − (46 + 2·15,5) < 70 → neue Seite.
  - Mit Bild: auf Höhe 46 pt (16,2 mm) skaliert, wenn dadurch breiter als lw → Breite lw, Höhe proportional; Bild-Unterkante bei y − 42 (unten bündig).
  - Ohne Bild (auch immer bei Miete): Linie 0,5 pt, Grau 45 %, von x bis x+lw auf Höhe y − 44.
  - Name: 11 pt normal, x, Grundlinie y − 57 (nicht umbrochen).
- Zeichenvorrat: ASCII und Latin-1 160–255 direkt; zusätzlich € ‚ ƒ „ … † ‡ ˆ ‰ Š ‹ Œ Ž ‘ ’ “ ” • – — ˜ ™ š › œ ž Ÿ; alles andere wird «?» (F5). Swift (UIGraphicsPDFRenderer + Systemschrift) hat diese Grenze nicht – Helvetica/Helvetica Neue mit vollen Unicode-Glyphen verwenden.
- Bilder: JPEG unverändert eingebettet (DCT, RGB, 8 bit), Grösse aus dem JPEG-SOF gelesen. Nicht lesbares Bild → wie «keine Unterschrift».
- Swift-Hinweise: UIKit zeichnet Text ab Oberkante der Zeile; Grundlinie = origin.y + font.ascender → origin.y = Grundlinie − ascender. Zeilenschritt 15,5 pt fest setzen (NSParagraphStyle minimum/maximumLineHeight), Umbruch über NSString-Messung (identische Ergebnisse sind wegen anderer Schriftmetriken nicht garantiert; wichtiger sind die Positionen der Blöcke).

---

## 6. Unterschrift zeichnen (Z. 3354–3381)

Datenmodell: settings.sigs = {Personenname: JPEG-Data-URL}; leer = keine. Swift: Data (JPEG/PNG) an Person-Entität.

### 6.1 Sheet (#sheetSig, über dem Brief)
- Kopf: «Abbrechen» | «Unterschrift» | «Übernehmen».
- Hinweis «Mit dem Finger auf der Linie unterschreiben, am besten im Querformat.»
- Feld: volle Breite, 200 pt hoch, weiss, Radius 14, 1-px-Innenrand; gestrichelte Hilfslinie (#b9b9b9) 48 pt über Unterkante, 24 pt Abstand links/rechts.
- Knopf «Löschen» (Feld weiss, nichts gezeichnet).

### 6.2 Zeichnen
- Strich 2,4 pt, Farbe #1b1e23, runde Enden und Ecken, Linie von letzter zu aktueller Fingerposition. Ein Tipp ohne Bewegung zählt nicht. Auflösung × min(2, Bildschirmskalierung).
- Swift: PencilKit (PKCanvasView) mit .pen #1b1e23, Breite ~2,4; auf Grösse/Drehung reagieren (F6), nur ein Finger (F13).

### 6.3 Übernehmen (`sigFromCanvas`)
- Nichts gezeichnet → «Bitte zuerst unterschreiben».
- Zuschnitt: Bounding-Box aller Pixel mit Rotanteil < 200, plus 12 px Rand (Bitmap-Pixel, auf Bildgrenzen begrenzt); keine Pixel → «Nichts gezeichnet».
- Weisser Hintergrund, JPEG Qualität 0,85. Speichern für die Person, Sheet zu, Brief/Personenseite neu, «Unterschrift gespeichert».
- «Entfernen» (überall, wo angeboten): sofort löschen, «Unterschrift entfernt» (keine Rückfrage).

## 7. Namenszug-Vorschläge (Z. 3382–3417)

### 7.1 Sheet (#sheetSigPick)
- Kopf: «Abbrechen» | «Namenszug» | (leer).
- Hinweis «Tippe auf einen Vorschlag. Üblich sind voller Name, Initial mit Nachname oder nur der Nachname.»
- Beim Öffnen «Vorschläge werden erstellt …»; wartet bis alle 6 Schriften geladen sind, höchstens 2,5 s.
- Je Vorschlag eine Kachel (weiss, 84 pt hoch, Radius 12): Bild (max. 64 pt hoch, 72 % breit) links, Beschriftung klein rechts.
- Fussnote «Am echtesten ist «Zeichnen» mit dem Finger. Für Mietverträge gilt nur die Unterschrift von Hand auf Papier.»
- Tipp → als Unterschrift der Person speichern, Sheet zu, «Namenszug übernommen».

### 7.2 Namen
- Vor-/Nachname aus dem Absender der Person; beide leer → Personenname an Leerzeichen trennen (erstes Wort Vorname, Rest Nachname); immer noch leer → «Zuerst den Namen beim Absender erfassen», kein Sheet.
- Formen: 0 = «Vorname Nachname» (getrimmt), 1 = «V. Nachname» (Initiale + Punkt + Leerzeichen; ohne Vorname nur Nachname), 2 = Nachname, sonst Vorname. Leere Texte entfallen. (F14: ohne Nachname ergibt Form 1 nur «V.».)

### 7.3 Varianten (`SIG_FONTS`) – Reihenfolge = Anzeige
| # | Schrift (OFL, lokal) | Startgrösse px | Beschriftung | Form | Schwung |
|---|---|---|---|---|---|
| 1 | Hurricane | 120 | «Voller Name» | 0 | nein |
| 2 | La Belle Aurore | 92 | «Initial + Nachname» | 1 | ja |
| 3 | Licorice | 116 | «Voller Name» | 0 | nein |
| 4 | Zeyada | 110 | «Nur Nachname» | 2 | nein |
| 5 | Qwigley | 128 | «Voller Name» | 0 | ja |
| 6 | Bilbo | 112 | «Initial + Nachname» | 1 | nein |

### 7.4 Rendering (`renderSig`, deterministisch)
- Zufall (`sigRand(seed)`, seed = Variantennummer 1…6): x0 = seed·9301 + 49297; je Aufruf x = (x·9301 + 49297) mod 233280, Ergebnis x/233280 (Int64 in Swift ergibt identische Werte). Aufrufreihenfolge exakt einhalten.
- Leinwand 1000 × 300 px, weiss. Tinte #1c2a52.
- Schriftgrösse px = Startgrösse; solange Textbreite > 860 und px > 40: px −= 6. tw = Textbreite bei finaler Grösse.
- Ursprung nach (50, 174) verschieben (174 = 0,58·300), drehen um −(0,02 + r()·0,035) rad (≈ −1,1° bis −3,2°), Grundlinie alphabetisch.
- Je Zeichen i: Verschiebung x = Breite des Präfixes text[0..<i], y = (r() − 0,5)·px·0,05; Skalierung (1 + (r() − 0,5)·0,05, 1 + (r() − 0,5)·0,07); Zeichen zeichnen. (Drei r()-Aufrufe pro Zeichen in dieser Reihenfolge.)
- Zweiter Durchgang: ganzer Text mit 35 % Deckkraft bei (0,8, 0,5).
- Schwung (nur 2 und 5): Strich Tinte, runde Enden, Breite max(2, px·0,035); y = px·0,22; Start (0,08·tw, y + 0,06·px), kubische Kurve mit Kontrollpunkten (0,35·tw, y + 0,16·px), (0,75·tw, y − 0,02·px) und Ende (1,04·tw, y − 0,12·px).
- Danach Zuschnitt + JPEG wie §6.3.

---

## 8. Logo aus Google holen / Einfügen (Z. 3553–3616)

### 8.1 «Logo suchen» (`logoSearch`)
- Name = Vertragspartner, sonst Bezeichnung (Einnahme: Name, sonst Bezeichnung); leer → «Zuerst den Firmennamen eintragen».
- Hinweis im Logo-Bereich: «**So geht’s:** In Google das passende Bild lange drücken → «Kopieren». Dann zurück in die App und «Einfügen» tippen.»; Knopf «Einfügen» pulsiert.
- Öffnet Google-Bildersuche «<Name> logo» (extern).
- Rückkehr in die App: versucht automatisch ein Bild aus der Zwischenablage zu lesen; Erfolg → Hinweis/Puls weg, Zuschneiden öffnen; sonst «Bild kopiert? Jetzt «Einfügen» tippen». Swift: Wartezustand beim Schliessen des Formulars zurücksetzen (F7); nativ eher PhotosPicker/Paste-Button (UIPasteControl).

### 8.2 «Einfügen» (`pasteLogo`)
- Hinweis/Puls entfernen. Keine Zwischenablage-API → «Einfügen wird hier nicht unterstützt – bitte hochladen».
- Erstes Bild in der Zwischenablage → Zuschneiden.
- Sonst Text, der genau eine http(s)-URL ist → «Lade Bild…» → über images.weserv.nl (Breite 1200, PNG) laden → Zuschneiden; Fehler «Bild-Link konnte nicht geladen werden».
- Sonst «Kein Bild in der Zwischenablage. In Google Bild lange drücken → «Kopieren».»
- Zugriff verweigert → «Zugriff auf die Zwischenablage nicht erlaubt – bitte «Einfügen» bestätigen oder hochladen».

### 8.3 Links öffnen (`openLink`)
- Öffnet URL in neuem Fenster/extern. (Rückfall «Kopiert: …» in die Zwischenablage ist im Web praktisch nie aktiv.) Swift: `openURL`; tel:/mailto: direkt.

---

## 9. Vertragsdetail (`openDetail`, Z. 3618–3725)

Datenbasis: Kopie des Vertrags mit id. Sheet #sheetDetail.

### 9.1 Kopf
- Leiste: links «Schliessen», Mitte Titel (Bezeichnung, sonst Vertragspartner, sonst «Ohne Namen»; erst ab 60 pt Scroll sichtbar), rechts «Bearbeiten».
- Kopfbereich: Logo-Kachel 76 × 76 pt, Radius 17 (Logo auf logoBg, sonst Kategoriefarbe + Kategoriesymbol) | Titel gross; darunter (13 pt, grau) Vertragspartner, wenn Bezeichnung vorhanden und ≠ Vertragspartner (ohne Gross/Klein).

### 9.2 Pillen (Zeile unter dem Kopf; ohne Pille 10 pt Abstand)
Bestimmung in dieser Reihenfolge (spätere überschreiben):
1. u = urgency(c): lvl alert → rot «Frist <inDays>», warn → orange «Frist <inDays>»; sonst wenn status «cancelled» → grau «Gekündigt» + « am <fmtD(cancelledAt)>» (falls vorhanden); sonst keine.
2. cancelPer gesetzt und status ≠ cancelled → «Gekündigt · läuft bis <fmtD(cancelPer)>»; sonst wenn «behalten» für den aktuellen Termin (keptFor = iso(termEnd)) → «Behalten bis nächster Termin».
3. Pausiert (paused und pausedUntil leer oder in der Zukunft) → «Pausiert bis <fmtD(pausedUntil)>» bzw. «Pausiert seit <fmtD(pausedAt oder heute)>».
4. Zusätzlich (angehängt): nächste künftige Preisänderung → orange «Neuer Preis ab <fmtD(from)>: <money> <Währung>».
- urgency: Frist = nDl(termEnd); Tage bis Frist; < 0 kein Level; ≤ 30 alert; ≤ 90 warn; sonst ok. Kein Level bei jederzeit kündbar (unbefristet mit Kündbar auf «p» oder «m»), noWatch, cancelPer oder behalten. Swift: zusätzlich bei status cancelled kein Level (F8).

### 9.3 Abschnitte (Zeilen «Bezeichnung links grau 12,5 pt | Wert rechts 14 pt», gruppierte Karte; Abschnitt entfällt ohne Zeilen)
**Kosten**
1. «Betrag»: «<money(aktueller Preis)> <Währung> · <CYCLE[Turnus] oder «monatlich»>»
2. «Ø pro Monat»: «<money(Monatskosten in Heimwährung)> <Heimwährung>» – entfällt bei Turnus 1 und Vertragswährung = Heimwährung.
3. «Pro Jahr»: «<money(Monatskosten·12)> <Heimwährung>»
4. «Nächste Zahlung»: fmtD(nächster Zahlungstermin) oder «—»

**Laufzeit & Kündigung**
1. «Beginn»: fmtD(start) – nur wenn gesetzt.
2. «Vertragsende»: fmtD(effektives Ende; bei Verlängerung auf das aktuelle Ende vorgerollt) – nur wenn end gesetzt.
3. «Kündigung»: noticeText oder «ohne Frist»; bei unbefristet zusätzlich « · auf <TERMS[cancTerm]>» bzw. « · jederzeit».
4. Wenn Frist berechenbar: jederzeit kündbar → «Nächste Gelegenheit»: «per <fmtShort(termEnd)>, kündigen bis <fmtShort(Frist)>»; sonst «Nächster Termin»: gleich + « (<inDays>)» bzw. « (abgelaufen)». Swift: bei cancelPer/archiviert weglassen (F8).
5. «Pflichtvertrag»: «nur Wechsel möglich» (mand).
6. «Frist»: «wird nicht beobachtet» (noWatch).
7. Verlängerung: mit Ende + Verlängerung → «Sonst verlängert bis»: fmtD(effektives Ende + renew Monate); nur renew → «Verlängerung»: «automatisch um <n> Monat/Monate».
8. «Kündigung per»: cancF-Text.
9. «Gekündigt am»: fmtD(cancelledOn) – nur wenn cancelPer und cancelledOn.
10. «Probeabo endet»: fmtD(trial).

**Zuordnung**
1. «Vertragspartner»: Link (teal, fett) «<Name> ›» → Vertragspartner-Seite (Rückkehr öffnet das Detail wieder).
2. «Kategorie», 3. «Inhaber» (mit « & » verbunden), 4. «Kundennummer», 5. «Vertragsnummer», 6. «Zahlungsart» (payM), 7. «Belastet über» (payA) – je nur wenn vorhanden.

**Kontakt** (nur wenn Website, Telefon oder E-Mail): Zeilen-Knöpfe «Website | <URL ohne http(s)://>», «Telefon | <Nummer>», «E-Mail | <Adresse>» (Wert rechts teal, einzeilig abgeschnitten). Tipp: Website → https-URL öffnen; Telefon → tel: ohne Leerzeichen; E-Mail → mailto:.

**Preisverlauf** (nur bei ≥ 1 Preisänderung): Stufendiagramm (`priceChart`, ausserhalb dieses Abschnitts) + Liste: erste Zeile «ab <fmtD(start)>» bzw. «Anfangspreis» mit Grundbetrag; danach je Änderung «ab <fmtD(from)>»; aktuelle Stufe (letzte mit from ≤ heute; keine → Anfangspreis) mit teal Balken links + Tag «aktuell»; künftige mit Tag «geplant» (orange). Rechts «<money> <Währung>».

**Sonderzahlungen**: wie §1.1, ohne Löschknopf.

**Notiz**: Text 14,5 pt, Zeilenumbrüche erhalten.

**Dokumente**: je Datei Zeile «📄 <Name>» (PDF) bzw. «🖼 <Name>» → Viewer (§3).

### 9.4 Knöpfe unten (Rahmen-Knöpfe volle Breite, Reihenfolge)
1. «Kündigung zurücknehmen» – nur wenn cancelPer. → cancelPer und cancelledOn leeren, «Kündigung zurückgenommen».
2. «Entscheid «Behalten» zurücksetzen» – nur wenn behalten. → keptFor leeren, «Wieder offen».
3. Kündigen-Knopf – nur wenn weder cancelPer noch status cancelled; Text/Aktion nach cancVia:
   - online: «Online kündigen» → kein Link → «Kein Link hinterlegt. Trag Website oder Kündigungslink ein.», Detail zu, Formular auf «Weitere Angaben». Sonst Toast «Nach der Kündigung hier bestätigen», merkt den Vertrag für die Rückfrage «Gekündigt?» bei Rückkehr in die App, öffnet den Link nach 0,35 s.
   - mail: «Per E-Mail kündigen» → ohne E-Mail ask «E-Mail-Adresse fehlt» / «Trag die Kündigungsadresse des Vertragspartners beim Vertrag unter «Kontakt» ein.» / «Eintragen» → Formular «Weitere Angaben». Sonst mailto an c.mail, Betreff aus letterParts (Standard-Unterzeichner), Text = Referenzen + Text + Namen (je Block Leerzeile), merkt Vertrag für «Gekündigt?». (Swift: bei Miete nicht anbieten, F3.)
   - post: «Kündigungsschreiben» → Brief (§4).
   - offen: «Kündigen …» → Auswahl «Wie kündigst du «<Titel>»?» mit «Online / Kundenkonto, Kündigungsbutton», «Per E-Mail / Mail mit fertigem Text», «Per Brief / PDF mit Unterschrift»; speichert cancF und löst den passenden Knopf aus (`openCancViaPick`, ausserhalb).
4. «Pausieren» bzw. «Fortsetzen» – nur wenn status ≠ cancelled. Fortsetzen: paused=false, pausedAt/pausedUntil leer, «Fortgesetzt». Pausieren → Dauer-Auswahl (`openPausePick`, ausserhalb).
5. Aufklappbereich «Weitere Aktionen»:
   - «Duplizieren» → Formular als Kopie (Titel «Duplizieren»; ohne Dokumente/Sonderzahlungen, Preise werden übernommen).
   - status cancelled: «Wieder aktiv setzen» → status active, cancelledAt leer, «Wieder aktiv»; sonst «Als gekündigt ins Archiv» → status cancelled, cancelledAt heute, «Ins Archiv verschoben».
   - «Vertrag löschen» (rot) → ask «Vertrag löschen?» / ««<Titel>» wird endgültig gelöscht. Angehängte Dateien bleiben erhalten.» / «Löschen» (rot) → löschen, «Gelöscht».
- «Bearbeiten» → Detail zu, nach 0,18 s Formular mit dem Vertrag. Alle Speicheraktionen schliessen danach die Sheets und zeichnen neu.
- Wischen nach unten (ab 90 pt, nur wenn ganz oben gescrollt) schliesst das Detail (Z. 3732 ff., knapp ausserhalb).
