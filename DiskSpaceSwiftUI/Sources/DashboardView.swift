import SwiftUI
import Charts

// This view recreates the dashboard cards and wires to DashboardViewModel and existing DiskModel.
struct DashboardView: View {
    @EnvironmentObject var diskModel: DiskModel // reuse scheduling + CLI integration
    @StateObject private var vm = DashboardViewModel()
    @State private var pendingTrash: DSFileItem? = nil
    @State private var showConfirmTrash = false

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

                LazyVGrid(columns: columns, spacing: 16) {
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
                        }
                    }

                    // Usage by type with Charts donut
                    WidgetCard("Usage by File Type", icon: "folder.fill.badge.plus", iconColor: .purple) {
                        VStack(spacing: 12) {
                            Chart(vm.fileTypeUsage) { item in
                                SectorMark(
                                    angle: .value("Percent", item.percent),
                                    innerRadius: .ratio(0.60)
                                )
                                .foregroundStyle(item.color)
                            }
                            .chartLegend(.hidden)
                            .frame(height: 160)

                            VStack(spacing: 8) {
                                ForEach(vm.fileTypeUsage) { item in
                                    HStack {
                                        Text(item.type + ":").foregroundStyle(item.color)
                                        Spacer()
                                        Text("\(Int(item.percent))%")
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                    }

                    // Top Large Files
                    WidgetCard("Top Large Files", icon: "doc.text.fill", iconColor: .red) {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(vm.topFiles.indices, id: \.self) { idx in
                                    let f = vm.topFiles[idx]
                                    HStack {
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
                                        } label: {
                                            Image(systemName: "ellipsis.circle").imageScale(.medium)
                                        }
                                        .menuStyle(.borderlessButton)
                                    }
                                    .padding(.vertical, 10)
                                    .overlay(alignment: .bottom) {
                                        if idx != vm.topFiles.indices.last { Divider() }
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                    }

                    // Historical Trends (from persisted history)
                    WidgetCard("Historical Usage Trends", icon: "chart.line.uptrend.xyaxis", iconColor: .cyan) {
                        VStack(spacing: 12) {
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

                    // Cleanup Opportunities summary uses existing DiskModel problems
                    WidgetCard("Cleanup Opportunities", icon: "sparkles", iconColor: .yellow) {
                        VStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                                .frame(minHeight: 120)
                                .overlay(
                                    VStack(spacing: 8) {
                                        if vm.isScanning { ProgressView().progressViewStyle(.circular) }
                                        if diskModel.problems.isEmpty {
                                            Text(vm.cleanupMessage).foregroundStyle(.secondary)
                                        } else {
                                            VStack(alignment: .leading) {
                                                ForEach(diskModel.problems.prefix(5)) { p in
                                                    HStack { Text(p.description); Spacer(); Text(p.humanSize).foregroundStyle(.orange) }
                                                    Divider()
                                                }
                                            }
                                        }
                                    }
                                    .padding()
                                )
                            HStack {
                                Button { vm.scanFullDisk() } label: {
                                    Label("Scan for Larger Files", systemImage: "magnifyingglass")
                                }.buttonStyle(.bordered)
                                Button { diskModel.autoClean() } label: { Label("Auto Clean", systemImage: "wand.and.stars") }.buttonStyle(.bordered)
                            }
                        }
                    }

                    // Scheduled Cleanup (summary controlled via existing model)
                    WidgetCard("Scheduled Cleanup", icon: "calendar", iconColor: .indigo) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Notifications")
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
                                }), displayedComponents: [.hourAndMinute]).labelsHidden().frame(width: 140)
                                Button("Apply") { diskModel.scheduleAt(Date(timeIntervalSince1970: diskModel.scheduleTime)) }
                            }
                            Text("Current: \(diskModel.scheduledDate.map { DateFormatter.hm.string(from: $0) } ?? "Not scheduled")")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Scan Settings
                    WidgetCard("Scan Settings", icon: "gearshape", iconColor: .gray) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Include system folders (/Applications, /Library)", isOn: $vm.includeSystem)
                            Toggle("Include external volumes", isOn: $vm.includeExternal)
                            HStack {
                                Text("Minimum size")
                                Spacer()
                                Stepper(value: $vm.minSizeMB, in: 0...10240, step: 50) { Text("\(vm.minSizeMB) MB") }
                            }
                            HStack {
                                Toggle("Documents", isOn: $vm.includeDocuments)
                                Toggle("Media", isOn: $vm.includeMedia)
                                Toggle("Archives", isOn: $vm.includeArchives)
                                Toggle("Other", isOn: $vm.includeOther)
                            }
                            VStack(alignment: .leading) {
                                Text("Ignore patterns (comma or newline, case-insensitive)").font(.caption).foregroundStyle(.secondary)
                                TextField("e.g. node_modules, .git, cache", text: $vm.ignorePatternsRaw)
                            }
                            Divider()
                            HStack {
                                Button { vm.addExtraRootViaPanel() } label: { Label("Add Extra Root…", systemImage: "folder.badge.plus") }
                                Spacer()
                                if !vm.extraRoots.isEmpty {
                                    Menu("Extra Roots") {
                                        ForEach(vm.extraRoots, id: \.path) { u in
                                            Button(u.path) { }
                                            Button(role: .destructive) { vm.removeExtraRoot(u) } label: { Text("Remove \(u.lastPathComponent)") }
                                        }
                                    }
                                }
                            }
                            HStack {
                                Button { vm.openFullDiskAccessSettings() } label: { Label("Open Full Disk Access…", systemImage: "lock.shield") }
                                Spacer()
                                Button { vm.scanFullDisk() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                            }
                        }
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
    }
}
