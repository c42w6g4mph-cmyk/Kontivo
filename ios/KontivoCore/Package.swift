// swift-tools-version:5.9
// Kern der nativen Kontivo-App: Datenmodell, Rechenkern, Texte, Import/Export. Nur Foundation.
import PackageDescription

let package = Package(
    name: "KontivoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KontivoCore", targets: ["KontivoCore"])
    ],
    targets: [
        .target(
            name: "KontivoCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KontivoCoreTests",
            dependencies: ["KontivoCore"],
            // BankFixtures: Kontoauszug-Musterdateien + Erwartungswerte aus der Web-App (Ordnerstruktur bleibt erhalten)
            resources: [.process("Resources"), .copy("BankFixtures")]
        )
    ]
)
