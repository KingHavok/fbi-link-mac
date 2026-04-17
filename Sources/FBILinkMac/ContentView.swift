import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddConsole = false
    @State private var showAddURL = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            ConsoleSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                FileList()
                Divider()
                LogPane()
                    .frame(height: 140)
            }
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showAddConsole) { AddConsoleSheet() }
        .sheet(isPresented: $showAddURL) { AddURLSheet() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(model.isServing ? "Stop" : "Send") {
                if model.isServing { model.stop() } else { model.start() }
            }
            .keyboardShortcut(.defaultAction)
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button { showAddConsole = true } label: { Label("Add 3DS", systemImage: "plus.app") }
            Button { showAddURL = true } label: { Label("Add URL", systemImage: "link.badge.plus") }
            Button { pickFiles() } label: { Label("Add Files", systemImage: "doc.badge.plus") }
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if let cia = UTType(filenameExtension: "cia"), let tik = UTType(filenameExtension: "tik") {
            panel.allowedContentTypes = [cia, tik]
        }
        if panel.runModal() == .OK {
            model.addFiles(panel.urls)
        }
    }
}

// MARK: - Console sidebar

private struct ConsoleSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("3DS Consoles") {
                if model.consoles.isEmpty {
                    Text("None yet — add a 3DS by IP.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(model.consoles) { console in
                        ConsoleRow(console: console)
                            .contextMenu {
                                Button("Remove", role: .destructive) { model.removeConsole(console.id) }
                            }
                    }
                }
            }
            if let lan = model.lanAddress {
                Section("This Mac") {
                    LabeledContent("LAN IP", value: lan)
                    if let port = model.serverPort {
                        LabeledContent("Serving on", value: "\(port)")
                    }
                }
                .font(.callout)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ConsoleRow: View {
    let console: Console

    var body: some View {
        HStack {
            Image(systemName: "gamecontroller")
            VStack(alignment: .leading) {
                Text(console.displayName).font(.body)
                Text(statusLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusLabel: String {
        switch console.status {
        case .idle: "Idle"
        case .connecting: "Connecting…"
        case .sending: "Sending…"
        case .completed: "Done"
        case .failed(let message): "Failed: \(message)"
        }
    }
}

// MARK: - File list

private struct FileList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.files.isEmpty {
                DropTarget()
            } else {
                Table(model.files) {
                    TableColumn("Name") { file in
                        HStack {
                            Image(systemName: file.isLocal ? "doc.fill" : "link")
                            Text(file.displayName).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    TableColumn("Progress") { file in
                        if file.byteCount > 0 {
                            ProgressView(value: file.progress)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    TableColumn("Size") { file in
                        Text(file.byteCount > 0 ? byteString(file.byteCount) : "—")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .onDeleteCommand {
                    // TODO: bind selection and delete selected row
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addFiles(urls.filter(\.isFileURL))
            return true
        }
    }

    private func byteString(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

private struct DropTarget: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Drop CIA files here").font(.headline)
            Text("Or use the toolbar to add files, folders, or URLs.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Log pane

private struct LogPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.logLines.enumerated()), id: \.offset) { idx, line in
                        Text(line).font(.system(.caption, design: .monospaced)).id(idx)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.logLines.count) { _, new in
                proxy.scrollTo(new - 1, anchor: .bottom)
            }
        }
        .background(.background.secondary)
    }
}

// MARK: - Sheets

private struct AddConsoleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port: String = "5000"
    @State private var name = ""

    var body: some View {
        Form {
            TextField("IP address", text: $host).textContentType(.URL)
            TextField("Port", text: $port)
            TextField("Name (optional)", text: $name)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 360)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let p = UInt16(port) ?? 5000
                    model.addConsole(host: host, port: p, name: name.isEmpty ? nil : name)
                    dismiss()
                }.disabled(host.isEmpty)
            }
        }
    }
}

private struct AddURLSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = "https://"

    var body: some View {
        Form {
            TextField("URL", text: $urlString)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    if let url = URL(string: urlString) { model.addRemoteURL(url) }
                    dismiss()
                }.disabled(URL(string: urlString) == nil)
            }
        }
    }
}
