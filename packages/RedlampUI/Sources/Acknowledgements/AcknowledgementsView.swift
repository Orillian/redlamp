import RedlampDesign
import RedlampEngineAPI
import SwiftUI

/// The Acknowledgements window's content: a sidebar of entries, and the chosen one's notices and
/// licence texts beside it.
struct AcknowledgementsView: View {
    @Bindable var model: AcknowledgementsModel
    let engine: any EditingEngine

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider()
            ScrollView {
                detail
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .overlayScrollers()
            .id(model.selection)
        }
        .frame(minWidth: 640, minHeight: 400)
        .task {
            model.models = await engine.models()
        }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("Redlamp") {
                Label("Licence and Source Code", systemImage: "doc.text").tag(AcknowledgementsModel.Entry.redlamp)
                Label("Trademarks", systemImage: "c.circle").tag(AcknowledgementsModel.Entry.trademarks)
            }
            Section("Built In") {
                ForEach(model.components) { component in
                    Text(component.name).tag(AcknowledgementsModel.Entry.component(component.name))
                }
            }
            Section("Downloadable Models") {
                if let models = model.models {
                    if models.isEmpty {
                        Text("None in this build").foregroundStyle(.secondary)
                    }
                    ForEach(models) { info in
                        Text(info.name).tag(AcknowledgementsModel.Entry.model(info.id))
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("acknowledgements.sidebar")
    }

    @ViewBuilder private var detail: some View {
        switch model.selection ?? .redlamp {
        case .redlamp:
            redlamp
        case .trademarks:
            trademarks
        case let .component(name):
            if let component = model.components.first(where: { $0.name == name }) {
                componentDetail(component)
            }
        case let .model(id):
            if let info = model.models?.first(where: { $0.id == id }) {
                modelDetail(info)
            }
        }
    }

    private var redlamp: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Redlamp", model.version)
            Text(Acknowledgements.redlampNotice)
            Link("Redlamp's source code on GitHub", destination: model.source)
            texts([Acknowledgements.redlampLicence])
        }
    }

    private var trademarks: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Trademarks", nil)
            ForEach(TrademarkNotice.Kind.allCases, id: \.self) { kind in
                Text(kind.rawValue).font(.headline).padding(.top, 4)
                ForEach(TrademarkNotices.all.filter { $0.kind == kind }) { notice in
                    Text(notice.text)
                }
            }
            Text(TrademarkNotices.filmLooks).padding(.top, 4)
            Text(TrademarkNotices.others)
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("acknowledgements.trademarks")
    }

    private func componentDetail(_ component: Acknowledgements.Component) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(component.name, "\(component.version) · \(component.licence)")
            Text(component.use)
            if let note = component.note {
                Text(note)
            }
            Link("Its source code, as built", destination: component.source)
            texts(component.texts)
        }
    }

    private func modelDetail(_ info: ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(info.name, ModelLicence.summary(info))
            Text(info.purpose)
            if !info.trainingData.isEmpty {
                Text("Trained on \(info.trainingData.joined(separator: "; ")).").foregroundStyle(.secondary)
            }
            switch ModelLicence(info) {
            case let .downloaded(file):
                Text("Its licence, which came with its files:")
                licence((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            case let .withDownload(url):
                Text("Its licence comes with its files when it downloads.")
                Link("Read its licence", destination: url)
            case let .byName(page, standard):
                Text("""
                Its files come with no licence file. Its publisher releases it under the \
                \(info.licence ?? "licence its page names"), as the model's page says.
                """)
                if let page {
                    Link("The model's page", destination: page)
                }
                if let standard, let name = info.licence {
                    Link("The \(name) licence", destination: standard)
                }
            }
        }
    }

    private func heading(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.semibold))
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
    }

    private func texts(_ texts: [Acknowledgements.LicenceText]) -> some View {
        ForEach(texts) { text in
            Text(text.title).font(.headline).padding(.top, 8)
            licence(text.contents() ?? "This build is missing \(text.file).")
        }
    }

    private func licence(_ contents: String) -> some View {
        Text(contents)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
