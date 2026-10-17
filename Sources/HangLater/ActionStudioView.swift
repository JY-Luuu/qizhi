import SwiftUI
import AppKit
import PDFKit
import HangLaterCore

extension StudyStatus {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .running: return language.text("正在整理", "Working")
        case .review: return language.text("等你确认", "Ready for review")
        case .failed: return language.text("需要重试", "Needs a retry")
        case .cancelled: return language.text("已取消", "Cancelled")
        case .interrupted: return language.text("可继续", "Ready to resume")
        case .completed: return language.text("已挂上", "On the clothesline")
        }
    }
}

struct ActionStudioView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var studio: StudyCoordinator
    @State private var consent = false
    @State private var citation: SavedCitation?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let run = studio.current, [.review, .completed].contains(run.status) {
                HStack(spacing: 14) {
                    label(store.text("03 / 确认你的下一步", "03 / REVIEW YOUR NEXT STEPS"))
                    Spacer()
                    Text("\(run.sources.count) " + store.text("份资料 ·", "sources ·") + " \(run.budget) min")
                        .font(LeLaboType.label(10)).foregroundStyle(Palette.muted)
                }
            } else {
                HStack(alignment: .top, spacing: 22) {
                    sourcePicker.frame(maxWidth: .infinity, alignment: .topLeading)
                    intention.frame(maxWidth: .infinity, alignment: .topLeading)
                }.disabled(studio.running)
            }
            if let storageError = studio.storageError { message(storageError) }
            if let notice = studio.notice { message(notice) }
            if let run = studio.current { runView(run) }
            else { invitation }
            if !studio.history.isEmpty { history }
        }
        .sheet(isPresented: $studio.showingConnection) { ModelConnectionView(studio: studio, language: store.language) }
        .popover(item: $citation) { EvidenceDetail(citation: $0, language: store.language) }
        .onDisappear { studio.flushDrafts() }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                label(store.text("01 / 选 1–3 份资料", "01 / CHOOSE 1–3 SOURCES"))
                Spacer()
                Text("\(studio.selected.count)/3").font(LeLaboType.label(10)).foregroundStyle(Palette.muted)
            }
            if store.studySources.isEmpty {
                Text(store.text("先晾起网页、PDF，或带正文备注的文字资料。", "Save a webpage, PDF, or a note with source text first."))
                    .font(LeLaboType.copy(12)).foregroundStyle(Palette.muted).padding(.vertical, 14)
                Button(store.text("添加资料", "Add a source")) { store.presentAddOptions() }.buttonStyle(QuietButton())
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.studySources) { source in
                            Button { toggle(source.id) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: studio.selected.contains(source.id) ? "checkmark.square.fill" : "square")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.title).lineLimit(2).foregroundStyle(Palette.ink)
                                        Text(source.url.flatMap { URL(string: $0)?.host } ?? (source.filePath == nil ? store.text("文字备注", "Note") : "PDF / TEXT"))
                                            .font(LeLaboType.label(9)).foregroundStyle(Palette.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.font(LeLaboType.copy(11)).padding(.vertical, 11).padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(studio.selected.contains(source.id) ? Palette.raisedSurface : .clear)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!studio.selected.contains(source.id) && studio.selected.count >= 3)
                            Rectangle().fill(Palette.border.opacity(0.4)).frame(height: 0.5)
                        }
                    }
                }.frame(height: 178)
            }
        }
    }

    private var intention: some View {
        VStack(alignment: .leading, spacing: 12) {
            label(store.text("02 / 留一点时间", "02 / MAKE A LITTLE TIME"))
            TextField(store.text("今天想从这些资料里得到什么？", "What would you like to learn?"), text: $studio.goal, axis: .vertical)
                .lineLimit(3...4).textFieldStyle(.plain).font(LeLaboType.copy(12))
                .padding(12).background(Palette.raisedSurface)
                .overlay(Rectangle().stroke(Palette.border, lineWidth: 0.7))
            HStack {
                Stepper(value: $studio.budget, in: 5...120, step: 5) {
                    Text("\(studio.budget) " + store.text("分钟", "min")).font(LeLaboType.label(12, bold: true))
                }
                Spacer()
                Button(store.text("模型连接", "Model connection")) { studio.showingConnection = true }
                    .buttonStyle(.plain).font(LeLaboType.label(10)).underline()
            }
            Toggle(isOn: $consent) {
                Text(store.text("允许将所选资料正文与目标发送给配置的模型接口。", "Send the selected source text and goal to my configured model provider."))
                    .font(LeLaboType.copy(10)).foregroundStyle(Palette.muted)
            }.toggleStyle(.checkbox)
            HStack(spacing: 12) {
                Button(store.text("生成行动草稿", "Make draft cards")) {
                    let sources = store.studySources.filter { studio.selected.contains($0.id) }
                    studio.start(sources: sources); consent = false
                }.buttonStyle(GreenButton())
                    .disabled(!consent || studio.selected.isEmpty || !studio.canUseStorage || studio.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(consent && !studio.selected.isEmpty && studio.canUseStorage ? 1 : 0.45)
                Button(store.text("试用离线样例", "Try offline sample")) { studio.start(sources: [], demo: true) }
                    .buttonStyle(.plain).font(LeLaboType.label(10)).underline().disabled(!studio.canUseStorage)
            }
        }
    }

    private var invitation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Palette.border).frame(height: 1)
            Text(store.text("先有依据，再有下一步。", "Evidence first. Then the next step."))
                .font(LeLaboType.display(21)).padding(.top, 12)
            Text(store.text("每张草稿都有原文片段、时间和具体产出。你可以改一改，再决定哪些值得挂上。离线样例使用内置资料和固定结果，不调用模型。", "Each draft has a source excerpt, a time estimate and an outcome. Edit it before hanging it up. The offline sample uses built-in sources and fixed results, without a model."))
                .font(LeLaboType.copy(12)).lineSpacing(5).foregroundStyle(Palette.muted)
        }.padding(.top, 8)
    }

    @ViewBuilder private func runView(_ run: StudyRun) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack {
                if run.status == .running { ProgressView().controlSize(.small) }
                Text(run.status.title(store.language)).font(LeLaboType.display(20))
                if run.isDemo {
                    Text(store.text("离线样例 · 非模型生成", "OFFLINE SAMPLE · FIXED OUTPUT"))
                        .font(LeLaboType.label(9, bold: true)).padding(6).overlay(Rectangle().stroke(Palette.border))
                }
                Spacer()
                if run.status == .running {
                    Button(store.text("取消", "Cancel")) { studio.cancel() }.buttonStyle(QuietButton())
                } else {
                    Button(store.text("新计划", "New plan")) { studio.newPlan() }.buttonStyle(.plain).font(LeLaboType.label(10)).underline()
                }
            }.padding(.top, 5)
            Text(run.goal).font(LeLaboType.copy(12)).foregroundStyle(Palette.muted)
            if let failure = run.failure { message(failure) }
            if [.failed, .cancelled, .interrupted].contains(run.status) {
                Text(store.text("已保存 \(run.documents.count)/\(run.sources.count) 份资料快照，尚未创建任务。", "\(run.documents.count)/\(run.sources.count) source snapshots saved. No tasks created."))
                    .font(LeLaboType.copy(11)).foregroundStyle(Palette.muted)
                Button(store.text("从快照重试", "Retry from snapshots")) { studio.retry() }
                    .buttonStyle(QuietButton()).disabled(!studio.canUseStorage)
            }
            if !run.drafts.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 226), spacing: 13, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(Array(run.drafts.enumerated()), id: \.element.id) { index, card in
                        draftCard(card, index: index, run: run)
                    }
                }
            }
            if run.status == .review {
                let total = run.drafts.reduce(0) { $0 + $1.minutes }
                HStack {
                    Text("\(total) / \(run.budget) " + store.text("分钟 · 确认后才创建任务", "min · Tasks are created only after confirmation"))
                        .font(LeLaboType.label(10, bold: true))
                    Spacer()
                    Button(run.isDemo ? store.text("挂上示例卡片", "Hang sample cards") : store.text("确认并挂上", "Confirm & hang")) {
                        studio.flushDrafts(); _ = store.confirmActionPlan()
                    }.buttonStyle(GreenButton())
                        .disabled(total > run.budget || run.drafts.isEmpty || !studio.canUseStorage)
                }
            }
            if run.status == .completed {
                Button(store.text("去晾衣绳看看 →", "See your clothesline →")) { store.destination = .line }.buttonStyle(QuietButton())
            }
            executionDetails(run)
        }
    }

    private func draftCard(_ card: ActionDraft, index: Int, run: StudyRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: "%02d / ACTION", index + 1)).font(LeLaboType.label(9, bold: true))
                Spacer()
                if run.status == .review {
                    Button { studio.moveCardUp(card.id) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                    Button { studio.removeCard(card.id) } label: { Image(systemName: "xmark") }
                }
            }.buttonStyle(.plain)
            TextField("", text: draftBinding(card, \.title), axis: .vertical)
                .font(LeLaboType.display(18)).lineLimit(2...3).disabled(run.status != .review)
            Rectangle().fill(Palette.labelRule.opacity(0.7)).frame(height: 1)
            TextField("", text: draftBinding(card, \.instruction), axis: .vertical)
                .font(LeLaboType.copy(11)).lineLimit(3...6).disabled(run.status != .review)
            Text(store.text("完成时留下", "LEAVE WITH")).font(LeLaboType.label(9, bold: true))
            TextField("", text: draftBinding(card, \.outcome), axis: .vertical)
                .font(LeLaboType.copy(11)).lineLimit(2...4).disabled(run.status != .review)
            HStack {
                Text(store.text("预计", "ESTIMATE")).font(LeLaboType.label(9))
                Stepper(value: Binding(get: { studio.current?.drafts.first { $0.id == card.id }?.minutes ?? card.minutes },
                                      set: { value in studio.editCard(card.id) { $0.minutes = value } }), in: 1...120) {
                    Text("\(card.minutes) min").font(LeLaboType.label(11, bold: true))
                }
            }.disabled(run.status != .review)
            Rectangle().fill(Palette.labelRule.opacity(0.3)).frame(height: 0.6)
            ForEach(Array(card.citations.enumerated()), id: \.offset) { _, ref in
                if let saved = snapshot(ref, run: run) {
                    Button { citation = saved } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(saved.source.title + " · " + saved.passage.locator, systemImage: "text.quote")
                                .font(LeLaboType.label(9, bold: true)).lineLimit(2)
                            Text("“" + saved.quote + "”").font(LeLaboType.copy(10)).lineLimit(3).lineSpacing(3)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .textFieldStyle(.plain).foregroundStyle(Palette.labelInk).padding(17)
        .background(LabelPaper()).overlay(Rectangle().stroke(Palette.labelRule.opacity(0.55), lineWidth: 0.8))
        .environment(\.colorScheme, .light)
    }

    private func draftBinding(_ card: ActionDraft, _ path: WritableKeyPath<ActionDraft, String>) -> Binding<String> {
        Binding(get: { (studio.current?.drafts.first { $0.id == card.id } ?? card)[keyPath: path] },
                set: { value in studio.editCard(card.id) { $0[keyPath: path] = value } })
    }
    private func snapshot(_ ref: ActionCitation, run: StudyRun) -> SavedCitation? {
        guard let doc = run.documents.first(where: { $0.source.id == ref.sourceID }),
              let passage = doc.passages.first(where: { $0.id == ref.passageID }) else { return nil }
        return SavedCitation(source: doc.source, passage: passage, quote: ref.quote, fingerprint: doc.fingerprint)
    }
    private func executionDetails(_ run: StudyRun) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Int(run.elapsedSeconds)) s · \(run.inputTokens) input / \(run.outputTokens) output tokens")
                ForEach(run.events) { event in
                    Text(event.detail).frame(maxWidth: .infinity, alignment: .leading)
                }
                if run.documents.contains(where: \.truncated) {
                    Text(store.text("部分长资料已截取正文，计划仅依据已读取的片段。", "Some long sources were truncated. The plan uses only the extracted passages."))
                }
                Text(store.text("引用校验确认片段出现在快照中，内容与建议仍需你判断。", "Quote validation checks textual presence. Please review the interpretation and advice."))
                Text(store.text("Token 数取服务商返回值；0 也可能表示未返回用量。", "Token counts come from the provider; zero can also mean usage was not reported."))
            }.padding(.vertical, 10)
        } label: { Text(store.text("读取与执行记录", "Sources & execution log")) }
        .font(LeLaboType.label(10)).foregroundStyle(Palette.muted)
    }
    private var history: some View {
        DisclosureGroup {
            ForEach(studio.history) { run in
                Button { studio.open(run) } label: {
                    HStack {
                        Text(run.goal).lineLimit(1)
                        Spacer()
                        Text(run.status.title(store.language))
                        Text(run.createdAt, style: .date)
                    }.padding(.vertical, 7)
                }.buttonStyle(.plain).disabled(studio.running)
            }
        } label: { Text(store.text("最近的计划", "Recent plans")) }
            .font(LeLaboType.label(10)).foregroundStyle(Palette.muted)
    }
    private func label(_ title: String) -> some View { Text(title).font(LeLaboType.label(10, bold: true)).foregroundStyle(Palette.muted) }
    private func message(_ text: String) -> some View {
        Text(text).font(LeLaboType.copy(11)).lineSpacing(4).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raisedSurface).overlay(Rectangle().stroke(Palette.border, lineWidth: 0.7))
    }
    private func toggle(_ id: UUID) {
        if studio.selected.contains(id) { studio.selected.remove(id) }
        else if studio.selected.count < 3 { studio.selected.insert(id) }
    }
}

