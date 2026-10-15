import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Module.bench.name,
    settings: .redlampProject,
    targets: [
        .frameworkTarget(module: .bench, resources: ["Resources/**"]),
        .frameworkTestTarget(module: .bench),
    ],
)
