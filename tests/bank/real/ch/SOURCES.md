# Swiss bank export fixtures – sources and verification

All fixtures use **invented data only** (holder "Max Muster", IBANs `CH00…`, fictitious
counterparties, generated QR references with a valid mod-10 check digit). Same scenario in every
account file, Oct 2025 – Sep 2026, opening balance 8'420.35 CHF, closing 53'341.65 CHF:

| Posting | Amount (CHF) | When | Type |
|---|---|---|---|
| Immo Seeblick AG (Miete) | -1850.00 | 1st | Dauerauftrag |
| CSS Kranken-Versicherung AG | -389.60 (Oct–Dec 2025), -412.30 (from Jan 2026) | 1st | LSV+/Lastschrift |
| Swisscom (Schweiz) AG | -79.00 | 20th | eBill (with QRR) |
| NETFLIX.COM | -18.90 | 12th (booked next business day) | Debitkarte |
| Energie Kreuzlingen | -180.50 | 20 Oct / Jan / Apr / Jul | eBill with QR reference |
| SERAFE AG | -335.00 | 31 Jan 2026 | eBill with QR reference |
| Muster Pharma AG (Lohn) | +6850.00 | 25th | credit transfer |
| Migros / Coop Kreuzlingen | -24 to -145 (5-Rappen rounded) | every Saturday, booked Monday | Debitkarte |
| TWINT to Laura Beispiel | -15 to -60 | 8th + 22nd | TWINT P2P |
| Bancomat | -200.00 (6th), -100.00 (17th, odd months) | | ATM |

**Collective order:** on 20.01.2026 Swisscom + Energie are paid as one e-banking *Sammelauftrag*
(-259.50). Bank formats show it as one booking (with sub-rows where the format has them: UBS,
ZKB, LUKB, TKB, Raiffeisen Details, BKB/Cler text, camt `Btch`). Neobank files (neon, Yuh,
Revolut, Wise, Swissquote) have no collective orders and list both payments separately.

**Credit-card files** (PostFinance Visa, UBS CC, Swisscard, Viseca, Migros Bank card) use a
card-only scenario: Netflix + the weekly groceries, plus a monthly "Ihre Zahlung – besten Dank"
credit (24th; 26 May) equal to the previous month's card total. Rent, salary, LSV, TWINT and ATM
are not on cards.

Verification levels:
- **verified** – header, column order, delimiter, quoting, date/number format and
  preamble/footer taken from a real (anonymised) export published in a repository.
- **partially verified** – structure confirmed by a source, but some details (encoding, exact
  wording of booking texts or labels) are assumed.
- **unverified** – reconstructed from parser code, documentation or memory only.

Booking texts are **always partly assumed**: the published real samples are anonymised
(Banana scrambles letters but keeps word lengths, so some keywords could be decoded; others are
reasonable guesses). Treat texts as realistic, not as exact.

Main sources (cloned 2026-10-08):
- [B] BananaAccounting/Switzerland ImportApps – anonymised real export samples per bank in
  `test/testcases/` plus format comments in the importer JS:
  https://github.com/BananaAccounting/Switzerland/tree/master/ImportApps
- [Y] bank2ynab config (column maps, header/footer row counts): https://github.com/bank2ynab/bank2ynab/blob/develop/bank2ynab/data/bank2ynab.conf
- [T] tarioch/beancounttools importers: https://github.com/tarioch/beancounttools/tree/master/src/tariochbctools/importers
- [K] Kokonut-ch/SwissBankCsvParser (bank READMEs; its own fixtures are synthetic):
  https://github.com/Kokonut-ch/SwissBankCsvParser/tree/main/banks
- [N] Dr-Nuke/drnuke-bean (PostFinance 2024+ fixture, ZKB camt.053 v08 importer):
  https://github.com/Dr-Nuke/drnuke-bean
