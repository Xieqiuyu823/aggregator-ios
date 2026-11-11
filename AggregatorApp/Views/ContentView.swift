import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { RunsView() }
                .tabItem { Label("任务", systemImage: "play.rectangle.on.rectangle") }
            NavigationStack { SubscriptionView() }
                .tabItem { Label("订阅", systemImage: "link") }
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct RunsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var submitted = false

    var body: some View {
        List {
            Section {
                Text("任务在你的 GitHub Actions 中运行，结果由仓库配置决定。首次使用请先在设置中填写仓库和令牌。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("运行任务") {
                ForEach(Workflow.allCases, id: \.self) { workflow in
                    Button {
                        Task {
                            submitted = await model.dispatch(workflow)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workflow.title).foregroundStyle(.primary)
                                Text(workflow.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                        }
                    }
                    .disabled(model.isLoading)
                }
            }
            Section {
                if model.isLoading && model.runs.isEmpty {
                    ProgressView("正在连接 GitHub…")
                } else if model.runs.isEmpty {
                    Text("暂无运行记录。下拉刷新以查询。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.runs) { run in
                        if let url = run.htmlURL {
                            Link(destination: url) { RunRow(run: run) }
                        } else {
                            RunRow(run: run)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("最近运行")
                    Spacer()
                    if model.isLoading { ProgressView() }
                }
            } footer: {
                Text("点击记录可在 GitHub 查看详情。新任务可能需要片刻才会出现。")
            }
        }
        .navigationTitle("Aggregator")
        .toolbar {
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("刷新运行记录")
            .disabled(model.isLoading)
        }
        .refreshable { await model.refresh() }
        .alert("任务已提交", isPresented: $submitted) {
            Button("好", role: .cancel) {}
        } message: {
            Text("GitHub 已接受请求。任务可能需要片刻才会出现在运行记录中；请刷新查看结果。")
        }
    }
}

private struct RunRow: View {
    let run: WorkflowRun

    private var statusText: String {
        if let conclusion = run.conclusion, !conclusion.isEmpty { return conclusion }
        return run.status
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(run.name).foregroundStyle(.primary)
                if let date = run.createdAt {
                    Text(date, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusText == "success" ? Color.green : Color.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct SubscriptionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    private var url: URL? {
        guard let url = URL(string: model.subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    var body: some View {
        List {
            Section("订阅链接") {
                if let url {
                    Text(url.absoluteString).textSelection(.enabled).font(.footnote)
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                        copied = true
                    } label: { Label("复制链接", systemImage: "doc.on.doc") }
                    ShareLink(item: url) { Label("分享链接", systemImage: "square.and.arrow.up") }
                    Link(destination: url) { Label("打开链接", systemImage: "safari") }
                } else {
                    Text("在设置中填写工作流输出的订阅链接。")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("链接由你的 Gist 或其他输出位置提供。你可以复制链接并导入支持的客户端。")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .navigationTitle("订阅")
        .alert("链接已复制", isPresented: $copied) { Button("好", role: .cancel) {} }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("GitHub 用户名或组织", text: $model.owner)
                    .textContentType(.username)
                TextField("仓库名，例如 aggregator", text: $model.repository)
                TextField("分支，例如 main", text: $model.branch)
            } header: {
                Text("GitHub 仓库")
            } footer: {
                Text("请填写已配置 Actions 的仓库。分支需要包含对应工作流。")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Section {
                SecureField("GitHub 令牌", text: $model.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("访问令牌")
            } footer: {
                Text("令牌需要有权读取运行记录并触发仓库的 Actions。请勿与他人分享令牌。")
            }
            Section {
                TextField("https://…", text: $model.subscriptionURL, axis: .vertical)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("结果地址")
            } footer: {
                Text("填入你配置的订阅输出链接；运行工作流不会自动填充此地址。")
            }
            Section {
                Button("保存设置") {
                    do {
                        try model.saveSettings()
                        saved = true
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .navigationTitle("设置")
        .alert("设置已保存", isPresented: $saved) { Button("好", role: .cancel) {} }
    }
}
