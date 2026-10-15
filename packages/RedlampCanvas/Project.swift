import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Module.canvas.name,
    settings: .redlampProject,
    targets: [
        .frameworkTarget(module: .canvas),
        .frameworkTestTarget(module: .canvas),
    ],
)