- [F] firefly-iii import-configurations CH: https://github.com/firefly-iii/import-configurations/tree/main/ch
- [E] Evernight/beancount-importers (Wise, Revolut): https://github.com/Evernight/beancount-importers
- [S] SIX Swiss Payment Standards: IG Cash Management SPS 2021 (camt .04)
  https://www.six-group.com/dam/download/banking-services/standardization/sps/ig-cash-management-sps2021-en.pdf
  and delta guide SPS 2022 (camt .08)
  https://www.six-group.com/dam/download/banking-services/standardization/sps/ig-cash-management-delta-guide-sps2022-en.pdf
- XSDs used for validation: https://github.com/genkgo/camt/tree/master/assets

---

## PostFinance

### ch_postfinance.csv – e-finance export since Feb 2024, 7 columns (DE)
- Sources: [B] `pf_import_bank_statement_csv/test/testcases/csv_postfinance_example_format6_20240215-DE.csv` (+ IT/FR/EN variants, `…-noenddate.csv`), [N] `src/drnukebean/importer/pfg.py`, [K] `banks/PostFinance/README.md`.
- Verified: UTF-8 **with BOM**, `;`, preamble `Datum von:;="01.10.2025"` (Excel formula quoting `="…"`), `Datum bis`, `Kategorie`, `Konto`, `Währung`; blank line, header, **blank line**, rows newest first, blank line, `Disclaimer:` + text; Avisierungstext always quoted; debit printed **negative in the "Lastschrift" column**; amounts without trailing zeros (`-33.8`, `6850`); Kategorie like `Wohnen // Nebenkosten`.
- Assumed: Bewegungstyp value `Buchung` (decoded from scrambled word length), PF wording for eBill/TWINT/ATM texts. Card text `KAUF/DIENSTLEISTUNG VOM dd.mm.yyyy KARTEN NR. XXXX1234 …` is verified [N].
- Note: older variant of the same format pads every preamble line with `;;;;;;` and puts `;;;;;;` in the blank lines ([B] JS comment, [K]); not produced here.

### ch_postfinance_saldo.csv – e-finance 2024+, 8 columns with Valuta + Saldo
- Sources: [N] `tests/fixtures/pfg/statement.csv` (anonymised real), [B] `…format6_20240228-FR-B.csv`.
- Verified: no Bewegungstyp column; `Datum;Avisierungstext;Gutschrift in CHF;Lastschrift in CHF;Label;Kategorie;Valuta;Saldo in CHF`; **Saldo only on the first (=latest) row of each booking day**, empty otherwise.

### ch_postfinance_legacy.csv – classic e-finance CSV (until ~2023)
- Sources: [B] `csv_postfinance_example_format1_20170929.csv` (+2016 files), [T] `postfinance/importer.py` (opens with `windows_1252`, 6 columns), tarioch test (EN headers, also ISO dates in 2021+).
- Verified: preamble lines padded with `;;;;`, **two-digit years** (`01.10.25`), header `Buchungsdatum;Avisierungstext;Gutschrift;Lastschrift;Valuta;Saldo`, sparse Saldo, footer `;;;;;` / `Disclaimer:;;;;;` / text (wording decoded from the scrambled sample).
- Partially verified: encoding cp1252 (from [T]; Banana file shows a broken `Währung` byte); preamble label `Buchungsdetails:` decoded.

### ch_postfinance_visa.csv – PostFinance Visa/credit card export (2024+)
- Source: [B] `csv_postfinance_example_format2_CreditCard_20241118-DE.csv` (+EN/FR/IT).
- Verified: BOM, preamble padded to 6 columns, `Bewegungsart:;"=""Alle"""`, header `Rechnungsperiode;Buchungsdatum;Einkaufsdatum;Buchungsdetails;Gutschrift in CHF;Lastschrift in CHF`, period label `Aktuelle Rechnungsperiode` or `dd.mm.yyyy − dd.mm.yyyy` (**U+2212 minus sign**), debits negative, `Disclaimer:;;;;;` directly after the rows (no blank line), no final newline.
- Assumed: payment text, billing period boundaries.

