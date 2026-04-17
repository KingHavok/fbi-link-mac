import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddConsole = false
    @State private var showAddURL = false
    @State private var showFileImporter = false

    var body: some View {
        NavigationSplitView {
            ConsoleSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                AggregateBanner()
                Divider()
                FileList()
                Divider()
                LogPane()
                    .frame(height: 140)
            }
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showAddConsole) { AddConsoleSheet() }
        .sheet(isPresented: $showAddURL) { AddURLSheet() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: ContentView.importerTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): model.addFiles(urls)
            case .failure(let err): model.log("File import cancelled: \(err.localizedDescription)")
            }
        }
    }

    static var importerTypes: [UTType] {
        var types: [UTType] = [.folder]
        if let cia = UTType(filenameExtension: "cia") { types.append(cia) }
        if let tik = UTType(filenameExtension: "tik") { types.append(tik) }
        return types
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(model.isServing ? "Stop" : "Send") {
                if model.isServing { model.stop() } else { model.start() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.isServing && (model.files.isEmpty || model.consoles.isEmpty))
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button { model.discoverConsoles() } label: { Label("Discover 3DS", systemImage: "sensor.tag.radiowaves.forward") }
                .help("Scan ARP table for Nintendo MAC prefixes")
            Button { showAddConsole = true } label: { Label("Add 3DS", systemImage: "plus.app") }
            Button { showAddURL = true } label: { Label("Add URL", systemImage: "link.badge.plus") }
            Button { showFileImporter = true } label: { Label("Add Files", systemImage: "doc.badge.plus") }
        }
    }
}

// MARK: - Aggregate banner

private struct AggregateBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.aggregateStats
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ProgressView(value: stats.progress) {
                    Text(headline(stats))
                        .font(.callout)
                }
                .progressViewStyle(.linear)
                if stats.isActive {
                    Text(rateAndETA(stats))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background.secondary)
    }

    private func headline(_ s: TransferStats) -> String {
        guard s.totalBytes > 0 else { return "Idle — add a 3DS and CIA files to begin" }
        let pct = Int((s.progress * 100).rounded())
        return "\(TransferFormat.bytes(s.bytesSent)) of \(TransferFormat.bytes(s.totalBytes)) (\(pct)%)"
    }

    private func rateAndETA(_ s: TransferStats) -> String {
        var bits: [String] = [TransferFormat.rate(s.bytesPerSecond)]
        if let eta = s.etaSeconds { bits.append("ETA \(TransferFormat.duration(eta))") }
        return bits.joined(separator: " · ")
    }
}

// MARK: - Console sidebar

private struct ConsoleSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("3DS Consoles") {
                if model.consoles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No 3DS added yet.").foregroundStyle(.secondary)
                        Text("Click **Discover 3DS** or **Add 3DS** in the toolbar.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
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
            Image(systemName: symbol)
                .foregroundStyle(color)
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

    private var symbol: String {
        switch console.status {
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .sending, .connecting: "arrow.up.circle"
        case .idle: "gamecontroller"
        }
    }

    private var color: Color {
        switch console.status {
        case .completed: .green
        case .failed: .red
        case .sending, .connecting: .accentColor
        case .idle: .secondary
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
                                .foregroundStyle(.secondary)
                            Text(file.displayName)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    TableColumn("Progress") { file in
                        FileProgressCell(file: file)
                    }
                    TableColumn("Size") { file in
                        Text(file.byteCount > 0 ? TransferFormat.bytes(file.byteCount) : "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { $0.isFileURL }
            if !accepted.isEmpty { model.addFiles(accepted) }
            return !accepted.isEmpty
        }
    }
}

private struct FileProgressCell: View {
    @Environment(AppModel.self) private var model
    let file: TransferFile

    var body: some View {
        let stats = model.perFileStats[file.id]
        VStack(alignment: .leading, spacing: 2) {
            if file.byteCount > 0 {
                ProgressView(value: file.progress)
            } else {
                ProgressView().controlSize(.small)
            }
            if let stats, stats.isActive, stats.bytesPerSecond > 0 {
                Text(rowFooter(stats))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rowFooter(_ s: TransferStats) -> String {
        var bits = [TransferFormat.rate(s.bytesPerSecond)]
        if let eta = s.etaSeconds { bits.append("ETA \(TransferFormat.duration(eta))") }
        return bits.joined(separator: " · ")
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
