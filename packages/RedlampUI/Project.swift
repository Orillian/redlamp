import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Module.ui.name,
    settings: .redlampProject,
    targets: [
        .frameworkTarget(module: .ui),
        .frameworkTestTarget(module: .ui),
    ],
)