## UBS

### ch_ubs.csv – UBS e-banking CSV since 11.2022 (DE)
- Sources: [B] `ubs_import_bank_statement_csv/test/testcases/csv_ubs_example_format3_de_20241115.csv`, `…_fr_20260731.csv`, `…_it_wdetails_20241111.csv`, `…_de_20221108.csv`; [Y] `[CH UBS Checking account]`.
- Verified: BOM, preamble `Kontonummer:` … `Anzahl Transaktionen in diesem Zeitraum:` then blank line; header ends with `;` (empty 15th column, bank2ynab calls it `Column1`); ISO dates; **Belastung printed negative** even though it is a separate column; Abschlusszeit only for card/ATM; card rows: Buchungsdatum later than Abschlussdatum, Valutadatum = Abschlussdatum; **Buchungsdatum empty for not-yet-booked card payments**; Beschreibung1 = "Name,Adresse", Beschreibung2 = "12345678-0 07/27, Zahlung Debitkarte" / "e-banking-Vergütungsauftrag", Beschreibung3 = "Referenz-Nr. QRR: …, Konto-Nr. IBAN: …, Kosten: …, Transaktions-Nr. …"; **collective order: sub-rows with empty dates and only `Einzelbetrag`**, same Transaktions-Nr.; no final newline.
- Assumed: preamble padding (2024 DE file pads with 13 `;`, 2026 FR file with one – the newer style is used); German wording "Dauerauftrag", "Lastschrift", "Geld senden TWINT".

### ch_ubs_signed.csv – UBS layout 09–11.2022 (one signed amount column)
- Source: [B] `csv_ubs_example_format2_de_20220928.csv` (+EN/FR/IT). Verified structure: `Transaktionsbetrag;Belastung/Gutschrift`, no BOM, no final newline. Short-lived format.

### ch_ubs_legacy.csv – UBS e-banking CSV before 2022 (21 columns)
- Sources: [B] `csv_ubs_example_format1_20161111.csv`, `…_20180831.csv`, `…_20230313_01.csv`; [Y] `Footer Rows = 3`.
- Verified: header (DE), statement metadata repeated on every row, positive Belastung/Gutschrift with **apostrophe thousands separators** (`1'850.00`), Saldo only on some rows, collective-order sub-rows with negative `Einzelbetrag`, footer: row of 20 `;`, `Schlusssaldo;Anfangssaldo` (decoded), values with 9 decimals (`53341.650000000`).
- Partially verified: encoding ISO-8859-1 (2016 sample contains a Latin-1 byte, later samples are UTF-8); some old exports use `,` as delimiter (`…_20230905_03.csv`).

### ch_ubs_creditcard.csv – UBS credit card transactions CSV
- Sources: [B] `csv_ubs_example_formatCc1_20171027.csv` (FR) + JS comment; [Y] `[CH UBS Credit card]` (Header Rows = 2).
- Verified: first line `sep=;`, 13 columns, first data row = balance carry-forward with Gutschrift `0.00`, merchant text in fixed-width blocks (`NAME…  CITY…  CHE`), **purchases positive in Belastung**, **pending authorisations have Betrag but empty Währung/Belastung/Buchung**, trailing empty line.
- Assumed: German column names (FR sample: `Numéro de compte;Numéro de carte;Titulaire de compte/carte;Date d'achat;Texte comptable;Secteur;Montant;Monnaie originale;Cours;Monnaie;Débit;Crédit;Ecriture`), cp1252 + CRLF.

## Credit Suisse (migrated to UBS 2024/25)

