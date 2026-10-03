# Portierungs-Inventar R5: index.html Z. 4435–5029

Ziel: Ein Swift-Entwickler soll das Verhalten 1:1 nachbauen können, ohne den JS-Code zu lesen. UI-Texte stehen wörtlich in «». Platzhalter für Werte stehen in <spitzen Klammern>; Guillemets innerhalb eines Textes gehören zum App-Text. JS-Namen stehen in Klammern. Verweise auf Helfer ausserhalb des Abschnitts sind markiert mit (ausserhalb).

Gemeinsame Helfer (ausserhalb, für das Verständnis nötig):
- `cntTxt(n, eins, mehrere)` → «n eins» bei n = 1, sonst «n mehrere» (z.B. «1 Vertrag», «3 Verträge»).
- `money(v)`: Zahl im Format de-CH mit 2 Nachkommastellen. `H0()`: Hauptwährung (`settings.home`).
- `mdSec(titel, rechts)`: Abschnittsüberschrift, rechts optional ein Link-Knopf. `mdEmpty(text)`: grauer Hinweisabsatz.
- `mdCRow(id,c)` → Vertragszeile: Logo/Marke; Titel (`label` || `partner` || «Ohne Namen»); darunter «Betrag WÄHRUNG · Turnus» (Turnus aus CYCLE, Standard «monatlich»), bei beendeten Verträgen zusätzlich «· beendet». Tipp öffnet den Vertrag.
- `holderStats()` → Liste {name, c (Anzahl Verträge), i (Anzahl Einnahmen)}. Reihenfolge: zuerst `settings.holders`, dann weitere Namen in der Reihenfolge, in der sie in Verträgen und Einnahmen vorkommen. Gezählt werden **alle** Verträge, auch gekündigte.
- `holdersOf(x)` → `x.holders`, sonst `[]`.
- `mapHolders(fn)`: wendet fn auf jeden Inhabernamen jedes Vertrags und jeder Einnahme an. `null` entfernt den Namen, Doppelte werden entfernt (erste Position bleibt). Zurück kommt die Anzahl geänderter Einträge.
- `sndRename(alt, neu)`: Absender, Unterschrift und Bild wandern zum neuen Namen. Hat das Ziel schon eigene Daten, bleiben diese, und die alten werden verworfen. Andere Personen mit «gleiche Adresse wie alt» zeigen danach auf neu. Ist das Ziel selbst so eine Person, bekommt es die Adresse als eigene Kopie.
- `sndDrop(name)`: Absender, Unterschrift und Bild-Zuordnung löschen. Wer «gleiche Adresse wie name» hatte, bekommt die Adresse als eigene Kopie.
- `catList()` → [{n Name, c Farbe, i Symbol-Schlüssel}]. Ohne gespeicherte Liste gilt die Vorbelegung CATS mit Standardfarbe, i = Name. `allCats()` = nur Namen. `catColor`/`catIcon` lesen aus dem Eintrag.
- Verwalten-Fenster = ein Sheet mit Navigationsstapel (`md.stack`). Seitentitel aus `mdTitle`: partner «Vertragspartner», holder «Inhaber», cat «Kategorien», qual «Datenqualität», hs «Absender», henew «Neuer Inhaber», cenew «Neue Kategorie», hassign «Verträge zuordnen», hbulk «Alle übertragen», pmerge «Zusammenführen», hdel «Inhaber löschen», cdel «Kategorie löschen». Sonst gilt `p.title`, `p.name`, `p.n` oder der Name des Vertragspartners. Der Zurück-Knopf trägt den Titel der Vorseite, bei mehr als 12 Zeichen «Zurück». Rechts steht «Fertig» und schliesst das Fenster. SwiftUI: NavigationStack in einem Sheet, Seiten als Enum.
- Speichern: `putContract`/`putIncome`/`saveSettings` schreiben sofort in den lokalen Speicher, `render()` zeichnet die Hauptansicht neu. `paintMd(0)` zeichnet die aktuelle Verwalten-Seite neu, ohne Animation.

---

## 1. Inhaber

### 1.1 Ende der Seite «Alle übertragen» (MD_PAGES.hbulk, nur Z. 4435)
- Unten fester Knopf «Übertragen» (Hauptknopf). Deaktiviert, solange kein Ziel gewählt ist oder die Quellperson 0 Einträge hat. Aktion siehe 1.8 «hbulk».

### 1.2 Neuer Inhaber (MD_PAGES.henew)
- Feld: Label «Name», Platzhalter «z.B. Lara», max. 30 Zeichen, Return-Taste «Fertig» (enterkeyhint done), kein Autocomplete.
- Knopf «Hinzufügen» (Hauptknopf). Enter im Feld löst denselben Knopf aus.
- Aktion (data-mdrun henew): Eingabe trimmen, Mehrfach-Leerzeichen zu einem zusammenfassen.
  - Leer → Toast «Bitte einen Namen eingeben».
  - Name existiert schon (Vergleich ohne Gross-/Kleinschreibung gegen `holderStats()`) → Toast «Diesen Inhaber gibt es schon».
  - Sonst ans Ende von `settings.holders` anhängen, speichern, render, eine Seite zurück, Toast «Inhaber «Name» angelegt».

### 1.3 Personenkarte (MD_PAGES.he), wie die iOS-Kontakte
Parameter: `name`, `edit` (Bearbeiten-Modus), `all` (alle Einträge zeigen).
- **Kopf (Karte):** Rechts oben der Link-Knopf «Bearbeiten» bzw. im Bearbeiten-Modus «Fertig». Darunter das grosse Bild (Foto oder Logo, sonst der erste Buchstabe gross).
  - Normal: Name als Überschrift, darunter «n Vertrag/Verträge» und, falls Einnahmen vorhanden, « · m Einnahme/Einnahmen». Gezählt wird über holderStats, also inkl. gekündigter Verträge.
  - Bearbeiten-Modus: Knopf «Foto oder Logo wählen» (ohne Bild) bzw. «Bild ändern» (mit Bild), mit Bild zusätzlich «Entfernen». Dazu das Feld Label «Name», Wert = aktueller Name, max. 30 Zeichen, Return «Fertig».
- **Abschnitt «Kündigungen»** (zwei Zeilen, beide öffnen die Seite «Absender» dieser Person):
  - «Absender»: Untertitel = «Vorname Nachname, Strasse, PLZ Ort» (leere Teile weggelassen), wenn der Absender vollständig ist. Vollständig heisst: Vor- oder Nachname, Strasse und Ort vorhanden; bei «gleiche Adresse wie X» zählt die Adresse von X. Sonst «Name und Adresse für Briefe». Rechts «✓» (grün) oder «ergänzen» (orange).
  - «Unterschrift»: Untertitel «hinterlegt» oder «ohne: Linie zum Unterschreiben von Hand». Rechts «✓» (grün) oder «optional».
- **Abschnitt Einträge:**
  - Titel bei vorhandenen Einträgen: «n Vertrag/Verträge», bei beiden Arten getrennt durch «, », dann «m Einnahme/Einnahmen». Ohne Einträge lautet der Titel «Verträge».
  - Rechts der Link «Zuordnen», nur bei mindestens 2 Personen. Er öffnet «Verträge zuordnen», gefiltert auf diese Person.
  - Liste: zuerst Verträge, sortiert nach Monatskosten in der Hauptwährung absteigend (`monthlyCost`, inkl. gekündigter Verträge), dann Einnahmen in alphabetischer Reihenfolge (de-CH, ohne Gross-/Kleinschreibung). Ohne `all` nur die ersten 4 und darunter der Knopf «Alle n zeigen» (n = Gesamtzahl), der `all` setzt.
  - Zeile: Logo (Vertrag) bzw. Einnahmen-Marke. Titel fett: bei Verträgen `label` || `partner` || «Ohne Namen», bei Einnahmen `label` || `name` || «Einnahme». Untertitel: bei Verträgen der Vertragspartner, wenn Bezeichnung und Partner vorhanden sind; bei Einnahmen «Einnahme». Gibt es weitere Inhaber, kommt «mit A, B» dazu (Teile mit « · » verbunden). Rechts der Betrag: bei Verträgen der aktuelle Preis (inkl. Preisänderungen), bei Einnahmen `amount`, jeweils mit der Währung des Eintrags. Tipp öffnet Vertrag oder Einnahme; das Verwalten-Fenster schliesst, nach 200 ms öffnet das Detail.
  - Leer: «Noch nichts zugeordnet.», bei mindestens 2 Personen zusätzlich « Über «Zuordnen» Verträge zuweisen.».
