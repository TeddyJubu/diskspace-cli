import SwiftUI
import Charts

// This view recreates the dashboard cards and wires to DashboardViewModel and existing DiskModel.
struct DashboardView: View {
    @EnvironmentObject var diskModel: DiskModel // reuse scheduling + CLI integration
    @StateObject private var vm = DashboardViewModel()
    @State private var pendingTrash: DSFileItem? = nil
    @State private var showConfirmTrash = false

    @State private var selection: Set<DSFileItem> = []
    @State private var batchTrash: [DSFileItem] = []
    @State private var showConfirmBatch = false

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("DiskSpace Dashboard")
                        .font(.system(size: 28, weight: .bold))
                    Spacer()
                    Button { vm.scanFullDisk() } label: { Label("Scan", systemImage: "magnifyingglass") }
                        .buttonStyle(.bordered)
                    Button { diskModel.check() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

                // Two-column masonry-ish layout to avoid large gaps
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        // Overall Usage
                        WidgetCard("Overall Usage", icon: "externaldrive.fill", iconColor: .blue) {
                            VStack(alignment: .leading, spacing: 12) {
                                ProgressBar(progress: vm.usedPercent)
                                Text("\(Int(vm.usedPercent * 100))% Used")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                                    Text(vm.freeText).font(.subheadline.weight(.medium))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))

                                // Fixed height area for scanning progress to prevent card resizing
                                VStack(spacing: 8) {
                                    if vm.isScanning {
                                        ProgressView(value: vm.progress) {
                                            Text(vm.progressDetail)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Button("Cancel Scan", role: .destructive) { vm.cancelScan() }.buttonStyle(.bordered)
                                    }
                                }
                                .frame(minHeight: vm.isScanning ? 60 : 0)
                                .animation(.easeInOut(duration: 0.15), value: vm.isScanning)
                                .clipped()
                            }
                        }
                        .frame(minHeight: 200)

