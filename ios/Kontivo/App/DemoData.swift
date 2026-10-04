import Foundation
import KontivoCore

#if DEBUG
/// Beispieldaten für Bildschirmfotos und Tests (nur in Debug-Builds, Start mit «-uiDemo»).
/// Inhalt = Web-Backup mit erfundenen Verträgen, läuft durch denselben Import wie echte Web-Backups.
enum DemoData {
    static func make(today: Day) -> AppData? {
        guard let d = json.data(using: .utf8) else { return nil }
        return try? WebImport.importBackup(d, today: today).data
    }

    static let json = #"""
{
 "app": "vertraege",
 "version": 2,
 "exported": "2026-10-03T08:00:00Z",
 "settings": {
  "home": "CHF",
  "onboarded": 1,
  "holders": [
   "Sinan",
   "Lara"
  ],
  "senders": {
   "Sinan": {
    "first": "Sinan",
    "last": "Muster",
    "street": "Seestrasse 12",
    "zip": "8280",
    "city": "Kreuzlingen",
    "country": ""
   }
  }
 },
 "contracts": {
  "a": {
   "partner": "Swisscom",
   "label": "Handy",
   "cat": "Mobilfunk & Internet",
   "amount": 59.9,
   "cur": "CHF",
   "cycle": 1,
   "due": "2026-10-15",
   "notice": 60,
   "noticeU": "d",
   "cancTerm": "m",
   "holders": [
    "Sinan"
   ],
   "status": "active",
   "start": "2024-03-01",
   "custNo": "12345"
  },
  "b": {
   "partner": "Netflix",
   "label": "Streaming",
   "cat": "Abos & Medien",
   "amount": 18.9,
   "cur": "EUR",
   "cycle": 1,
   "due": "2026-10-15",
   "notice": 0,
   "noticeU": "m",
   "cancTerm": "p",
   "holders": [
    "Sinan",
    "Lara"
   ],
   "status": "active",
   "start": "2024-03-01"
  },
  "c": {
   "partner": "CSS",
   "label": "Krankenkasse",
   "cat": "Versicherung",
   "amount": 412.5,
   "cur": "CHF",
   "cycle": 1,
   "due": "2026-10-15",
   "notice": 60,
   "noticeU": "d",
   "cancTerm": "y",
   "holders": [
    "Sinan"
   ],
   "status": "active",
   "start": "2024-03-01",
   "mand": true,
   "addr": "CSS Versicherung AG\nTribschenstrasse 21\n6005 Luzern"
  },
  "d": {
   "partner": "",
   "label": "Miete",
   "cat": "Wohnen",
   "amount": 2100,
   "cur": "CHF",
   "cycle": 1,
   "due": "2026-10-01",
   "notice": 3,
   "noticeU": "m",
   "cancTerm": "q",
   "holders": [
    "Sinan",
    "Lara"
   ],
   "status": "active",
   "start": "2024-03-01",
   "noWatch": true
  },
  "e": {
   "partner": "Stadtwerke Konstanz",
   "label": "Strom",
   "cat": "Energie & Wasser",
   "amount": 85,
   "cur": "EUR",
   "cycle": 1,
   "due": "2026-10-15",
   "notice": 1,
   "noticeU": "m",
   "cancTerm": "",
   "holders": [
    "Lara"
   ],
   "status": "active",
   "start": "2024-03-01"
  },
  "f": {
   "partner": "Die Mobiliar",
   "label": "Hausrat",
   "cat": "Versicherung",
   "amount": 384,
   "cur": "CHF",
   "cycle": 12,
   "due": "2027-01-01",
   "notice": 3,
   "noticeU": "m",
   "cancTerm": "",
   "holders": [
    "Sinan",
    "Lara"
   ],
   "status": "active",
   "start": "2024-03-01",
   "end": "2026-12-31",
   "renew": "12"
  },
  "g": {
   "partner": "Update Fitness",
   "label": "Fitnessabo",
   "cat": "Freizeit & Sport",
   "amount": 89,
   "cur": "CHF",
   "cycle": 1,
   "due": "2026-10-15",
   "notice": 1,
   "noticeU": "m",
   "cancTerm": "",
   "holders": [
    "Lara"
   ],
   "status": "active",
   "start": "2024-03-01",
   "end": "2026-11-30",
   "renew": "12"
  },
  "h": {
   "partner": "Spotify",
   "label": "Musik",
   "cat": "Abos & Medien",
   "amount": 12.95,
   "cur": "CHF",
   "cycle": 1,
   "due": "2026-10-15",
   "notice": 0,
   "noticeU": "m",
   "cancTerm": "p",
   "holders": [
    "Sinan"
   ],
   "status": "active",
   "start": "2024-03-01",
   "trial": "2026-10-20"
  },
  "i": {
   "partner": "Kanton TG",
   "label": "Einkommensteuer 2026",
   "cat": "Steuern & Gebühren",
   "amount": 1150,
   "cur": "CHF",
   "cycle": 3,
   "due": "2026-11-30",
   "notice": 0,
   "noticeU": "m",
   "cancTerm": "",
   "holders": [
    "Sinan"
   ],
   "status": "active",
   "start": "2024-03-01"
  },
  "j": {
   "partner": "Zattoo",
   "label": "TV",
   "cat": "Abos & Medien",
   "amount": 15,
   "cur": "CHF",
   "cycle": 1,
   "due": "2026-10-15",
   "notice": 2,
   "noticeU": "m",
   "cancTerm": "m",
   "holders": [
    "Sinan"
   ],
   "status": "cancelled",
   "start": "2024-03-01",
   "cancelledAt": "2026-06-30"
  },
  "k": {
   "partner": "SBB",
   "label": "Halbtax",
   "cat": "Mobilität",
   "amount": 190,
   "cur": "CHF",
   "cycle": 12,
   "due": "2027-03-01",
   "notice": 1,
   "noticeU": "m",
   "cancTerm": "a",
   "holders": [
    "Sinan"
   ],
   "status": "active",
   "start": "2024-03-01",
   "prices": [
    {
     "from": "2027-03-01",
     "amount": 199
    }
   ],
   "cancF": "Online / Kundenkonto"
  }
 },
 "incomes": {
  "i1": {
   "name": "Pharma AG",
   "label": "Lohn",
   "cat": "Lohn",
   "amount": 7200,
   "cur": "CHF",
   "cycle": 1,
   "due": "2026-10-25",
   "holders": [
    "Sinan"
   ]
  },
  "i2": {
   "name": "Klinik",
   "label": "Lohn",
   "cat": "Lohn",
   "amount": 4100,
   "cur": "EUR",
   "cycle": 1,
   "due": "2026-10-28",
   "holders": [
    "Lara"
   ]
  }
 },
 "files": {}
}
"""#
}
#endif
