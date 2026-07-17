import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SkillsKernel

// MARK: - Effective-Agent 检视器(M3)
// 选定 平台 × 项目,渲染实际生效的 Agent 资源树。只读:除最近项目列表
//(UserDefaults)外不写入任何文件。数据来自 InspectorViewModel(进程内
// 调用 SkillsKernel),文件跳转(Finder / 编辑器)在本层完成。

struct InspectorView: View {
    @Bindable var model: InspectorViewModel
    @State private var isProjectPickerPresented = false
    @State private var isSpecsDirectoryPickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            selectorBar
            Divider()
            content
        }
        .navigationTitle("检视器")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    model.reloadSpecs()
                    model.rescan()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("重新扫描当前平台与项目")
                .disabled(model.isScanning)
            }
        }
        .fileImporter(
            isPresented: $isProjectPickerPresented,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                model.selectProject(url)
            }
        }
        .fileImporter(
            isPresented: $isSpecsDirectoryPickerPresented,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                model.setSpecsDirectory(url)
            }
        }
        .onChange(of: model.selectedSpecID) {
            model.rescan()
        }
    }

    // MARK: 选择器

    private var selectorBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("平台", selection: $model.selectedSpecID) {
                    ForEach(model.specs) { spec in
                        if spec.loadError == nil {
                            Text(spec.displayName).tag(Optional(spec.id))
                        } else {
                            Text("\(spec.displayName)(无法解析)").tag(Optional(spec.id))
                        }
                    }
                    if model.specs.isEmpty {
                        Text("无可用 spec").tag(Optional<String>.none)
                    }
                }
                .fixedSize()

                specsDirectoryMenu
            }

            HStack(spacing: 8) {
                Text("项目")
                    .foregroundStyle(.secondary)
                projectMenu
            }
            .font(.callout)
        }
        .padding(10)
    }

    private var specsDirectoryMenu: some View {
        Menu {
            Button("使用内置 specs") {
                model.setSpecsDirectory(nil)
            }
            .disabled(model.specsDirectoryOverride == nil)
            Button("选择 specs 目录…") {
                isSpecsDirectoryPickerPresented = true
            }
        } label: {
            if let override = model.specsDirectoryOverride {
                Label(abbreviate(override.path), systemImage: "folder.badge.gearshape")
            } else {
                Label("内置 specs", systemImage: "shippingbox")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("adapter spec 的读取目录(默认使用应用内置副本;仅本次会话有效)")
    }

    private var projectMenu: some View {
        Menu {
            Button("选择项目目录…") {
                isProjectPickerPresented = true
            }
            if !model.recentProjects.isEmpty {
                Divider()
                ForEach(model.recentProjects, id: \.self) { path in
                    Button(abbreviate(path)) {
                        model.selectProject(URL(fileURLWithPath: path))
                    }
                }
            }
        } label: {
            if let path = model.projectPath {
                Label(abbreviate(path), systemImage: "folder")
            } else {
                Label("选择项目目录…", systemImage: "folder.badge.plus")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: 主体

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "选择平台与项目",
                systemImage: "eye",
                description: Text("选定 平台 × 项目 后,这里会渲染该 Agent 实际加载的资源树。")
            )
        case .scanning:
            VStack(spacing: 12) {
                ProgressView()
                Text("扫描中…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("扫描失败", systemImage: "xmark.octagon")
            } description: {
                Text(message)
                    .font(.callout)
                    .textSelection(.enabled)
            } actions: {
                Button("重试") { model.rescan() }
            }
        case .loaded(let presentation):
            VStack(spacing: 0) {
                InspectorSummaryBar(summary: presentation.summary)
                Divider()
                resourceList(presentation)
            }
        }
    }

    private func resourceList(_ presentation: InspectorPresentation) -> some View {
        List(selection: $model.selectedRowID) {
            ForEach(presentation.sections) { section in
                Section(section.title) {
                    if section.rows.isEmpty {
                        Text("(无)")
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                    }
                    ForEach(section.rows) { row in
                        InspectorInstanceRowView(row: row)
                            .tag(row.id)
                            .contextMenu {
                                Button("在 Finder 中显示") { revealInFinder(row.path) }
                                Button("用默认编辑器打开") { openInEditor(row.path) }
                            }
                    }
                }
            }
            if !presentation.unmodeled.isEmpty {
                Section("Unmodeled — spec 未建模的可疑条目") {
                    ForEach(presentation.unmodeled) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.purple)
                            Text(abbreviate(item.path))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            ScopeBadge(scope: item.scope)
                        }
                        .contextMenu {
                            Button("在 Finder 中显示") { revealInFinder(item.path) }
                            Button("用默认编辑器打开") { openInEditor(item.path) }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

// MARK: - Summary 统计条

private struct InspectorSummaryBar: View {
    let summary: InspectorSummary

    var body: some View {
        HStack(spacing: 14) {
            stat("资源", summary.resources, .primary)
            stat("生效", summary.active, .green)
            stat("遮蔽", summary.shadowed, .secondary)
            stat("缺失", summary.missing, .orange)
            stat("未建模", summary.unmodeled, .purple)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 资源实例行

private struct InspectorInstanceRowView: View {
    let row: InspectorInstanceRow

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .foregroundStyle(row.status == .shadowed ? .secondary : .primary)
                    .lineLimit(1)
                subtitle
            }
            Spacer()
            if let countText = row.countText {
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if row.lowConfidence {
                TagBadge(text: "低置信", color: .indigo)
                    .help("spec 中该条规则 confidence: low,规则本身可能不准确")
            }
            ScopeBadge(scope: row.scope)
        }
        .padding(.vertical, 1)
    }

    // 三种语义三种视觉:shadowed 灰显、missing 警示色、低置信独立标注
    @ViewBuilder
    private var statusIcon: some View {
        switch row.status {
        case .active:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .shadowed:
            Image(systemName: "circle.slash")
                .foregroundStyle(.secondary)
        case .missing:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch row.status {
        case .shadowed:
            Text("被遮蔽 · 生效方:\(abbreviate(row.shadowedByPath ?? ""))")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .missing:
            Text("缺失 · 期望路径:\(abbreviate(row.path))")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .truncationMode(.middle)
        case .active:
            Text(abbreviate(row.path))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Detail 栏

struct InspectorDetailView: View {
    let model: InspectorViewModel

    var body: some View {
        if let row = model.selectedRow {
            instanceDetail(row)
        } else if let presentation = model.presentation {
            ContentUnavailableView(
                "选择一个资源实例",
                systemImage: "cursorarrow.click",
                description: Text("左侧列表中共 \(presentation.summary.resources) 个资源实例。点击查看来源与状态详情。")
            )
        } else {
            ContentUnavailableView(
                "Effective-Agent 检视器",
                systemImage: "eye",
                description: Text("渲染某平台在某项目下实际加载的资源:生效、遮蔽、缺失与未建模,一览无余。")
            )
        }
    }

    private func instanceDetail(_ row: InspectorInstanceRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    HStack(spacing: 6) {
                        ScopeBadge(scope: row.scope)
                        if row.required {
                            TagBadge(text: "必需", color: .blue)
                        }
                        if row.lowConfidence {
                            TagBadge(text: "低置信", color: .indigo)
                        }
                    }
                }

                detailRow("状态", row.status.inspectorDescription)
                if row.status == .shadowed, let winner = row.shadowedByPath {
                    detailRow("遮蔽方", winner)
                }
                if let countText = row.countText {
                    detailRow("计数", countText)
                }
                detailRow("路径", row.path)
                detailRow("spec 规则", row.ruleId)

                if row.status != .missing {
                    HStack(spacing: 8) {
                        Button {
                            revealInFinder(row.path)
                        } label: {
                            Label("在 Finder 中显示", systemImage: "folder")
                        }
                        Button {
                            openInEditor(row.path)
                        } label: {
                            Label("用默认编辑器打开", systemImage: "square.and.pencil")
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}

// MARK: - 徽标与工具

private struct ScopeBadge: View {
    let scope: ResourceScope

    var body: some View {
        Text(scope.inspectorBadgeText)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch scope {
        case .global:    .blue
        case .project:   .teal
        case .directory: .brown
        }
    }
}

private struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

/// 把 home 前缀缩写为 ~,长路径更可读。
private func abbreviate(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

private func revealInFinder(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}

private func openInEditor(_ path: String) {
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}
