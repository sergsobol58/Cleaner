import ProjectDescription

// Сэндбокс выключен осознанно: в песочнице ~/Library/Developer недоступен без
// того, чтобы пользователь выбирал каждую папку вручную. См. спеку.
private let entitlements: Entitlements = .dictionary([
    "com.apple.security.app-sandbox": false,
])

let project = Project(
    name: "Cleaner",
    targets: [
        .target(
            name: "CleanerKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.sobol.CleanerKit",
            deploymentTargets: .macOS("26.0"),
            sources: ["CleanerKit/Sources/**"]
        ),
        .target(
            name: "Cleaner",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.sobol.Cleaner",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleName": "Cleaner",
                "CFBundleDisplayName": "Cleaner",
                "LSMinimumSystemVersion": "26.0",
                "NSHumanReadableCopyright": "",
            ]),
            sources: ["Cleaner/Sources/**"],
            entitlements: entitlements,
            dependencies: [.target(name: "CleanerKit")]
        ),
        .target(
            name: "CleanerKitTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.sobol.CleanerKitTests",
            deploymentTargets: .macOS("26.0"),
            sources: ["CleanerKitTests/**"],
            dependencies: [.target(name: "CleanerKit")]
        ),
    ]
)