struct ModelConnectionView: View {
    @ObservedObject var studio: StudyCoordinator
    let language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var config = PlanningConfiguration()
    @State private var key = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(language.text("连接你的模型。", "Connect your model.")).font(LeLaboType.display(26))
            Text(language.text("使用支持工具调用的 Chat Completions 兼容接口。所选资料正文会发送到该服务商，并按其 API 规则计费。聊天订阅不等于 API 额度。", "Use a Chat Completions-compatible endpoint with function calling. Selected source text goes to that provider and may incur API charges. A chat subscription does not provide API credits."))
                .font(LeLaboType.copy(11)).lineSpacing(4).foregroundStyle(Palette.muted)
            field(language.text("完整接口地址", "FULL ENDPOINT URL")) { TextField("https://…/v1/chat/completions", text: $config.endpoint) }
            field(language.text("模型名", "MODEL NAME")) { TextField(language.text("填写服务商提供的模型 ID", "Enter your provider's model ID"), text: $config.model) }
            field("API KEY") { SecureField(language.text("留空保留此接口已有的 Key", "Leave blank to keep this endpoint's saved key"), text: $key) }
            Text(language.text("Key 按接口地址分别存入本机钥匙串，不会写进任务、日志或 GitHub。", "Keys are stored per endpoint in this Mac's Keychain, never in tasks, logs or GitHub."))
                .font(LeLaboType.copy(10)).foregroundStyle(Palette.muted)
            if let error { Text(error).font(LeLaboType.copy(11)).foregroundStyle(Palette.ink) }
            HStack {
                Button(language.text("删除此接口的 Key", "Remove this endpoint's key")) {
                    do { try StudyKeychain.remove(endpoint: config.endpoint); key = ""; error = language.text("Key 已删除。", "Key removed.") }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.plain).font(LeLaboType.label(10)).underline()
                Spacer()
                Button(language.text("取消", "Cancel")) { key = ""; dismiss() }.buttonStyle(QuietButton())
                Button(language.text("保存连接", "Save connection")) {
                    do { try studio.saveConnection(config, newKey: key); key = ""; dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(GreenButton())
            }
        }.padding(30).frame(width: 570).background(Palette.paper).foregroundStyle(Palette.ink)
            .onAppear { config = studio.configuration }
    }
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(LeLaboType.label(10, bold: true)).foregroundStyle(Palette.muted)
            content().textFieldStyle(.plain).font(LeLaboType.copy(12)).padding(11)
                .background(Palette.raisedSurface).overlay(Rectangle().stroke(Palette.border, lineWidth: 0.7))
        }
    }
}

