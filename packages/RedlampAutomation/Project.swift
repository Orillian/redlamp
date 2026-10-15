import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Module.automation.name,
    settings: .redlampProject,
    targets: [
        .frameworkTarget(module: .automation),
        .frameworkTestTarget(module: .automation),
    ],
)