- **Bearbeiten-Modus unten:** roter Knopf «Inhaber löschen».

Aktionen:
- «Bearbeiten»/«Fertig» (hedit): zuerst offene Namenseingabe übernehmen (mdFlush), dann den Modus umschalten.
- «Alle n zeigen» (hall): `all = 1`.
- «Foto oder Logo wählen»/«Bild ändern» (havpick): Dateiauswahl, danach Zuschneiden (Ziel «h», Titel «Bild zuschneiden», ausserhalb). Gespeichert wird unter `settings.avatars[name]` = Blob-ID.
- «Entfernen» (havdel): Zuordnung löschen (der Blob bleibt im Speicher), neu zeichnen, Toast «Bild entfernt».

### 1.4 Umbenennen (heRename)
Ausgelöst durch: `change` am Namensfeld, Enter (Feld verlässt den Fokus), Wegnavigieren mit fokussiertem Feld (mdFlush).
1. Wert trimmen und Leerzeichen zusammenfassen.
2. Leer → altes Wert ins Feld zurück, Toast «Name darf nicht leer sein».
3. Unverändert → nichts.
4. Gibt es eine andere Person mit gleichem Namen (ohne Gross-/Kleinschreibung), kommt eine Rückfrage: Titel ««<Vorhanden>» gibt es schon», Text «Alle Einträge von «<Alt>» gehen an «<Vorhanden>», «<Alt>» wird entfernt.», Knopf «Zusammenführen».
   - Abbrechen → alter Name zurück ins Feld.
   - Bestätigen → Zusammenführen (1.5), die aktuelle Seite durch die Personenkarte von «Vorhanden» ersetzen, Toast «Zusammengeführt mit «<Vorhanden>»».
5. Sonst wird umbenannt:
   - `settings.holders`: Ist der alte Name enthalten, an derselben Stelle ersetzen, sonst den neuen anhängen.
   - Absender, Unterschrift und Bild mitnehmen (sndRename).
   - `lastHolders` ersetzen, Budget-Personenfilter (`bHolder`) und Kosten-Filter (`flt.holder`) nachziehen.
   - In allen Verträgen und Einnahmen den Namen ersetzen.
   - Toast «Umbenannt».
   - Nicht nachgezogen werden die Ignorieren-Schlüssel der Datenqualität (`h:Name:sender`).

### 1.5 Zusammenführen (heMerge(von, nach))
- `settings.holders` ohne «von»; «nach» anhängen, falls es fehlt. «von» aus `lastHolders` entfernen.
- Absender, Unterschrift und Bild wie sndRename (das Ziel behält eigene).
- Filter `bHolder` und `flt.holder` von «von» auf «nach» setzen.
- In allen Einträgen «von» → «nach». Ein Vertrag mit [von, nach] wird zu [nach].

### 1.6 Inhaber löschen
- Knopf «Inhaber löschen» (hdel):
  - Bei nur 1 Person → Toast «Mindestens ein Inhaber ist nötig».
  - Person ohne Verträge und Einnahmen → Rückfrage, Titel ««Name» löschen?», Text «Der Inhaber ist nirgends zugeordnet.», Knopf «Löschen» (rot). Bei Ja: löschen ohne Übertrag, eine Seite zurück, Toast «Inhaber gelöscht».
  - Sonst die Seite «Inhaber löschen» öffnen.
- **Seite hdel (MD_PAGES.hdel):**
  - Hinweistext ««<Name>» ist <n> Vertrag/Verträgen zugeordnet. Was soll damit passieren?». Hat die Person Einnahmen, wird vor « zugeordnet» « und <m> Einnahme/Einnahmen» eingefügt (z.B. ««Lara» ist 2 Verträgen und 1 Einnahme zugeordnet. Was soll damit passieren?»). Bei 0 Verträgen lautet es «0 Verträgen» (Fund R4).
  - Auswahlliste (Radio) mit einer Zeile pro anderer Person: Initiale (kein Foto) und «An «X» übertragen».
  - Letzte Zeile: Strich-Symbol, «Ohne Inhaber lassen», Untertitel «Gemeinsame Einträge behalten die übrigen Inhaber».
  - Vorauswahl: die erste andere Person. Nur wenn es keine gibt, «ohne».
  - Unten roter Hauptknopf «Inhaber löschen».
- Ausführen (hdelgo, heDelete):
  - Mit Ziel → Zusammenführen (1.5).
  - Ohne Ziel:
    - Name aus `settings.holders` entfernen; ist die Liste danach leer, gilt `["Ich"]`.
    - Aus `lastHolders` entfernen und Absender, Unterschrift und Bild löschen (sndDrop).
    - `bHolder` leeren, `flt.holder` = null.
    - Den Namen aus allen Einträgen entfernen.
  - Danach zwei Seiten zurück (zur Inhaber-Liste). Toast «Gelöscht, Einträge an «X» übertragen» bzw. «Inhaber gelöscht».

### 1.7 Absender-Seite: Wahl «Gleich wie» (Handler data-hssame, die Seite selbst liegt ausserhalb)
- Zuerst die Felder speichern (hsSave). Danach setzt «Eigene Adresse» die Person auf die eigene Adresse zurück (`same` entfernen), «Gleich wie X» setzt `same = X`. Speichern, neu zeichnen.

### 1.8 Weitere Aktionen der Inhaber-Seiten (Klick-Handler)
- Auf «Alle übertragen» (hbulk):
  - Tipp auf eine Person unter «Von» (data-hfrom) setzt `from`. Ist sie zugleich das Ziel, wird das Ziel geleert.
  - Tipp unter «An» (data-mdsel) setzt `to`.
  - «Übertragen» ersetzt in allen Einträgen «from» durch «to». Absender und Person bleiben bestehen. Danach eine Seite zurück und Toast «n Eintrag/Einträge an «to» übertragen» (n = tatsächlich geänderte Einträge).
- Auf «Verträge zuordnen»: Filter-Chip (data-hflt) setzt den Filter. Segment oder Chip (data-hset) speichert die Zuordnung sofort (hSet, ausserhalb).
- «Zuordnen» auf der Personenkarte öffnet «Verträge zuordnen» mit Filter «h:Name».

---

## 2. Kategorien

Konstanten: COLORS = #0E5A5E, #A93227, #1F4E8C, #6B4E9E, #8A6A1F, #2E6A4E, #B0562A, #3F4A55. Farbauswahl CE_COL = COLORS + #B03A5B, #2F86A6, #6E7B3A, #5F666E (12 Farben). Symbolauswahl CE_ICONS = die 12 Standardkategorien (Wohnen, Energie & Wasser, Versicherung, Gesundheit, Mobilfunk & Internet, Abos & Medien, Mobilität, Familie & Bildung, Freizeit & Sport, Steuern & Gebühren, Finanzen, Sonstiges) + «tag» (Etikett).

