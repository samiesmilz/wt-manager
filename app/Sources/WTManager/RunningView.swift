import AppKit
import SwiftUI
import WTManagerKit

/// What is running right now: every dev server listening on a port, under the
/// worktree it was started in.
///
/// The rest of the window answers "what can I delete". This answers the
/// question asked far more often in a day: which folder is `:3000`, is it the
/// one I think it is, and how do I make it stop. It was `lsof`, a squint at a
/// pid, and `kill`; here it is a row and a button, and the button names what
/// it will signal before it does.
struct RunningView: View {
    @ObservedObject var store: Store
    @State private var pending: Pending? = nil
    @State private var probe = WindowProbe.Box()
    /// Fast enough to feel live, slow enough that reading three process
    /// tables is not itself something running all day.
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    struct Pending: Identifiable {
        let server: RunningServer
        let worktree: String
        var force: Bool = false
        var id: String { server.id + (force ? "!" : "") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Running").font(.system(size: TypeScale.title, weight: .semibold))
                    Text("Dev servers listening on this Mac, under the worktree they were started in. Checked every few seconds while this page is open.")
                        .font(.system(size: TypeScale.body)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let outcome = store.stopOutcome { outcomeBanner(outcome.result, outcome.server) }
                if let error = store.runningError {
                    Banner(tone: .error, symbol: "exclamationmark.triangle", title: "Running servers could not be read",
                           detail: error, outer: 0) {
                        Button("Try again") { store.refreshRunning() }
                    }
                }
                if let running = store.running {
                    if running.worktrees.isEmpty {
                        CardBox {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Nothing is running").font(.system(size: TypeScale.body, weight: .semibold))
                                Text("Start a dev server in any worktree and it appears here with its port.")
                                    .font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 16)
                        }
                    }
                    ForEach(running.worktrees) { wt in card(wt) }
                    if !running.other.isEmpty { others(running.other) }
                } else if store.runningError == nil {
                    Text("Looking for listening ports…")
                        .font(.system(size: TypeScale.body)).foregroundStyle(Palette.muted)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(WindowProbe(box: probe))
        .onAppear { store.refreshRunning() }
        // Only while someone can see it. The view stays mounted when the
        // window is closed to the menu bar, and a poll nobody is reading is
        // three subprocesses every three seconds for nothing.
        .onReceive(tick) { _ in if probe.visible { store.refreshRunning() } }
        .confirmationDialog(pending.map(title) ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { ask in
            Button(ask.force ? "Force stop" : "Stop", role: .destructive) {
                store.stop(ask.server, force: ask.force)
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { ask in
            Text(ask.server.stopDetail(in: ask.worktree)
                 + (ask.force ? " It ignored a polite request. Forcing it gives it no chance to clean up after itself." : ""))
        }
    }

    private func title(_ ask: Pending) -> String {
        (ask.force ? "Force " : "Stop ") + ask.server.command + " on " + ask.server.portLabel + "?"
    }

    // MARK: one worktree

    private func card(_ wt: RunningWorktree) -> some View {
        CardBox {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(wt.name).font(.system(size: TypeScale.section, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        if wt.primary { tag("main checkout", Palette.status("trunk")) }
                    }
                    subtitle(wt)
                }
                Spacer(minLength: 8)
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: wt.path)]) }
                    .buttonStyle(.wt(.quiet)).help(wt.path)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
            ForEach(wt.servers) { server in
                Hairline().padding(.horizontal, 20)
                ServerRow(server: server, busy: store.stopping.contains(server.id)) {
                    pending = Pending(server: server, worktree: wt.name)
                }
            }
            if !wt.env.isEmpty {
                Hairline().padding(.horizontal, 20)
                envLine(wt.env)
            }
        }
    }

    /// The repo and branch, then how far behind its base it is, on a line of its own.
    private func subtitle(_ wt: RunningWorktree) -> some View {
        let fresher: Int? = store.behind(of: wt.path)
        let behind: Int = fresher ?? wt.behind ?? 0
        var lead: [String] = []
        if !wt.repo.isEmpty && wt.repo != wt.name { lead.append(wt.repo) }
        lead.append(wt.branch ?? "detached")
        let label: String? = wt.behindLabel(fresher)
        return VStack(alignment: .leading, spacing: 3) {
            Text(lead.joined(separator: " · ")).font(.system(size: TypeScale.secondary, design: .monospaced))
                .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            if let label {
                Text(label).font(.system(size: TypeScale.secondary))
                    .foregroundStyle(behind > 0 ? Palette.riskInk : Palette.muted)
                    .lineLimit(1)
            }
        }
    }

    /// `Env files   web ✓   admin ✗ missing .env.local`: names, never contents.
    private func envLine(_ env: [EnvFolder]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            GroupLabel("Env files")
            FlowRow(spacing: 14) {
                ForEach(env) { e in envMark(e) }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
    }

    private func envMark(_ e: EnvFolder) -> some View {
        let missing: String = e.missing.joined(separator: ", ")
        let place: String = e.folder.isEmpty ? "The top folder" : e.folder
        let help: String = e.complete ? place + " has " + e.present.joined(separator: ", ")
            : "The main checkout has " + missing + " here and this worktree does not"
        let spoken: String = e.label + (e.complete ? ", env files present" : ", missing " + missing)
        return HStack(spacing: 5) {
            Image(systemName: e.complete ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(e.complete ? Palette.safeInk : Palette.danger)
                .accessibilityHidden(true)
            Text(e.label).font(.system(size: TypeScale.secondary, weight: .medium))
            if !e.complete {
                Text("missing " + missing)
                    .font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.danger)
            }
        }
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    // MARK: everything else

    private func others(_ rows: [RunningServer]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel("Not in a worktree")
            CardBox {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, server in
                    if i > 0 { Hairline().padding(.horizontal, 20) }
                    HStack(spacing: 12) {
                        Circle().fill(Palette.faint).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(server.portLabel).font(.system(size: TypeScale.body, design: .monospaced))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(minWidth: 64, alignment: .leading)
                        Text(server.command).font(.system(size: TypeScale.body)).foregroundStyle(Palette.muted)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("pid \(String(server.pid))").font(.system(size: TypeScale.secondary, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 9)
                }
            }
            Text("Apps and system services. They are listed so a port clash can be explained, and are never stopped from here.")
                .font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func outcomeBanner(_ result: StopResult, _ server: RunningServer) -> some View {
        let tone: BannerTone = result.ended ? .success : (result.canForce ? .warning : .error)
        let symbol: String = result.ended ? "checkmark.circle" : (result.canForce ? "hourglass" : "hand.raised")
        let detail: String = result.ended ? server.portLabel + " is free."
            : (result.canForce ? "It is still holding " + server.portLabel + "." : "Nothing was signalled.")
        Banner(tone: tone, symbol: symbol, title: result.sentence, detail: detail, outer: 0,
               onDismiss: { store.stopOutcome = nil }) {
            if result.canForce {
                Button("Force stop…") {
                    let name: String = store.running?.worktrees.first { $0.servers.contains { $0.id == server.id } }?.name ?? "its worktree"
                    pending = Pending(server: server, worktree: name, force: true)
                }
            }
        }
    }

    private func tag(_ text: String, _ tint: Color) -> some View {
        Text(text).font(.system(size: TypeScale.caption, weight: .semibold))
            .foregroundStyle(Palette.ink(tint))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(Capsule().fill(Palette.wash(tint)))
    }
}

/// One listening process: a live dot, its port, what it is, where it sits.
private struct ServerRow: View {
    let server: RunningServer
    let busy: Bool
    let onStop: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Palette.reclaim).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(server.portLabel).font(.system(size: TypeScale.body, weight: .semibold, design: .monospaced))
                .lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.command).font(.system(size: TypeScale.body)).lineLimit(1).truncationMode(.middle)
                Text(server.folder.isEmpty ? "top of the worktree" : server.folder)
                    .font(.system(size: TypeScale.secondary, design: server.folder.isEmpty ? .default : .monospaced))
                    .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                ProgressView().controlSize(.small)
                Text("Stopping…").font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
            } else {
                if server.stoppable, let url = server.url {
                    Button("Open") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.wt(.quiet)).help(url.absoluteString)
                }
                if server.stoppable {
                    Button("Stop", action: onStop).buttonStyle(.wt(.quiet))
                        .help("Stop \(server.command) (pid \(String(server.pid)))")
                } else {
                    Text("Agent session").font(.system(size: TypeScale.secondary)).foregroundStyle(Palette.muted)
                        .help("A coding agent's own port. End the session from its window.")
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 11)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }
}

/// Lays children out left to right and wraps: an env line with six apps in a
/// narrow window becomes two lines rather than one clipped one.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(subviews, in: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = place(subviews, in: bounds.width)
        for (view, at) in zip(subviews, placed.points) {
            view.place(at: CGPoint(x: bounds.minX + at.x, y: bounds.minY + at.y), proposal: .unspecified)
        }
    }

    private func place(_ subviews: Subviews, in width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                x = 0; y += line + lineSpacing; line = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + line), points)
    }
}

/// Whether the window this view sits in can be seen. SwiftUI keeps a view
/// alive behind a window that was closed to the menu bar, so `onAppear` alone
/// cannot answer it.
struct WindowProbe: NSViewRepresentable {
    final class Box {
        weak var view: NSView?
        var visible: Bool {
            guard let window = view?.window else { return false }
            return window.isVisible && window.occlusionState.contains(.visible)
        }
    }
    let box: Box
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}
