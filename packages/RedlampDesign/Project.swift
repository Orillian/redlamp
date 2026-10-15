import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Module.design.name,
    settings: .redlampProject,
    targets: [
        .frameworkTarget(module: .design),
    ],
)