### 2.1 Liste (MD_PAGES.cat)
- Überschrift «n Kategorie/Kategorien», rechts der Link «Bearbeiten» bzw. «Fertig» (`md.catEdit`). Beim Öffnen des Fensters steht der Modus auf aus.
- Eine Zeile pro Kategorie in `catList`-Reihenfolge:
  - Farbiges Quadrat mit Symbol, Name fett.
  - Untertitel «n Vertrag/Verträge». Gezählt werden alle Verträge mit `cat` = Name, ohne Kategorie zählt als «Sonstiges», gekündigte Verträge eingeschlossen.
  - Bei n > 0 zusätzlich « · Betrag WÄHRUNG/Mt.»: Summe der Monatskosten nur laufender, nicht pausierter Verträge in der Hauptwährung.
  - Tipp öffnet das Detail.
- Bearbeiten-Modus:
  - Links ein rotes ⊖ (Bedienhilfe «<Name> löschen»); bei «Sonstiges» deaktiviert.
  - Rechts der Ziehgriff ≡ (Bedienhilfe «<Name> verschieben»).
  - Die Zeile «Kategorie hinzufügen» ist ausgeblendet.
- Normalmodus: letzte Zeile «+ Kategorie hinzufügen».
- Hinweis unten:
  - Bearbeiten-Modus: «Mit ⊖ löschen, mit ≡ ziehen, um die Reihenfolge zu ändern. «Sonstiges» bleibt immer.»
  - Normalmodus: «Kategorien gruppieren deine Verträge in der Liste und in den Kosten. Tippe auf eine Kategorie, um Name, Farbe und Symbol zu ändern.»
- ⊖ antippen:
  - «Sonstiges» → nichts.
  - Leere Kategorie → Rückfrage, Titel ««Name» löschen?», Text «Die Kategorie ist leer.», Knopf «Löschen» (rot). Bei Ja: löschen (Ziel «Sonstiges»), Toast «Kategorie gelöscht».
  - Sonst die Seite «Kategorie löschen» mit Quelle = diese Kategorie.

### 2.2 Reihenfolge ziehen (Pointer-Events; SwiftUI: List + .onMove)
- Nur am Griff. Während des Ziehens folgt die Zeile dem Finger, die anderen Zeilen rücken um eine Zeilenhöhe nach.
- Zielposition: Die Mitte der gezogenen Zeile wird mit den Mitten der übrigen Zeilen verglichen.
- Beim Loslassen (auch beim Abbruch durch das System) wird die neue Reihenfolge gespeichert, wenn sie sich geändert hat.

### 2.3 Detail (MD_PAGES.ce)
- Gibt es die Kategorie nicht mehr: «Diese Kategorie existiert nicht mehr.».
- Kopf: grosses Farbquadrat mit Symbol und das Feld Label «Name» (max. 30, Return «Fertig»). Bei «Sonstiges» ist das Feld deaktiviert, darunter: ««Sonstiges» fängt alles ohne Kategorie auf und lässt sich weder umbenennen noch löschen.»
- Abschnitt «Farbe»: 12 runde Farbflächen, die aktuelle ist markiert.
- Abschnitt «Symbol»: 13 Symbole auf der aktuellen Farbe, das aktuelle ist markiert.
- Farbe oder Symbol antippen speichert sofort (ceUpdate), auch bei «Sonstiges».
- Abschnitt «n Vertrag/Verträge»: alle Verträge dieser Kategorie (inkl. gekündigter) als Vertragszeilen. Leer: «Noch keine Verträge in dieser Kategorie.».
- Ausser bei «Sonstiges» unten der rote Knopf «Kategorie löschen»:
  - Leere Kategorie → Rückfrage wie in 2.1, bei Ja löschen, eine Seite zurück, Toast «Kategorie gelöscht».
  - Sonst die Seite «Kategorie löschen».

### 2.4 Umbenennen (ceRename)
Ausgelöst wie bei 1.4: change, Enter oder mdFlush.
1. Trimmen und Leerzeichen zusammenfassen.
2. Leer → Wert zurücksetzen, Toast «Name darf nicht leer sein».
3. Gleich → nichts.
4. Gibt es den Namen schon bei einer anderen Kategorie (ohne Gross-/Kleinschreibung) → Wert zurücksetzen, Toast «Diese Kategorie gibt es schon». Ein Zusammenführen wird nicht angeboten.
5. Sonst: den Namen im catList-Eintrag ändern (Farbe und Symbol bleiben). Alle Verträge mit genau `cat === alt` bekommen `cat = neu`, und ein Kosten-Filter auf die alte Kategorie wird umgestellt. Toast «Umbenannt».

Achtung beim Nachbau: In JS hängen Fachregeln am Kategorienamen («Versicherung» → Kündigungsweg Brief, Name beginnt mit «Steuern» → Steuer, «Wohnen» → Miete). Das ist ein Fund (M1). In Swift diese Regeln an eine stabile Kategorie-ID bzw. einen Vorbelegungs-Schlüssel binden.

### 2.5 Kategorie löschen (MD_PAGES.cdel, ceDelete)
- Quelle: `p.src` (aus der Liste) oder die vorherige Seite (aus dem Detail).
- Text bei n Verträgen: «In «X» ist 1 Vertrag. In welche Kategorie sollen sie?» bzw. «In «X» sind n Verträge. In welche Kategorie sollen sie?». Bei 0: ««X» ist leer und kann gelöscht werden.».
- Bei n > 0 eine Radio-Liste aller anderen Kategorien (Farbquadrat, Name). Vorauswahl «Sonstiges», ohne «Sonstiges» die erste.
- Roter Hauptknopf «Kategorie löschen». Aktion:
  - Alle Verträge der Quelle (inkl. gekündigter; ohne Kategorie zählt als Sonstiges) bekommen die Zielkategorie, Standard «Sonstiges».
  - Den Eintrag aus catList entfernen, einen Kosten-Filter auf die Quelle leeren.
  - Zurück zur Liste (aus der Liste 1 Seite, aus dem Detail 2 Seiten). Toast «Kategorie gelöscht».

### 2.6 Neue Kategorie (MD_PAGES.cenew)
- Startwerte: Farbe = COLORS[(Anzahl Kategorien + 3) mod 8], Symbol «tag».
- Kopf mit Vorschau und dem Feld Label «Name», Platzhalter «z.B. Haustier», max. 30. Darunter Farbe und Symbol wie in 2.3; die Auswahl gilt nur für den Entwurf, der eingegebene Name bleibt dabei erhalten.
- Knopf «Hinzufügen» (Enter im Feld löst ihn ebenfalls aus):
  - Leer → «Bitte einen Namen eingeben».
  - Doppelt (ohne Gross-/Kleinschreibung) → «Diese Kategorie gibt es schon».
  - Sonst ans Ende der Liste anhängen, eine Seite zurück, Toast «Kategorie «Name» angelegt».

---

## 3. Datenqualität: Liste der offenen Einträge mit Inline-Editoren

Die Prüfregeln (`qualItems`), die Übersicht (`paintMdQual`) und die Zeilen (`qRows`) liegen ausserhalb (Z. 4075–4199). Hier geht es um Seite, Editoren und Speichern.

### 3.1 Seiten
- `qual`: Übersicht, gezeichnet von paintMdQual (ausserhalb).
- Tipp auf ein Kriterium «n offen ›» (data-qf "Gruppe:Feld", data-qt = Titel) öffnet die Seite `qlist` mit {g, f, title}.
- **qlist (MD_PAGES.qlist):** Einträge = `qSel(qualItems(), g, f)`. Die Regel: bei f = «inc» alle Einnahmen-Hinweise der Gruppe, sonst alle mit Schlüssel-Endung = f; in Gruppe A nur Verträge.
  - Leer: Haken-Symbol, «Erledigt.», «Hier ist nichts mehr offen.».
  - Sonst Kopf «n Eintrag/Einträge» (orange). Rechts bei f = logo der Knopf «Alle suchen», immer «Alle ignorieren». Darunter die Zeilen (qRows) mit Editor.
  - Hinweis unten:
    - bei logo: ««Suchen» schlägt ein Logo vor. Tippe auf den Namen, um es selbst zu wählen.»
    - bei Inline-Feldern: «Direkt hier eintragen. Tippe auf den Namen für alle Angaben.»
    - sonst: «Tippe auf einen Eintrag, um die Angabe nachzutragen.»
