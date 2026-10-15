import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: Module.document.name,
    settings: .redlampProject,
    targets: [
        .frameworkTarget(module: .document, extraDependencies: libJXLDependencies),
        .frameworkTestTarget(module: .document),
    ],
)