### ch_creditsuisse_legacy.csv – CS Direct "Buchungen suchen" export
- Sources: [B] `credit_suisse_import_bank_statement_csv/test/testcases/csv_creditsuisse_example_format4_20230905.csv` (+ `format5_2025…`, JS comments for formats 1–5); [F] `ch/creditsuisse/default.json`.
- Verified: **comma** delimiter, 5 preamble lines (`Erstellt am … CEST`, `Buchungen suchen`, `Konto,"…"`, `Saldo,53'341.65 CHF`, `Buchungen`), header with `Valutasaldo` and `Buchungszeitpunkt`, positive amounts in Belastung/Gutschrift, Text = several comma-joined parts with padding spaces inside one quoted field, Saldo only on first row per date, **footer `Total Spalte,,<sum debit>,<sum credit>,,,,`**, no final newline.
- Assumed: footer spelling (scrambled in source, 2025 sample shows `TOTAL SPALTE`), booking-text words, encoding cp1252.

## Zürcher Kantonalbank

### ch_zkb.csv – "CSV-Export mit Details" (12 columns)
- Sources: [Y] `[CH ZKB Konto CSV-Export (Mit Details)]` (2025, header given verbatim, filename `Kontoauszug yyyymmddhhmmss.csv`); [B] `zkb_import_bank_statement_csv/test/testcases/csv_zkb_example_format3_20220614.csv` (+ format6 with 13 columns incl. duplicate `Zahlungszweck`); [T] ZKB booking-text prefixes (`LSV:`, `Gutschrift:`, `eBanking:`, `E-Rechnung:`).
- Verified: every field quoted incl. header, `;`, positive amounts in `Belastung CHF`/`Gutschrift CHF`, Valuta after Buchungstext, **collective order = total row + detail rows with empty Datum and the item amount in `Betrag Detail`**.
- Assumed: UTF-8 BOM (2022 sample has BOM), "Einkauf ZKB Visa Debit Card Nr. xxxx 1234, …" wording, QR reference in `Referenznummer`.

### ch_zkb_simple.csv – short layout `Datum;Buchungstext;Konto;Whg;Belastung;Gutschrift`
- Sources: [B] `csv_zkb_example_format5_20230223.csv`; [Y] `[CH ZKB Erweiterte Suche]`. Verified structure; cp1252 assumed.

## Raiffeisen

### ch_raiffeisen.csv – e-banking CSV since July 2024
- Sources: [B] `raiffeisen_import_bank_statement_csv/test/testcases/csv_example_format6_20241119.csv` (+ format5 2018–2025 without `Details`); [F] `ch/raiffeisen/default.json`; [K] `banks/Raiffeisen/README.md`.
- Verified: English headers regardless of UI language, IBAN on every row, timestamps `2025-10-01 00:00:00.0`, one signed amount without trailing zeros (`-40.7`), Balance on every row, rows oldest first, no final newline. Details contain amounts with apostrophes (`CHF 1'850.00 -`).
- Partially verified: cp1252 (sample shows Latin-1 bytes replaced); booking-text keywords decoded from scrambled sample ("E-Banking Auftrag (eBill)", "Gutschrift TWINT von", "E-Banking Sammelauftrag mit Einzelbuchungen", "Zahlung für:").
- Not produced: format5 continuation lines (`;;Text…;;;`), which pre-2024 exports use for sub-items.

## Kantonalbanken

### ch_bekb.csv – Berner Kantonalbank
- Sources: [B] `bekb_import_bank_statement_csv/test/testcases/csv_bekb_example_format1_20230908.csv`; [K] `banks/BEKB/README.md`.
- Verified: 12 columns, direction column `Belastung per dd.mm.yyyy` / `Gutschrift per …` (Banana sample literally contains `{date}`), signed Betrag, Saldo every row, counterparty name/address/account in own columns.
- Partially verified: cp1252 (sample shows `Beg�nstigter`); values of Buchungstext beyond `Zahlungseingang`, `Verkaufspunkt/Debitkarte`, `Ihr E-Banking-Auftrag`, `Bancomat/Debitkarte` are assumed.