- Inline-fähige Felder (QE_INLINE): holder, amount, cat, cycle, due, via, ref, link, mail, notice, inc, addr, sender.

### 3.2 Einfeld-Editoren (qEditor), Speichern sofort (qSave)
Verträge (Schlüssel «VertragsID:Feld»):

| Feld | Steuerelement | Speichert | Regel |
|---|---|---|---|
| via | Segment «Online» / «E-Mail» / «Brief» | `cancF` = «Online / Kundenkonto» / «E-Mail» / «Brief» | sofort beim Tippen |
| holder | Segment mit allen Personen (holderStats) + bei ≥ 2 Personen «Beide» (genau 2) bzw. «Alle» (≥ 3) | `holders` = [Name] bzw. alle | sofort |
| cat | Auswahl «Kategorie wählen …» + alle Kategorien ausser «Sonstiges» | `cat` | bei Auswahl |
| cycle | Auswahl «Zahlungsweise wählen …» + 1 «monatlich», 2 «alle 2 Monate», 3 «quartalsweise», 6 «halbjährlich», 12 «jährlich», 24 «alle 2 Jahre» | `cycle` (Zahl) | bei Auswahl |
| due | Datumsfeld (Bedienhilfe-Name «Nächste Zahlung») | `due` (ISO-Datum) | bei Auswahl |
| amount | Textfeld, Dezimal-Tastatur, Platzhalter «Betrag in WÄHRUNG» | `amount` | beim Verlassen/Enter; Zahl > 0, sonst Toast «Bitte einen Betrag eingeben» |
| ref | Textfeld, Platzhalter «Kunden- oder Vertragsnummer» | `custNo` | beim Verlassen/Enter |
| link | URL-Feld, Platzhalter «z.B. sunrise.ch/kuendigen» | `cancUrl` | beim Verlassen/Enter, ohne Prüfung |
| mail | E-Mail-Feld, Platzhalter «z.B. kuendigung@anbieter.ch» | `mail` | beim Verlassen/Enter, ohne Prüfung |

Einnahmen (Schlüssel «inc|EinnahmeID:Feld»):
- amount: Textfeld «Betrag in WÄHRUNG», Zahl > 0.
- holder: Segment wie oben inkl. «Beide»/«Alle». Achtung, das ist inkonsistent zum Einnahmen-Formular (Fund N10).