                        // Top Large Files with selection
                        WidgetCard("Top Large Files", icon: "doc.text.fill", iconColor: .red) {
                            VStack(spacing: 8) {
                                HStack {
                                    Button("Reveal Selected") { for f in selection { vm.reveal(f) } }.disabled(selection.isEmpty)
                                    Button("Trash Selected", role: .destructive) { batchTrash = Array(selection); showConfirmBatch = true }.disabled(selection.isEmpty)
                                    Spacer()
                                }
                                ScrollView {
                                    VStack(spacing: 0) {
                                        if vm.topFiles.isEmpty {
                                            Text("No large files found yet. Run a scan to analyze your disk.")
                                                .foregroundStyle(.secondary)
                                                .font(.callout)
                                                .multilineTextAlignment(.center)
                                                .padding(.vertical, 40)
                                        } else {
                                            ForEach(Array(vm.topFiles.enumerated()), id: \.offset) { pair in
                                                let idx = pair.offset
                                                let f = pair.element
                                                HStack {
                                                    Toggle("", isOn: Binding(get: { selection.contains { $0.id == f.id } }, set: { on in if on { selection.insert(f) } else { selection.remove(f) } }))
                                                        .labelsHidden()
                                                        .toggleStyle(.checkbox)
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(f.name).font(.subheadline.weight(.medium))
                                                        Text(f.path).font(.caption).foregroundStyle(.secondary)
                                                    }
                                                    Spacer()
                                                    Text(f.sizeText).font(.subheadline.weight(.medium))
                                                    Menu {
                                                        Button("Reveal in Finder") { vm.reveal(f) }
                                                        Button("Reveal in Terminal") { vm.revealInTerminal(f) }
                                                        Button("Copy Path") { vm.copyPath(f) }
                                                        Button(role: .destructive) { pendingTrash = f; showConfirmTrash = true } label: { Text("Move to Trash…") }
                                                    } label: { Image(systemName: "ellipsis.circle").imageScale(.medium) }
                                                    .menuStyle(.borderlessButton)
                                                }
                                                .padding(.vertical, 10)
                                                .overlay(alignment: .bottom) { if idx != vm.topFiles.indices.last { Divider() } }
                                            }
                                        }
                                    }
                                }
                                .frame(height: 220) // Fixed height to prevent resizing
                            }
                        }
                        .frame(minHeight: 320)

                        // Cleanup Opportunities
                        WidgetCard("Cleanup Opportunities", icon: "sparkles", iconColor: .yellow) {
                            VStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 180) // Fixed height to prevent resizing
                                    .overlay(
                                        VStack(spacing: 8) {
                                            if vm.isScanning { 
                                                VStack(spacing: 8) {
                                                    ProgressView().progressViewStyle(.circular)
                                                    Text("Scanning for opportunities...").foregroundStyle(.secondary).font(.caption)
                                                }
                                            } else if diskModel.problems.isEmpty {
                                                VStack(spacing: 8) {
                                                    Image(systemName: "checkmark.circle")
                                                        .foregroundStyle(.green)
                                                        .font(.title2)
                                                    Text(vm.cleanupMessage)
                                                        .foregroundStyle(.secondary)
                                                        .multilineTextAlignment(.center)
                                                }
                                            } else {
                                                ScrollView {
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        ForEach(diskModel.problems.prefix(3)) { p in
                                                            HStack(alignment: .center) {
                                                                VStack(alignment: .leading) {
                                                                    Text(p.description)
                                                                        .font(.subheadline)
                                                                        .lineLimit(2)
                                                                    Text(p.humanSize).foregroundStyle(.orange).font(.caption)
                                                                }
                                                                Spacer()
                                                                VStack {
                                                                    Button("Run") { diskModel.runProblemCommand(p) }.buttonStyle(.bordered)
                                                                    Button("Copy") { diskModel.copyProblemCommand(p) }
                                                                }
                                                            }
                                                            if p.id != diskModel.problems.prefix(3).last?.id {
                                                                Divider()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding()
                                    )
                                HStack {
                                    Button { vm.scanFullDisk() } label: { Label("Scan for Larger Files", systemImage: "magnifyingglass") }.buttonStyle(.bordered)
                                    Button { diskModel.autoClean() } label: { Label("Auto Clean", systemImage: "wand.and.stars") }.buttonStyle(.bordered)
                                }
                            }
                        }
                        .frame(minHeight: 280)

                        // Scan Settings
                        WidgetCard("Scan Settings", icon: "gearshape", iconColor: .gray) {
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Toggle("Include system folders (/Applications, /Library)", isOn: $vm.includeSystem)
                                    Toggle("Include external volumes", isOn: $vm.includeExternal)
                                    
                                    HStack {
                                        Text("Minimum size")
                                        Spacer()
                                        Stepper(value: $vm.minSizeMB, in: 0...10240, step: 50) { 
                                            Text("\(vm.minSizeMB) MB")
                                                .frame(minWidth: 60, alignment: .trailing)
                                        }
                                    }
                                    
                                    HStack(spacing: 20) {
                                        Toggle("Documents", isOn: $vm.includeDocuments)
                                        Toggle("Media", isOn: $vm.includeMedia)
                                        Toggle("Archives", isOn: $vm.includeArchives)
                                        Toggle("Other", isOn: $vm.includeOther)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Ignore patterns (comma or newline, case-insensitive)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("e.g. node_modules, .git, cache", text: $vm.ignorePatternsRaw)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                                .frame(minHeight: 140)
                                
                                Divider()
                                
                                // Fixed height section for extra roots to prevent layout shifts
                                VStack(spacing: 8) {
                                    HStack {
                                        Button { vm.addExtraRootViaPanel() } label: { 
                                            Label("Add Extra Root…", systemImage: "folder.badge.plus") 
                                        }
                                        .buttonStyle(.bordered)
                                        Spacer()
                                        
                                        // Fixed width for menu to prevent shifts
                                        HStack {
                                            if !vm.extraRoots.isEmpty {
                                                Menu("Extra Roots (\(vm.extraRoots.count))") {
                                                    ForEach(vm.extraRoots, id: \.path) { u in
                                                        Button(action: {}) {
                                                            Label(u.lastPathComponent, systemImage: "folder")
                                                        }
                                                        Button(role: .destructive) { 
                                                            vm.removeExtraRoot(u) 
                                                        } label: { 
                                                            Label("Remove \(u.lastPathComponent)", systemImage: "trash")
                                                        }
                                                        Divider()
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                            } else {
                                                Text("No extra roots")
                                                    .foregroundStyle(.secondary)
                                                    .font(.caption)
                                            }
                                        }
                                        .frame(minWidth: 120, alignment: .trailing)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Button { vm.openFullDiskAccessSettings() } label: { 
                                            Label("Full Disk Access…", systemImage: "lock.shield") 
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Spacer()
                                        
                                        Button { vm.scanFullDisk() } label: { 
                                            Label("Rescan", systemImage: "arrow.clockwise") 
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .frame(minHeight: 60)
                            }
                        }
                        .frame(minHeight: 300)
                    }

                    VStack(spacing: 16) {
                        // Usage by type with Charts donut
                        WidgetCard("Usage by File Type", icon: "folder.fill.badge.plus", iconColor: .purple) {
                            VStack(spacing: 12) {
                                // Fixed height chart area to prevent resizing
                                VStack {
                                    if vm.fileTypeUsage.reduce(0, { $0 + $1.percent }) > 0.0 {
                                        Chart(vm.fileTypeUsage) { item in
                                            SectorMark(
                                                angle: .value("Percent", item.percent),
                                                innerRadius: .ratio(0.60)
                                            )
                                            .foregroundStyle(item.color)
                                        }
                                        .chartLegend(.hidden)
                                    } else {
                                        VStack(spacing: 8) {
                                            Image(systemName: "chart.donut")
                                                .foregroundStyle(.secondary)
                                                .font(.system(size: 40))
                                            Text("No data yet. Run a scan.")
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                }
                                .frame(height: 160)

                                // Fixed height legend area
                                VStack(spacing: 8) {
                                    if vm.fileTypeUsage.isEmpty {
                                        // Placeholder to maintain consistent height
                                        ForEach(0..<4, id: \.self) { _ in
                                            HStack {
                                                Text("—").foregroundStyle(.clear)
                                                Spacer()
                                                Text("—").foregroundStyle(.clear)
                                            }
                                            .font(.callout)
                                        }
                                    } else {
                                        ForEach(vm.fileTypeUsage) { item in
                                            HStack {
                                                Text(item.type + ":").foregroundStyle(item.color)
                                                Spacer()
                                                Text(String(format: "%.1f%%", item.percent))
                                            }
                                            .font(.callout)
                                        }
                                        // Fill remaining space for consistency
                                        ForEach(vm.fileTypeUsage.count..<4, id: \.self) { _ in
                                            HStack {
                                                Text("—").foregroundStyle(.clear)
                                                Spacer()
                                                Text("—").foregroundStyle(.clear)
                                            }
                                            .font(.callout)
                                        }
                                    }
                                }
                                .frame(height: 100)
                            }
                        }
                        .frame(minHeight: 320)

                        // Historical Trends (from persisted history)
                        WidgetCard("Historical Usage Trends", icon: "chart.line.uptrend.xyaxis", iconColor: .cyan) {
                            VStack(spacing: 12) {
                                if vm.history.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "chart.line.uptrend.xyaxis")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 40))
                                        Text("No historical data yet")
                                            .foregroundStyle(.secondary)
                                        Text("Usage trends will appear here over time")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(height: 170)
                                } else {
                                    Chart(vm.history) { p in
                                        AreaMark(
                                            x: .value("Date", p.date),
                                            y: .value("Used", p.usedPercent)
                                        )
                                        .interpolationMethod(.catmullRom)
                                        .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                                        LineMark(
                                            x: .value("Date", p.date),
                                            y: .value("Used", p.usedPercent)
                                        )
                                        .interpolationMethod(.catmullRom)
                                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                        .foregroundStyle(.blue)
                                    }
                                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                                    .chartYScale(domain: 0...100)
                                    .frame(height: 170)
                                }
                            }
                        }
                        .frame(minHeight: 250)

                        // Scheduled Cleanup (summary controlled via existing model)
                        WidgetCard("Scheduled Cleanup", icon: "calendar", iconColor: .indigo) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Notifications")
                                    Spacer()
                                    Toggle("", isOn: $diskModel.notificationsEnabled).labelsHidden()
                                }
                                HStack {
                                    Toggle("Enable schedule", isOn: Binding(get: { diskModel.scheduledDate != nil }, set: { on in
                                        if on { diskModel.scheduleAt(Date(timeIntervalSince1970: diskModel.scheduleTime)) } else { diskModel.unschedule() }
                                    }))
                                    Spacer()
                                    DatePicker("", selection: Binding(get: { Date(timeIntervalSince1970: diskModel.scheduleTime) }, set: { d in
                                        diskModel.scheduleTime = d.timeIntervalSince1970
                                        if diskModel.scheduledDate != nil { diskModel.scheduleAt(d) }
                                    }), displayedComponents: [.hourAndMinute]).labelsHidden().frame(width: 100)
                                    Button("Apply") { diskModel.scheduleAt(Date(timeIntervalSince1970: diskModel.scheduleTime)) }
                                        .buttonStyle(.bordered)
                                }
                                
                                HStack {
                                    Text("Current:")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(diskModel.scheduledDate.map { DateFormatter.hm.string(from: $0) } ?? "Not scheduled")
                                        .foregroundStyle(diskModel.scheduledDate != nil ? .primary : .secondary)
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                        }
                        .frame(minHeight: 160)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        .onAppear { vm.onAppear(); diskModel.check() }
        .confirmationDialog(
            pendingTrash.map { "Move \($0.name) to Trash?" } ?? "",
            isPresented: $showConfirmTrash,
            titleVisibility: .visible
        ) {
            if let item = pendingTrash {
                Button("Move to Trash", role: .destructive) { _ = vm.trash(item); pendingTrash = nil }
            }
            Button("Cancel", role: .cancel) { pendingTrash = nil }
        } message: {
            if let item = pendingTrash { Text("Size: \(item.sizeText)\nPath: \(item.url.path)") }
        }
        .confirmationDialog(
            "Move \(batchTrash.count) items to Trash?",
            isPresented: $showConfirmBatch,
            titleVisibility: .visible
        ) {
            Button("Trash Items", role: .destructive) {
                for f in batchTrash { _ = vm.trash(f) }
                selection.removeAll()
                batchTrash.removeAll()
            }
            Button("Cancel", role: .cancel) { batchTrash.removeAll() }
        } message: {
            if !batchTrash.isEmpty {
                let total = batchTrash.reduce(Int64(0)) { $0 + $1.size }
                Text("Total: \(total.dsHumanBinary)")
            }
        }
    }
}