### ch_lukb.csv – Luzerner Kantonalbank (format since 12.2024)
- Source: [B] `lkb_import_bank_statement_csv/test/testcases/csv_lkb_example_format6_20241231.csv` + JS comments formats 2–6.
- Verified: `Buchung;Valuta;Buchungstext;Detail;Gutschrift;Belastung;Saldo (CHF)` – **Gutschrift before Belastung**; **empty cells contain a single space**; sub-rows of collective bookings start with ` ; ;` and carry the item amount in `Detail`; amounts without trailing zeros; card text `Warenbezug/Dienstleistung / <ref> Bezugsort: … Transaktionsdatum: dd.mm.yy / hh:mm:ss Karten-Nr.: … Betrag: CHF …` (decoded).
- Assumed: UTF-8 without BOM, texts for non-card bookings.

### ch_tkb.csv – Thurgauer Kantonalbank (format since 2024)
- Source: [B] `tkb_import_bank_statement_csv/test/testcases/csv_tkb_example_format4_20240229.csv` + JS comments.
- Verified: `Buchungsdatum;Valutadatum;Auftragsart;Buchungstext;Betrag Einzelzahlung (CHF);Belastung (CHF);Gutschrift (CHF);Saldo in (CHF)`; **Buchungstext is a quoted multi-line field** (name, street, city, country, "Mitteilung: …"); collective debit (`Sammelbelastung e-banking (Anzahl Zahlungen: n / Ref.-Nr. …)`) followed by rows with only `Betrag Einzelzahlung`; no final newline.
- Partially verified: cp1252 (sample shows `Z�rich`); Auftragsart values (`Vergütung` decoded, others assumed).

### ch_akb.csv – Aargauische Kantonalbank (2024)
- Source: [B] `akb_import_bank_statement_csv/test/testcases/csv_akb_example_format3_20241018.csv` (+ format1 with Valuta).
- Verified: BOM, `Buchung;Buchungstext;Belastung;Gutschrift;Saldo CHF;` with **trailing `;` on every line**, apostrophes in amounts and balance, some texts quoted with leading/trailing blanks (`" Zahlungseingang / Ref.-Nr. … "`), no Valuta column, no final newline.
- Assumed: texts other than `Zahlungseingang`/`Belastung e-banking` patterns.

### ch_bkb.csv – Basler Kantonalbank (2024)
- Source: [B] `bkb_import_bank_statement_csv/test/testcases/csv_bkb_example_format2_20240326.csv` (with Valutadatum) and `…_20240327.csv` (without).
- Verified: `Buchungsdatum;Valutadatum;Auftragsart;Buchungstext;Belastungsbetrag (CHF);Gutschriftsbetrag (CHF);Saldo (CHF)`, multi-line quoted text, positive amounts, no final newline. Assumed: cp1252, Auftragsart wording.

### Not produced: St.Galler KB, Alternative Bank Schweiz
No published sample, parser or column description was found. Do not assume their layout; use the
generic split-column/signed-column path. (Other cantonal banks with samples in [B] that were not
requested: BLKB, BCV, BancaStato, NKB, SZKB, Zuger KB, acrevis, CIC, EFG, VZ.)

## Other banks

### ch_migrosbank.csv – Migros Bank account statement (format 2, 2024+)
- Source: [B] `migrosbank_import_bank_statement_csv/test/testcases/csv_migrosbank_example_format2_de_20260301.csv`.
- Verified: BOM, everything quoted, preamble (`Kontoauszug von:`, `bis`, `;`, `Vertrag:`, `Kontonummer / IBAN:`, `Bezeichnung:`, `Saldo:`, `;`, three address lines, `;`, `;`), header `Datum;Buchungstext;Mitteilung;Referenznummer;Betrag;Saldo;Valuta`, signed amount, **Referenznummer unquoted when empty**, oldest first.
- Assumed: booking texts. Older Migros Bank format1 (same shape as Valiant, ISO dates in preamble) not produced.

