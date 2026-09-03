import ProjectDescription

// The sandbox is off deliberately: inside it ~/Library/Developer is
// unreachable unless the user picks every folder by hand.
private let entitlements: Entitlements = .dictionary([
    "com.apple.security.app-sandbox": false,
])

let project = Project(
    name: "Cleaner",
    options: .options(developmentRegion: "en"),
    targets: [
        .target(
            name: "CleanerKit",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.sobol.CleanerKit",
            deploymentTargets: .macOS("26.0"),
            sources: ["CleanerKit/Sources/**"],
            resources: ["CleanerKit/Resources/**"]
        ),
        .target(
            name: "Cleaner",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.sobol.Cleaner",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleName": "Cleaner",
                "CFBundleDevelopmentRegion": "en",
                "CFBundleIconName": "AppIcon",
                "CFBundleDisplayName": "Cleaner",
                "LSMinimumSystemVersion": "26.0",
                "NSHumanReadableCopyright": "",
            ]),
            sources: ["Cleaner/Sources/**"],
            resources: ["Cleaner/Resources/**"],
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