struct EvidenceDetail: View {
    let citation: SavedCitation
    let language: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(citation.source.title).font(LeLaboType.display(21))
            Text(citation.passage.locator).font(LeLaboType.label(10, bold: true)).foregroundStyle(Palette.muted)
            ScrollView { Text(citation.passage.text).font(LeLaboType.copy(13)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 250)
            Text(language.text("这是本次读取时保存的片段，原资料之后可能发生变化。", "This excerpt is a saved snapshot. The original source may have changed."))
                .font(LeLaboType.copy(10)).foregroundStyle(Palette.muted)
            if let address = citation.source.url, let url = TaskInput.webURL(address) {
                Button(language.text("打开原网页 ↗", "Open original webpage ↗")) { NSWorkspace.shared.open(url) }.buttonStyle(QuietButton())
            } else if let path = citation.source.filePath {
                Button(language.text("打开原文件 ↗", "Open original file ↗")) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }.buttonStyle(QuietButton())
            }
        }.padding(24).frame(width: 410).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

struct ActionEvidenceSection: View {
    let origin: ActionTaskOrigin
    let language: AppLanguage
    @State private var citation: SavedCitation?
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                Text(origin.outcome).font(LeLaboType.copy(11))
                ForEach(origin.citations) { saved in
                    Button { citation = saved } label: {
                        Label(saved.source.title + " · " + saved.passage.locator, systemImage: "text.quote")
                    }.buttonStyle(.plain).font(LeLaboType.label(10)).underline()
                }
            }.padding(.top, 10)
        } label: {
            Text(language.text("行动依据", "Action evidence") + " · \(origin.minutes) min" + (origin.isDemo ? " · DEMO" : ""))
                .font(LeLaboType.label(10, bold: true))
        }.popover(item: $citation) { EvidenceDetail(citation: $0, language: language) }
    }
}