### ch_migrosbank_card.csv – Migros Bank credit card (Viseca platform)
- Source: [B] `csv_migrosbank_example_formatCC1_en_20250625.csv`; [K] `banks/MigrosBank/README.md`.
- Verified: BOM, comma, **blank line after the header and after every row**, timestamps, **3-decimal amounts**, **purchases positive / payments negative**, `Exchange Rate` column, payment rows without CardId/merchant.

### ch_valiant.csv – Valiant
- Sources: [B] `valiant_import_bank_statement_csv/test/testcases/csv_example_valiant_transactions.csv`; [K] says Migros Bank (old) and Valiant are indistinguishable.
- Verified: preamble lines `Kontoauszug bis: dd.mm.yyyy ;;;` (note the blank before `;`), `Kontonummer: …;;;`, `Saldo: CHF …;;;`, address lines, `;;;` spacers, header `Datum;Buchungstext;Betrag;Valuta`, **two-digit years**, signed amount, newest first, no final newline. Assumed: cp1252, texts.

### ch_cler.csv – Bank Cler (also former Bank Coop; Zak is Cler's app)
- Source: [B] `cler_bank_import_statement_csv/test/testcases/csv_clerbank_example_format1_CHF_20260724.csv` (+ 2024/2025 files, IT/EUR variants).
- Verified: `Buchungsdatum;Auftragsart;Text;Belastungsbetrag (CHF);Gutschriftsbetrag (CHF);Saldo (CHF)` (2025+ without Valuta), Auftragsart `QR-Rechnung` / `Gutschrift`, multi-line quoted Text ending in `Pers. Ref.: …`, currency in the amount headings, newest first. Assumed: cp1252, other Auftragsart values.
- Bank Coop: renamed Bank Cler in 2017 – no separate format. Zak: only PDF statements are evidenced ([T] `zak/importer.py` parses PDF columns `Text, Valuta, Belastung, Gutschrift, Saldo`); no CSV fixture produced.

### ch_neon.csv – neon
- Sources: [Y] `[CH Neon Monthly/Yearly Account Statement]`, [T] `neon/importer.py`, [B] `neonfree_import_bank_statement_csv/test/testcases/neon_example.csv`.
- Verified: all fields quoted, `;`, ISO date, signed amount with 2 decimals, columns incl. `Wise` and `Spaces` (`no`), no currency column, newest first. Assumed: category slugs.

### ch_yuh.csv – Yuh
- Source: [B] `yuh_import_statement_csv/test/testcases/csv_yuh_example_format1_20250218.csv`; [K] `banks/Yuh/README.md`.
- Verified: BOM, upper-case English headers, `DD/MM/YYYY`, **DEBIT negative**, separate DEBIT/CREDIT currency columns, names wrapped in **triple quotes** (`"""Name"""`), trading columns. Assumed: ACTIVITY TYPE values (scrambled in source), sort order.

### ch_revolut.csv – Revolut (CHF account, English UI)
- Sources: [T] `revolut/importer.py`, [Y] `[Revolut]`, [E] `import_revolut.py`.
- Verified: `Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance`, comma, `YYYY-MM-DD HH:MM:SS`, signed amount, oldest first. Assumed: `PENDING` rows have empty Completed Date and Balance; Type values for transfers/top-ups.

### ch_wise.csv – Wise (balance statement CSV)
- Sources: [E] `import_wise.py` (column names), header line quoted in https://mail.kde.org/pipermail/kmymoney/2023-March/004062.html.
- Partially verified: 19-column header (only multi-word names quoted), `dd-mm-yyyy` (dayfirst per [E]), signed amount, IDs `CARD-…`/`TRANSFER-…`. Newer exports add `Exchange To Amount`; the "transaction-history" export ([Y] `[Wise]`, 18 columns) is a different file.

### ch_swissquote.csv – Swissquote
- **Unverified** (no sample found). Reconstructed from memory of the Swissquote transactions export: `Datum;Auftrag #;Transaktionen;Symbol;Name;ISIN;Anzahl;Stückpreis;Kosten;Aufgelaufene Zinsen;Nettobetrag;Saldo;Währung`, `dd-mm-yyyy hh:mm:ss`.

