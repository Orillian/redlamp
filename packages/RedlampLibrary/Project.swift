import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Module.library.name,
    settings: .redlampProject,
    targets: [
        .frameworkTarget(module: .library, extraDependencies: sqliteDependencies),
        .frameworkTestTarget(module: .library),
    ],
)
