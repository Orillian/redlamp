import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Module.engineAPI.name,
    targets: [
        .frameworkTarget(module: .engineAPI, resources: ["Resources/**"]),
        .frameworkTestTarget(module: .engineAPI),
    ],
)