### Radicant, Cembra / Cumulus Mastercard
Only PDF statements are evidenced ([T] `radicant/importer.py`, `cembrastatement/importer.py`). No
CSV fixture produced. Cembra PDF has separate credit/debit columns; radicant PDF uses `dd.mm.yy`
and apostrophes.

## Card issuers

### ch_swisscard.csv – Swisscard (Amex / Cashback), layout since 2024 (DE)
- Sources: [B] `swisscard_import_statement_csv/test/testcases/csv_swisscard_example_format2_de_20260415.csv` (+EN/IT, 2023 8-column layout); [Y] `[CH SwissCard]`; [T] `swisscard/importer.py` (negates Amount); [F] `ch/swisscard/default.json`.
- Verified: comma, header unquoted, all values quoted, `dd.mm.yyyy`, **purchases positive, payments negative** (`IHRE ZAHLUNG – BESTEN DANK` with en dash), `Debit/Kredit` = `Belastung`/`Gutschrift`, Status `Gebucht`.
- Partially verified: `Ausstehend` (decoded), merchant categories.

### ch_viseca.csv – Viseca one (CSV, 2025)
- Source: [B] `viseca_one_transactions_xls/test/testcases/csv_viseca_one_example_format3a_20250611.csv`, `…3b…`.
- Verified: BOM, comma, `TransactionId,CardId,Date,ValutaDate,Amount,…,StateType,Details,Type`, timestamps, 3 decimals, **purchases positive, payments/refunds negative with empty CardId**, `Type` = `merchant`/`fee`, no final newline.
- Note: [K] claims a `;`-separated variant `Date;ValutaDate;TransactionId;…` verified against a real export; Viseca also offers an Excel export with dozens of upper-case columns (`TRANSAKTIONSDATUM,…`, [B] format1/2). Not produced.

## ISO 20022

### ch_camt053_sps2022_v08.xml – camt.053.001.08 (SPS 2022+)
### ch_camt053_sps2021_v04.xml – camt.053.001.04 (SPS ≤ 2021, still delivered by some banks)
### ch_camt054_sps2022_v08.xml – camt.054.001.08 debit notifications (`RptgSrc/Prtry` = `DBTN`)
- Sources: [S] (both IGs), [N] `src/drnukebean/importer/zkb_camt.py` (ZKB delivers .08), XSDs from genkgo/camt. **All three files validate against the ISO XSDs.**
- Swiss specifics used: one `Stmt` per month with mandatory OPBD/CLBD (+CLAV); `BkTxCd/Domn` always present; QR payments: `RmtInf/Strd/CdtrRefInf/Tp/CdOrPrtry/Prtry` = `QRR` + 27-digit `Ref`, and `NtryRef` = QR-IBAN (reference version 4); collective order = one `Ntry` with `NtryDtls/Btch` + 2 `TxDtls`; `GrpHdr/AddtlInf` `SPS/2.2/PROD` resp. `SPS/1.7/PROD` (assumed); camt.054 without `Bal` and without `AddtlNtryInf`.
- Version differences a parser must handle: `.08` wraps parties in `<Pty>` (`RltdPties/Cdtr/Pty/Nm`), `.04` does not (`RltdPties/Cdtr/Nm`); `.08` `<Sts><Cd>BOOK</Cd></Sts>` vs `.04` `<Sts>BOOK</Sts>`; `.08` has `UETR`.
- Assumed: BkTxCd sub-families per transaction type, card data in `RmtInf/Ustrd` + `RltdDts/AccptncDtTm` (real banks may use `CardTx` or `AddtlNtryInf` only, cf. [N]).

---
Note: `tests/bank/samples/ch_camt053.xml` (pre-existing, not touched) does not validate against
the camt.053.001.08 XSD (no `Bal`, element order).
