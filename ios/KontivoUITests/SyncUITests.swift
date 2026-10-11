import XCTest

/// iCloud-Sync: Im Build ohne iCloud-Berechtigung (CI, kostenloses Personal Team) zeigt «Mehr → Daten» nur die graue
/// Hinweiszeile, kein Schalter, und die Rückfrage «Alle Daten löschen?» erwähnt iCloud nicht.
final class SyncUITests: KontivoUITestCase {

    func testICloudLineInBuildWithoutICloud() {
        launch("-uiDemo", "-uiTab", "more")
        let line = el("more.icloud.unavailable")
        reveal(line, "Zeile iCloud-Sync")
        XCTAssertEqual(line.label, "iCloud-Sync: in diesem Build aus (Apple Developer Program nötig)")
        XCTAssertFalse(app.switches["more.icloud"].exists, "ohne iCloud-Berechtigung kein Schalter")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Mehr-Daten-iCloud"
        shot.lifetime = .keepAlways
        add(shot)

        tap(button("Alle Daten löschen"), "Alle Daten löschen")
        let alert = app.alerts.firstMatch
        wait(alert, "Rückfrage")
        let mentionsICloud = alert.descendants(matching: .staticText).matching(pred("label CONTAINS %@", "iCloud")).firstMatch
        XCTAssertFalse(mentionsICloud.exists, "Sync ist aus: kein Hinweis auf iCloud")
        tapAlertButton("Abbrechen")
        waitGone(alert, "Rückfrage geschlossen")
    }
}