Allgemein:
- Leere Werte werden ignoriert.
- Zahlen werden mit `parseNum` gelesen (entfernt «'» und ersetzt das **erste** Komma durch einen Punkt). Inline wird nicht gerundet (Fund R2).
- Nach dem Speichern: render, die Liste neu zeichnen (der Eintrag verschwindet), Toast «Titel: gespeichert». Bei Einnahmen ist der Titel `label` || `name` || «Einnahme».
- Enter in einem Inline-Feld verlässt nur das Feld, das Speichern läuft über `change`.

### 3.3 Mehrfeld-Editoren mit «Übernehmen» (qMulti / qMultiSave)
Knopf «Übernehmen» mit Schlüssel «Feld:ID». Werte werden getrimmt und Leerzeichen zusammengefasst.

**Frist/Laufzeit (notice, ID = Vertrag)**
- Zeile 1: Feld «Frist» (Ziffern, schmal), Vorbelegung `notice`. Einheiten-Auswahl: m «Monate», w «Wochen», d «Tage», k «. im Monat», vorbelegt mit `noticeU` (Standard m).
- Zeile 2: Auswahl:
  - «Kündbar auf … wählen» (leer)
  - m «auf Monatsende»
  - q «auf Quartalsende»
  - h «auf Halbjahresende»
  - y «auf Jahresende»
  - a «auf Ende Vertragsjahr»
  - p «auf Ende Zahlungsperiode»
  - fix «Feste Laufzeit bis …»
  Vorbelegt mit `cancTerm`, falls gesetzt. Die Option «jederzeit» fehlt (Fund M2).
- Zeile 3, nur bei «fix» sichtbar: Datumsfeld «Vertragsende» (nicht vorbelegt) und Auswahl «ohne Verlängerung» / «verlängert um 1 Monat» / «verlängert um 12 Monate» / «verlängert um 24 Monate» (Werte "", "1", "12", "24"; das Formular kennt zusätzlich 3 und 6).
- Speichern:
  - `notice` = Zahl > 0, sonst 0; `noticeU` = Einheit.
  - Bei «fix»: Ende ist Pflicht (Toast «Bitte das Vertragsende eingeben»), dann `end`, `renew` und `cancTerm=""`.
  - Bei einem Termin: `cancTerm` setzen. Achtung, `end`/`renew` bleiben stehen (Fund N1; im Nachbau leeren).
  - Ohne Auswahl → Toast «Bitte wählen, worauf kündbar».
  - Toasts nach dem Speichern:
    - Termin berechenbar: «Titel: gespeichert»
    - sonst bei «a»: «Gespeichert. Für «Ende Vertragsjahr» fehlt noch das Startdatum im Vertrag»
    - sonst: «Gespeichert, Termin noch nicht berechenbar»

**Adresse des Vertragspartners (addr, ID = Partner-Schlüssel = Name klein geschrieben)**
- Felder «Firma» (Vorbelegung Firma aus der bestehenden Adresse, sonst der Partnername), «Strasse und Nr.», «PLZ» (Ziffern, schmal), «Ort». Knöpfe «Übernehmen» und «Suchen» (siehe 3.5).
- Speichern: Strasse und Ort sind Pflicht (Toast «Bitte Strasse und Ort eingeben»). Zusatz und Land der bestehenden Adresse bleiben erhalten. Die Adresse wird mehrzeilig zusammengesetzt (addrJoin) und auf **alle** Verträge des Partners geschrieben (setPartnerAddr). Toast «Partnername: Adresse gespeichert».

**Absender (sender, ID = Inhabername)**
- Felder «Vorname» | «Nachname», «Strasse und Nr.», «PLZ» | «Ort». Vorbelegt ist der wirksame Absender (bei «gleich wie» die Adresse der anderen Person).
- Knöpfe «Übernehmen» und pro anderer Person mit eigener vollständiger Adresse (nicht selbst «gleich wie») «Adresse wie X».
- Übernehmen: Pflicht sind Vor- oder Nachname, Strasse und Ort (Toast «Bitte Name, Strasse und Ort eingeben»; das gilt auch, wenn nur der Name fehlt, siehe Fund M3). Gespeichert werden die eigenen Felder, `same` wird entfernt, das bestehende Land bleibt. Toast «Absender von X gespeichert».
- «Adresse wie X»: Vor- und Nachname aus den Feldern übernehmen, `same = X`, speichern. Toast «Adresse übernommen», ohne Namen mit dem Zusatz «, Name noch eintragen».

### 3.4 Weitere Aktionen der Liste
- «Ignorieren»: Schlüssel in `settings.qIgn` setzen, die Liste neu zeichnen. Schlüsselformat «c:ID:feld», «i:ID:feld», «p:partnerkey:logo|addr», «h:Name:sender».
- «Alle ignorieren»: alle Einträge der aktuellen Liste ignorieren.
- «Zurücksetzen» (#qReset in der Übersicht): `qIgn = {}`.
- Tipp auf den Namen:
  - Vertrag: Fenster schliessen, nach 200 ms das Vertragsformular öffnen.
  - Einnahme: Fenster schliessen, Einnahme öffnen.
  - Vertragspartner: dessen Seite (openPe).
  - Inhaber: Absender-Seite (openHs).
- Logo: «Suchen» bei einem Partner öffnet dessen Seite und löst nach 250 ms «Logo automatisch finden» aus (openPeSearch). «Alle suchen» → Sammelsuche (qSearch, ausserhalb).
- In den Vorschlägen der Sammelsuche (Seite raw): Tipp schaltet die Auswahl um, «Andere …» öffnet wie «Suchen», «n Vorschläge übernehmen» → qApply (ausserhalb).
- Toter Code: Handler `data-qall` (wird nicht gerendert, nicht portieren).

### 3.5 Adresssuche aus Datenqualität und Partner-Seite
- Datenqualität «Suchen» (data-qafind) und Partner-Seite «Suchen» (paddrfind) arbeiten gleich:
  - Toast «Suche Adresse …», dann `findAddresses(Partnername, Domain der Website, Währung des ersten Vertrags)` (ausserhalb). Die Funktion fragt Wikidata und OpenStreetMap parallel und liefert bis zu 5 Kandidaten {lines[], src}.
  - Kein Treffer: in der Datenqualität «Keine Adresse gefunden», auf der Partner-Seite «Keine Adresse gefunden. Bitte von Website oder Rechnung übernehmen.».
  - Treffer: Auswahl-Sheet, Titel «Adresse wählen», eine Zeile pro Kandidat (Zeilen untereinander, Quelle klein darunter). Nur auf der Partner-Seite steht darunter der Hinweis «Quellen: Wikidata und OpenStreetMap, ohne Gewähr. Bei mehreren Standorten den Hauptsitz oder Kundendienst wählen.».
  - Fehler: «Suche nicht möglich».
- Auswahl (ausserhalb, Z. 3465): Adresse normalisieren (addrSplit → addrJoin), auf alle Verträge des Partners schreiben, neu zeichnen, Toast «Adresse übernommen, bitte prüfen».

---

## 4. Vertragspartner-Seite: Eingaben und Logo (nur Handler; die Seite selbst liegt ausserhalb, Z. 4299)

### 4.1 Adresse als Felder (PA_F, paForm, addrSplit, addrJoin, paSave, peAddrChange, setPartnerAddr)
- Felder in dieser Reihenfolge, jeweils mit Platzhalter, ohne Label:
  - «Firma, z.B. Sunrise GmbH» (Autofill organization)
  - «Zusatz, z.B. Kundendienst oder Postfach»
  - «Strasse und Nr.»
  - «PLZ» (Ziffern) | «Ort» in einer Zeile
  - «Land (optional)»
  Alle Felder mit Wort-Grossschreibung, Return «Weiter».
- Gespeichert wird weiterhin **ein mehrzeiliger Text** `c.addr` pro Vertrag, auf allen Verträgen eines Partners gleich (Vergleich: Partnername getrimmt, klein geschrieben).
- **addrSplit(Text) → Felder:**
  1. In Zeilen teilen, trimmen, Leerzeilen weg.
  2. Die PLZ-Zeile ist die erste Zeile, auf die `^([A-Z]{1,2}-?)?\d{4,5}\s+\S` passt.
  3. Ohne PLZ-Zeile: Firma = 1. Zeile, Strasse = alle weiteren Zeilen mit «, » verbunden.
  4. Mit PLZ-Zeile: PLZ = die Ziffern (ein Präfix wie «D-» entfällt), Ort = der Rest der Zeile, Land = alle Zeilen danach mit «, ». Von den Zeilen davor: Strasse = die letzte, Firma = die erste der übrigen, Zusatz = die restlichen mit «, ».
  Schwächen siehe Fund N8.
- **addrJoin:** Firma, Zusatz, Strasse, «PLZ Ort», Land. Leere Teile weglassen, mit Zeilenumbruch verbinden.
- Speichern (paSave): bei `change` jedes Feldes und bei Enter im letzten Feld. Enter in den anderen Feldern springt ins nächste Feld. Der Text wird normalisiert (Zeilen trimmen, leere weg) und nur bei Änderung auf alle Verträge geschrieben. Toast «Adresse gespeichert» bzw. bei leerem Text «Adresse entfernt».

### 4.2 Logo-Knöpfe auf der Partner-Seite
- «Logo automatisch finden» (#peAuto): Vorschläge zum aktuellen Namen im Feld, mit Währung und Website des Partners (runCands, ausserhalb). Tipp auf einen Vorschlag übernimmt das Logo sofort für **alle** Verträge des Partners; der Toast erscheint nach 900 ms: «Logo gespeichert».
- «Einfügen» (#pePaste): Bild aus der Zwischenablage (pasteLogo «p»), das Hervorheben endet.
- «Hochladen» (#peUp): Dateiauswahl + Zuschneiden (Ziel «p»). Nur vorhanden, wenn ein Dateispeicher verfügbar ist.
- «Google» (#peGoogle): Ohne Namen → Toast «Zuerst den Namen eintragen». Sonst öffnet sich die Google-Bildsuche (logoSearch, ausserhalb) mit dem Hinweis «So geht’s: In Google das passende Bild lange drücken → «Kopieren». Dann zurück in die App und «Einfügen» tippen.». Der Knopf «Einfügen» pulsiert.
- «Bild entfernen» (#peLogoDel): Logo bei allen Verträgen des Partners entfernen, Toast «Logo entfernt». Nur sichtbar, wenn ein Logo existiert.
- Hilfsfunktionen: `openPe(key)` legt die Partner-Seite auf den Stapel, wenn das Fenster offen ist, sonst öffnet es das Fenster direkt dort. `openPeSearch(key)` wie openPe, dazu nach 250 ms automatisch «Logo automatisch finden».

### 4.3 Eingabe-Handler des Verwalten-Fensters
- `change`:
  - Inline-Feld mit Schlüssel → qSave.
  - Auswahl «Kündbar auf» → Zeile «Feste Laufzeit» ein- oder ausblenden.
  - Namensfelder der Seiten Partner, Inhaber und Kategorie sowie die Adressfelder → speichern (mdNameChange).
  - Absender-Felder → hsSave.
- `input`:
  - Suchfeld der Partnerliste: Liste bei jedem Zeichen neu zeichnen, Fokus und Cursor bleiben.
  - Neue Kategorie: Entwurfsname merken.
- Enter:
  - Inline-Feld → Feld verlassen.
  - Namensfeld → Feld verlassen (löst das Speichern aus).
  - Adress- bzw. Absenderfelder → nächstes Feld, im letzten speichern.
  - «Neuer Inhaber»/«Neue Kategorie» → «Hinzufügen».
- mdFlush (ausserhalb): Vor jeder Navigation (Push, Pop, Schliessen, Bearbeiten-Umschalten) wird ein noch fokussiertes Namens- oder Adressfeld gespeichert. SwiftUI: `onSubmit` + `onDisappear`/`onChange` statt Fokus-Tricks; der Fund N7 entfällt damit.

---

## 5. Vertragspartner-Vorschläge beim Erfassen (Formular, Feld «Vertragspartner»)

### 5.1 Ablauf (schedulePSug, paintPSug, hidePSug)
- Auslöser: Eingabe und Fokus im Feld.
  - Bei Eingabe wird die Merkvariable «gewählter Name» (`pSugSel`) geleert, sobald der Text davon abweicht.
  - Beim Verlassen des Feldes wird die Liste nach 220 ms ausgeblendet; ein Tippen auf die Liste nimmt dem Feld den Fokus nicht.
- Unter 2 Zeichen oder Text = gewählter Name → Liste ausblenden.
- Sonst sofort zeichnen:
  - Abschnitt «Deine Vertragspartner»: bis zu 3 eigene Partner, deren Name den Text enthält (ohne Gross-/Kleinschreibung). Zeile: Logo, Name, Untertitel «n Vertrag/Verträge», mit Website zusätzlich « · domain».
  - Ab 3 Zeichen, solange keine Internet-Treffer da sind, der Platzhalter «Suche …».
- Nach 350 ms Pause: Internet-Suche (webPartners). Ergebnisse nur übernehmen, wenn inzwischen keine neue Eingabe kam (Zähler-Token). Abschnitt «Aus dem Internet»:
  - Treffer, deren Name einem eigenen Partner gleicht, entfallen.
  - Zeile: Bild auf weissem Grund. Mit Logo-Datei `https://commons.wikimedia.org/wiki/Special:FilePath/<Datei>?width=96`, sonst `https://www.google.com/s2/favicons?sz=64&domain=<domain>`; bei Ladefehler entfällt das Bild.
  - Name fett, Untertitel «domain · Beschreibung».
- Ist nichts anzuzeigen, wird die Liste ausgeblendet.

### 5.2 Internet-Suche (webPartners(q)) mit Wikidata
- Bedingungen: mindestens 3 Zeichen, Name «brauchbar» (lusable, 7.1), online. Sonst leere Liste.
- Anfrage 1: `https://www.wikidata.org/w/api.php?format=json&origin=*&action=wbsearchentities&type=item&limit=8&language=de&uselang=de&search=<q>`. Ergebnis: IDs aus `search[].id`.
- Anfrage 2: `…&action=wbgetentities&props=claims|labels|descriptions&languages=de|en&ids=<id1|id2…>`.
- Zeitlimit je 8 s (rateJson). Fehler → leere Liste.
- Pro Entität (in Suchreihenfolge):
  - Überspringen, wenn eine «instance of»-Angabe (P31) in der Ausschlussliste WNOT steht (7.6).
  - Websites = P856 als Hostname ohne www. Ohne Website überspringen.
  - Label = de, sonst en. Ohne Label überspringen.
  - Der normalisierte Text muss im normalisierten Label enthalten sein (lnorm), sonst überspringen.
  - Doppelte registrierbare Domain (regDom) überspringen.
  - Logo-Datei = P8972 (kleines Logo/Icon), sonst P2910 (Icon), sonst P154 (Logo).
  - Telefon = erster Text aus P1329. E-Mail = erster Text aus P968, ohne «mailto:».
  - Land: P17 enthält Q39 → «CH», Q183 → «DE»; sonst Domain auf .ch → CH, auf .de → DE; sonst leer.
  - Beschreibung = de, sonst en; descAll = de + " " + en.
  - Abgelehnte Claims mit Rang «deprecated» werden ignoriert (wclaims).
- Rückgabe: höchstens 4 Treffer {name, desc, descAll, dom, file, tel, mail, cc}.

### 5.3 Übliche Frist für beliebige Anbieter (STD_RULES, stdFor)
- Text = lnorm(descAll oder desc) + " " + lnorm(name). Es gilt die erste Regel, deren Muster passt.
- Werte im Format [Frist, Einheit, Kündbar per, Kündigungsweg, Pflicht (1/0), Hinweis]:

| Muster (Regex auf normalisiertem Text) | Kategorie | Bezeichnung | CH | DE | alle Länder |
|---|---|---|---|---|---|
| `krankenkasse\|krankenversicher\|health insur` | Versicherung | Krankenkasse | [1, m, y, «Einschreiben», 1, H_KVG] | [2, m, m, "", 1, H_GKV], nur wenn zusätzlich `gesetzlich\|krankenkasse` passt, sonst nächste Regel | – |
| `versicher\|insurance` | Versicherung | Versicherung | [3, m, a, «Brief», 0, H_VVG] | [3, m, a, «Brief», 0, H_VDE] | – |
| `telekom\|telecom\|mobilfunk\|mobile (network\|operator)\|internetdienst\|internet service\|kabelnetz` | Mobilfunk & Internet | Handy / Internet | [60, d, m, "", 0, H_TCH] | [1, m, "", "", 0, H_TDE] | – |
| `energieversorg\|stromanbieter\|stadtwerk\|elektrizit\|electric utility\|energy (company\|supplier)` | Energie & Wasser | Strom | [0, m, "", "", 1, H_ECH] | [1, m, "", "", 0, H_EDE] | – |
| `streaming\|video.on.demand\|musikdienst\|music service` | Abos & Medien | Streaming | | | [0, m, p, «Online / Kundenkonto», 0, H_STR] |
| `fitness` | Freizeit & Sport | Fitnessabo | | | [0, m, a, "", 0, H_FIT] |
| `\bbank\b\|kreditinstitut\|neobank\|sparkasse` | Finanzen | Konto | | | [0, m, "", "", 0, H_BNK] |

- Hinweistexte (ausserhalb, Z. 2756–2766, wörtlich):
  - H_KVG: «Grundversicherung: per 31.12. kündbar, Kündigung muss bis 30.11. eingetroffen sein. Mit Mindestfranchise und Standardmodell (freie Arztwahl) zusätzlich per 30.06., Kündigung bis 31.03. Zusatzversicherungen haben eigene Fristen.»
  - H_VVG: «Nach 3 Jahren per Ende Versicherungsjahr kündbar (VVG). Genaue Frist in der Police prüfen.»
  - H_TCH: «60 Tage auf Monatsende, frühestens auf Ende der Mindestlaufzeit.»
  - H_TDE: «Nach der Mindestlaufzeit monatlich mit 1 Monat Frist kündbar (TKG).»
  - H_STR: «Jederzeit kündbar, gilt ab der nächsten Abrechnungsperiode.»
  - H_BNK: «Konto jederzeit kündbar. Guthaben vorher übertragen.»
  - H_FIT: «Abos laufen meist 12 Monate. Verlängerung und Frist im Vertrag prüfen.»
  - H_ECH: «Grundversorgung: Haushalte können den Stromanbieter nicht wechseln.»
  - H_EDE: «Sondervertrag: nach Mindestlaufzeit meist 1 Monat Frist. Grundversorgung: 2 Wochen.»
  - H_GKV: «Gesetzliche Krankenkasse: 2 Monate zum Monatsende, nach mindestens 12 Monaten Mitgliedschaft.»
  - H_VDE: «Meist 3 Monate zum Ende des Versicherungsjahres, neuere Verträge oft 1 Monat. Police prüfen.»
- Kategorie nur übernehmen, wenn es sie in der Kategorienliste des Nutzers gibt, sonst "".
- Rückgabe im Katalogformat (TPLI): [0 Name, 1 Land, 2 Kategorie, 3 Bezeichnung, 4 Domain, 5 Frist, 6 Einheit, 7 Kündbar per, 8 Kündigungsweg, 9 Pflicht, 10 Hinweis].
  - Passt eine Regel, aber es gibt keinen Wert für das Land: `[Name, Land, Kat, Bez, Domain, 0, "m", "", "", 0, ""]`, aber nur wenn die Kategorie existiert, sonst null.
  - Keine Regel → null.

### 5.4 Internet-Treffer übernehmen (pickWebPartner)
1. Feld Vertragspartner = Name des Treffers und als «gewählt» merken.
2. Nur leere Felder füllen: Website = Domain, Telefon, E-Mail. Sammelliste für den Toast: «Website», «Telefon», «E-Mail».
3. Vorlage bestimmen: der erste Katalogeintrag (TPL) mit derselben registrierbaren Domain, Name ersetzt durch den Treffernamen; sonst stdFor. Wenn die Vorlage eine Kategorie hat und noch keine Kategorie gewählt ist → übernehmen, Liste «Kategorie». Achtung, im Katalogpfad wird nicht geprüft, ob es die Kategorie gibt (Fund N4).
4. Bezeichnung leer → Bezeichnung der Vorlage (ohne Eintrag in der Sammelliste).
5. Vorlage ohne Hinweistext (Index 10) → verwerfen.
6. Hat die Vorlage Frist, Kündbar per oder Pflicht, und sind Frist sowie «Kündbar per» im Formular leer: die Vorlage still anwenden (applyTpl keepName, quiet, ausserhalb), als «übliche Frist» merken, Liste «übliche Frist». Achtung, applyTpl überschreibt dabei Kategorie, Kündigungsweg und Pflicht (Fund N4). Swift: nur leere Felder füllen.
7. Land = Land der Vorlage, sonst des Treffers. Ist es gesetzt und der Betrag leer: Währung = EUR bei DE, sonst CHF.
8. Vorschlagsliste ausblenden, Logo, Farben und Vorschlagsknopf neu zeichnen.
9. Logo:
   - Ist schon ein gültiges Logo da, offline oder kein Dateispeicher → nur der Toast.
   - Sonst Toast «Lade Logo …», dann:
     a. Mit Datei: `https://commons.wikimedia.org/w/api.php?format=json&origin=*&action=query&prop=imageinfo&iiprop=url|size&iiurlwidth=512&titles=File:<Datei>`. Erstes `imageinfo` lesen und `thumburl` (sonst `url`) als Wikipedia-Logo verarbeiten (takeLogo src wiki: auf ein Quadrat setzen, ausserhalb).
     b. Sonst bzw. ohne Ergebnis: Website-Symbol der registrierbaren Domain (siteCand(regDom(domain), 3), ausserhalb).
   - Übernehmen nur, wenn der Entwurf inzwischen kein Logo hat. Achtung, es gibt keine Prüfung, ob es noch derselbe Entwurf ist (Fund N3).
10. Toast: «Übernommen: A, B, …» (mit «Logo», wenn geladen) bzw. «Nichts Weiteres gefunden».

### 5.5 Eigenen Vertragspartner übernehmen (pickOwnPartner)
- Name setzen und als gewählt merken.
- Website nur, wenn leer.
- Logo des Partners, wenn der Entwurf keins hat (Hintergrund Standard #FFFFFF).
- Kategorie des ersten Vertrags, wenn keine gewählt ist.
- Telefon und E-Mail des ersten Vertrags nur in leere Felder.
- Danach Liste ausblenden und neu zeichnen. Kein Toast.

---

## 6. Einstellungen «Währung» und Wechselkurse

### 6.1 Anzeige
- `fillSettings`:
  - Verwalten-Übersicht aktualisieren.
  - «Letzter Quartals-Check: <Datum lang>» bzw. «Noch kein Quartals-Check durchgeführt» (Element ist ausgeblendet).
  - Hauptwährung zeichnen, CSV-Ausgabe leeren, Kursstand zeichnen.
- Kursstand (paintRateStamp): «Kurse der EZB, täglich automatisch · Stand <Datum lang, z.B. 2. Oktober 2026>». Ohne Datum fällt « · Stand …» weg. Die Quelle heisst immer EZB, auch beim Fallback (Fund R4).
- Hauptwährung (paintHomePick): in der Gruppe «Währung» mit dem Hinweis «Hauptwährung für alle Summen».
  - Zwei grosse Kacheln EUR, CHF mit Fahne.
  - Knopf «Weitere Währungen» klappt die kleinen Kacheln USD, GBP, TRY auf. Ist die aktuelle Währung eine davon, ist der Bereich offen.
  - Bedienhilfe-Namen: «EUR (Euro)», «CHF (Franken)», «USD (US-Dollar)», «GBP (Pfund)», «TRY (Lira)».
  - Tipp auf eine andere Währung: speichern, Kursabruf ohne Zwang, alles neu zeichnen, Toast «Hauptwährung: XXX».
- Knopf «Aktualisieren» → Kursabruf mit Zwang.

### 6.2 Kursabruf (rateJson, fetchRate, autoRate)
- Gespeichert wird `settings.rates` = CHF pro Einheit für EUR, USD, GBP, TRY. CHF selbst ist 1.
  - Umrechnung (ausserhalb): Betrag × rate(Währung) / rate(Hauptwährung).
  - Fehlt ein Kurs, gelten die Startwerte RATE0: EUR 0.94, USD 0.80, GBP 1.07, TRY 0.02.
- rateJson(url): GET ohne Cache, Abbruch nach 8 s. Status nicht OK → Fehler. Antwort als JSON. Das Zeitlimit endet schon beim Eingang der Header (Fund N9).
- fetchRate: Quellen der Reihe nach, die erste plausible gewinnt:
  1. `https://api.frankfurter.dev/v1/latest?base=CHF&symbols=EUR,USD,GBP,TRY`: `rates`, Datum `date`.
  2. `https://api.frankfurter.app/latest?from=CHF&to=EUR,USD,GBP,TRY`: `rates`, Datum `date`.
  3. `https://open.er-api.com/v6/latest/CHF`: `rates`, Datum aus `time_last_update_unix` (lokales Datum).
  - Die Quellen liefern «Einheiten pro 1 CHF». Gespeichert wird der Kehrwert 1/x, nur für Werte > 0.
  - Plausibel heisst: EUR liegt zwischen 0.5 und 2 CHF. Jeder Fehler führt zur nächsten Quelle; ohne Ergebnis null.
- autoRate(zwang):
  - Läuft schon ein Abruf → nichts (auch ohne Toast).
  - Ohne Zwang: nichts, wenn heute schon geprüft wurde (`rateChecked` = heute) und ein USD-Kurs vorhanden ist.
  - Offline: mit Zwang Toast «Keine Internetverbindung», sonst still.
  - Mit Zwang Toast «Lade Kurse…» (ohne Leerzeichen vor den Punkten).
  - Fehlschlag: mit Zwang «Kurse konnten nicht geladen werden». `rateChecked` wird nicht gesetzt, der nächste Anlass versucht es erneut.
  - Erfolg:
    - `rates` wird **komplett ersetzt**: EUR auf 4 Nachkommastellen gerundet, USD/GBP/TRY auf 6, nur wenn vorhanden. Fehlt eine Währung, gilt danach RATE0.
    - `rateDate` = Datum der Quelle, wenn im Format JJJJ-MM-TT, sonst heute. `rateChecked` = heute.
    - `rateSrc="auto"` und `rateAuto=true` werden geschrieben, aber nirgends gelesen (nicht portieren).
    - Speichern, Kursstand neu zeichnen. Nur bei geänderten Kursen die Hauptansicht neu zeichnen. Mit Zwang Toast «Kurse aktualisiert».
- Auslöser: App-Start (ausserhalb, Z. 5589), App kommt in den Vordergrund (visibilitychange → sichtbar), Wechsel der Hauptwährung (auch in der Einführung), Knopf «Aktualisieren». SwiftUI: `scenePhase == .active` → autoRate(false).

---

## 7. Logo-Suche: Namensvergleich, App Store, Bildprüfung, Wikidata (bis Z. 5029)

### 7.1 Namen normalisieren
- `lnorm(s)`: klein schreiben, Unicode NFD, Akzente entfernen (U+0300–U+036F), «ß» → «ss», «&» → « und », alles ausser a–z/0–9 → Leerzeichen, trimmen.
- `ltok(s)`: Wörter aus lnorm mit mindestens 2 Zeichen, ohne Stoppwörter LSTOP.
- LSTOP (zählen nie): ag, gmbh, sa, se, kg, co, ltd, inc, llc, plc, nv, bv, spa, sarl, sagl, ug, ev, mbh, die, der, das, the, und, and, de, la, le, les, des, of, von, fur, fuer, schweiz, suisse, svizzera, switzerland, swiss, deutschland, germany, ch, international.
- LGEN (generisch; dürfen beim Treffer zusätzlich stehen, reichen allein aber nicht): gruppe, group, holding, app, apps, mobile, versicherung, versicherungen, versicherungsgesellschaft, insurance, assurance, assurances, bank, krankenkasse, krankenversicherung, energie, strom, werke, services, service, online, digital, genossenschaft, gesellschaft, official, offiziell.
- LADJ (Adjektive, beim Treffer erlaubt): schweizerische, schweizerischen, schweizer, deutsche, deutscher, allgemeine, erste, neue, grand.
- LPLACE (Ortsbegriffe, reichen allein nie): stadt, gemeinde, kanton, verwaltung, landkreis, kreis, bezirk, verein, club, amt.
- `lusable(name)`: mindestens ein Wort mit ≥ 3 Zeichen, das weder generisch noch Ortsbegriff ist. Folge: «O2», «1&1» und «E.ON» sind nicht brauchbar, für sie gibt es keine Internet-Vorschläge und keine Namenssuche.
- `teq(a,b)`: gleich, oder beide ≥ 6 Zeichen und unterscheiden sich nur durch angehängtes «s» oder «en».
- `nameEq(gesucht, text)`: Jedes gesuchte Wort kommt im Text vor (teq), und jedes Textwort ist gesucht, generisch oder ein Adjektiv.
- `nameHas(gesucht, text)`: Jedes gesuchte Wort kommt vor, weitere Wörter sind erlaubt.
- `regDom(d)`: klein schreiben, «www.» weg, die letzten zwei Labels. Falsch bei .co.uk/.com.tr (Fund N5); in Swift eine Public-Suffix-Liste verwenden.

### 7.2 Punkte für App-Store-Treffer (lscore(name, r, domain))
- Name nicht brauchbar → 0. Genre enthält «game»/«spiel» → 0.
- Anbieter = `sellerName` || `artistName`. «Domain passt» heisst: Vertragsdomain vorhanden und regDom(Host von `sellerUrl`) = regDom(Domain).
- Anbieter passt genau (nameEq) oder Domain passt: 3 Punkte.
  - App-Name passt genau: +2, sonst bei nameHas +1.
  - Domain passt: zusätzlich +2.
- Sonst App-Name passt genau: 2 (nur Vorschlag).
- Sonst nameHas auf App-Name oder Anbieter: 1. Sonst 0.

### 7.3 App-Store-Suche (logoCands(name, Währung, Domain), jsonp)
- Länderreihenfolge nach Währung: EUR → de, ch; USD → us, ch; GBP → gb, ch; TRY → tr, de; sonst (CHF) ch, de.
- Suchbegriff: Wörter aus ltok mit Leerzeichen, sonst der Name.
- Pro Land: `https://itunes.apple.com/search?entity=software&limit=20&country=<cc>&term=<begriff>`.
  - In JS als JSONP (Callback-Name «kjp…», Zeitlimit 9 s, Fehler «timeout»/«net»). In Swift ein normaler JSON-GET mit 9 s.
- Pro Ergebnis: Bild = `artworkUrl512` || `artworkUrl100`. Doppelte trackId überspringen. Punkte > 0 → Kandidat {url, thumb (`artworkUrl100`), title (trackName), seller, score, src "store"}.
- Hat ein Land einen Treffer mit ≥ 3 Punkten, werden keine weiteren Länder gefragt.
- Ergebnis nach Punkten absteigend.

### 7.4 Bild prüfen und normieren für App-Store-Bilder (logoBlob(url))
- Quellen der Reihe nach:
  1. URL mit `/<b>x<h>bb.<ext>` am Ende ersetzt durch `/512x512bb.png`
  2. Original
  3. Proxy `https://images.weserv.nl/?url=<groessere URL ohne Schema>&w=512&h=512&fit=cover&output=png`
  Die dritte Quelle dient nur als CORS-Ausweg; in Swift ist sie unnötig, direkt laden.
- Das erste ladbare Bild entscheidet:
  - Breite oder Höhe < 256 oder Seitenverhältnis ausserhalb 0.8–1.25 → `{err:"klein"}`, ohne weitere Quelle zu versuchen.
  - Probe auf 32×32 verkleinert: Standardabweichung der Helligkeit (0.2126 R + 0.7152 G + 0.0722 B) < 6 oder Anteil deckender Pixel (Alpha > 200) < 60 % → `{err:"leer"}`.
  - Sonst 512×512 PNG auf weissem Grund, Glättung hoch → `{blob}`.
- Nicht lesbar (CORS) → nächste Quelle. Alle scheitern → `{err:"laden"}`.
- Bild laden (loadImg) hat kein Zeitlimit; in Swift eines setzen.
- Wikipedia-, Website- und Profilbilder laufen über padBlob (ausserhalb).

### 7.5 Wikidata-Logo-Suche (wikiCands, nur Anfang bis Z. 5029)
- Basis WD = `https://www.wikidata.org/w/api.php?format=json&origin=*`.
- Name nicht brauchbar → leere Liste.
- Parallel zwei Anfragen:
  - q1 Volltext nur über Einträge mit Logo: `WD&action=query&list=search&srnamespace=0&srlimit=10&srsearch=<name> haswbstatement:P154`
  - q2 Namenssuche: `WD&action=wbsearchentities&type=item&limit=10&language=de&uselang=de&search=<name>`
- Fortsetzung (Auswertung, Bewertung, Commons-Abfrage) ab Z. 5030 im nächsten Abschnitt.

### 7.6 Ausschlussliste WNOT (P31-Werte, keine Firmen: Personen, Figuren, Werke, Orte, Ereignisse …)
Q5, Q95074, Q15632617, Q15773317, Q11424, Q5398426, Q7889, Q482994, Q134556, Q7725634, Q571, Q515, Q70208, Q262166, Q1549591, Q5119, Q42744322, Q486972, Q3957, Q532, Q15284, Q747074, Q4022, Q23397, Q8502, Q1656682, Q13406463, Q4167410, Q17537576, Q3305213, Q1004, Q11032.

### 7.7 Claim-Leser (wclaims(entität, P))
- Alle Claims der Eigenschaft ohne Rang «deprecated».
- Wert: bei Entitäten die ID («Q…»), sonst der Rohwert (Text für URL, Telefon, Datei). Leere Werte entfallen.

---

## 8. Hinweise für den SwiftUI-Nachbau (aus diesem Abschnitt)
- Personen und Kategorien als Entitäten mit UUID. Umbenennen ändert dann nur das Anzeigefeld, und sndRename, mapHolders und ceRename entfallen. Fachregeln (Steuer, Versicherung, Miete) an den Vorbelegungs-Schlüssel binden.
- Vertragspartner als Entität (Name, Web, Logo, Adresse strukturiert). setPartnerAddr und das Zerlegen mit addrSplit entfallen. Für den Import alter Daten addrSplit trotzdem 1:1 übernehmen.
- Inline-Editoren der Datenqualität: `List` mit Zeilen, darin `Picker(.segmented)`, `Picker(.menu)`, `DatePicker`, `TextField` mit `.onSubmit`. Mehrfeld-Editoren als aufklappbare Zeile mit «Übernehmen».
- Kategorien: `List` + `.onMove` / `.onDelete` im `EditMode`, «Sonstiges» nicht löschbar (`.deleteDisabled`).
- Netzwerk: alle Abfragen mit `URLSession` und Zeitlimit (Kurse und Wikidata 8 s, iTunes 9 s, Bilder ca. 10 s). Pro Formular einen Abbruch-Token führen (siehe Funde N3, N9).
