import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "RedlampCLI",
    settings: .redlampProject,
    targets: [
        .target(
            name: "redlamp",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "\(redlampBundlePrefix).cli",
            deploymentTargets: .macOS(redlampMacOSVersion),
            sources: ["Sources/**"],
            dependencies: [
                Module.engineAPI.dependency,
                Module.engine.dependency,
                Module.services.dependency,
                Module.recipes.dependency,
                Module.document.dependency,
                Module.generative.dependency,
                Module.library.dependency,
                Module.bench.dependency,
            ],
            settings: .settings(base: redlampBaseSettings.merging([
                // Frameworks sit next to the tool in the build products directory.
                "LD_RUNPATH_SEARCH_PATHS": ["@executable_path", "@executable_path/../Frameworks"],
            ]) { $1 }),
        ),
        // The tool's commands run as a person runs them: the tool built beside the tests, in a process of its own.
        .target(
            name: "redlampTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "\(redlampBundlePrefix).cliTests",
            deploymentTargets: .macOS(redlampMacOSVersion),
            sources: ["Tests/**", .glob(.relativeToRoot("tests/support/**"))],
            dependencies: [.target(name: "redlamp"), Module.engineAPI.dependency, Module.document.dependency],
            settings: .settings(base: redlampBaseSettings),
            environmentVariables: ["MTL_DEBUG_LAYER": "1"],
        ),
    ],
)
