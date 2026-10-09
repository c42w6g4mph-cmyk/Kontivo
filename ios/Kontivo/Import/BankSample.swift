import Foundation

#if DEBUG
/// Beispiel-Kontoauszug für UI-Tests (`-uiBankSample`): gekürzte PostFinance-CSV aus tests/bank/samples/ch_postfinance.csv
/// (Miete, Krankenkasse, Swisscom, Strom quartalsweise, Fitness, Lohn, einige Einkäufe). Web-Ergebnis (v141, 08.10.2026):
/// 4 Vorschläge – Immo Seeblick AG 1850.00 monatlich, CSS 412.30, Energie Kreuzlingen 180.50 quartalsweise, Swisscom 79.00.
enum BankSample {
    static var csv: Data { Data(text.utf8) }

    static let text = #"""
Datum von:;01.10.2025
Datum bis:;30.09.2026
Bewegungstyp:;Alle Buchungen
Konto:;CH00 0000 0000 0000 0000 0
Währung:;CHF

Datum;Bewegungstyp;Avisierungstext;Gutschrift in CHF;Lastschrift in CHF;Label;Kategorie
30.09.2026;Lastschrift;"KAUF/DIENSTLEISTUNG VOM 30.09.2026 KARTEN NR. XXXX1234 MIGROS KREUZLINGEN";;-123.24;;
25.09.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
23.09.2026;Lastschrift;"KAUF/DIENSTLEISTUNG VOM 23.09.2026 KARTEN NR. XXXX1234 MIGROS KREUZLINGEN";;-39.89;;
20.09.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
16.09.2026;Lastschrift;"KAUF/DIENSTLEISTUNG VOM 16.09.2026 KARTEN NR. XXXX1234 MIGROS KREUZLINGEN";;-89.44;;
09.09.2026;Lastschrift;"KAUF/DIENSTLEISTUNG VOM 09.09.2026 KARTEN NR. XXXX1234 MIGROS KREUZLINGEN";;-90.32;;
01.09.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.09.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.08.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.08.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
01.08.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.08.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.07.2026;Lastschrift;"E-RECHNUNG Energie Kreuzlingen, Akontorechnung Strom Messpunkt 4711";;-180.50;;
25.07.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.07.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
01.07.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.07.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.06.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.06.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
01.06.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.06.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.05.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.05.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
01.05.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.05.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.04.2026;Lastschrift;"E-RECHNUNG Energie Kreuzlingen, Akontorechnung Strom Messpunkt 4711";;-180.50;;
25.04.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.04.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
01.04.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.04.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.03.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.03.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
03.03.2026;Lastschrift;"LASTSCHRIFT UPDATE FITNESS AG Mitgliedschaft Monatsbeitrag";;-79.00;;
01.03.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.03.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.02.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.02.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-82.35;;
03.02.2026;Lastschrift;"LASTSCHRIFT UPDATE FITNESS AG Mitgliedschaft Monatsbeitrag";;-79.00;;
01.02.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.02.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.01.2026;Lastschrift;"E-RECHNUNG Energie Kreuzlingen, Akontorechnung Strom Messpunkt 4711";;-180.50;;
25.01.2026;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.01.2026;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
03.01.2026;Lastschrift;"LASTSCHRIFT UPDATE FITNESS AG Mitgliedschaft Monatsbeitrag";;-79.00;;
01.01.2026;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.01.2026;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-412.30;;
25.12.2025;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.12.2025;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
03.12.2025;Lastschrift;"LASTSCHRIFT UPDATE FITNESS AG Mitgliedschaft Monatsbeitrag";;-79.00;;
01.12.2025;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.12.2025;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-389.60;;
25.11.2025;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.11.2025;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
03.11.2025;Lastschrift;"LASTSCHRIFT UPDATE FITNESS AG Mitgliedschaft Monatsbeitrag";;-79.00;;
01.11.2025;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.11.2025;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-389.60;;
25.10.2025;Lastschrift;"E-RECHNUNG Energie Kreuzlingen, Akontorechnung Strom Messpunkt 4711";;-180.50;;
25.10.2025;Gutschrift;"GUTSCHRIFT VON Muster Pharma AG Lohn";6850.00;;;
20.10.2025;Lastschrift;"E-RECHNUNG Swisscom (Schweiz) AG, Rechnung Kundennummer 9876543";;-79.00;;
03.10.2025;Lastschrift;"LASTSCHRIFT UPDATE FITNESS AG Mitgliedschaft Monatsbeitrag";;-79.00;;
01.10.2025;Lastschrift;"DAUERAUFTRAG Immo Seeblick AG MITTEILUNGEN: Miete Wohnung 3.OG Seestrasse 12";;-1850.00;;
01.10.2025;Lastschrift;"LASTSCHRIFT CSS KRANKEN-VERSICHERUNG AG Prämie Grundversicherung Police 1234567";;-389.60;;
"""#
}
#endif
