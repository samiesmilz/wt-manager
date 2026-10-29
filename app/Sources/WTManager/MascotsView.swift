import SwiftUI
import WTManagerKit

/// The cast, each one large and moving, and everything about the character in
/// one place: who it is, what it wears, and where it goes.
///
/// It was a strip of 26pt portraits that opened under the header and pushed
/// the folders down, with the coat, the floating companion and the wandering
/// scattered through the Appearance menu.
struct MascotsView: View {
    @ObservedObject var store: Store
    @ObservedObject private var pulse = Pulse.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mascots")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Pick the one that keeps you company. Its face tells you how your disk is doing.")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                }
                if let mascot = store.mascot {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
                        ForEach(mascot.figures) { card($0, mascot) }
                        if OwnFace.exists { ownCard }
                    }
                    coats(mascot)
                }
                behaviour
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: cast

    private func card(_ figure: Mascot.Figure, _ mascot: Mascot) -> some View {
        let selected = store.figure == figure.id
        // The chosen one in the coat it wears; the rest in the coat each was
        // drawn in, which is the one choosing it puts on.
        let coat = selected ? store.skin : Mascot.drawnCoats[figure.id] ?? mascot.defaultSkin
        let still = reduceMotion
        return Button { store.figure = figure.id } label: {
            VStack(spacing: 8) {
                SwiftUI.Group {
                    if let image = mascot.image(figure: figure.id, gauge: 0,
                                                eyes: !still && pulse.blinking ? "shut" : "open",
                                                frame: still ? 0 : pulse.wag, skin: coat, tint: "#3fb27f",
                                                fitting: 69, detailed: true, showSignal: false) {
                        Image(nsImage: image).interpolation(.none)
                    }
                }
                .frame(height: 72)
                VStack(spacing: 2) {
                    Text(figure.name).font(.system(size: 12.5, weight: .semibold))
                    // Two lines' room for every tell, so the cards stay one height.
                    Text(figure.tell).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center).lineLimit(2)
                        .frame(height: 28, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Palette.mascot.opacity(0.10) : Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Palette.mascot : Color.primary.opacity(0.08),
                              lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(figure.name), \(figure.tell)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var ownCard: some View {
        let selected = store.figure == Store.ownFigure
        return Button { store.figure = Store.ownFigure } label: {
            VStack(spacing: 8) {
                SwiftUI.Group {
                    if let image = OwnFace.image(fitting: 69, tint: nil) {
                        Image(nsImage: image).interpolation(.none)
                    }
                }
                .frame(height: 72)
                VStack(spacing: 2) {
                    Text("Yours").font(.system(size: 12.5, weight: .semibold))
                    Text("your own picture").font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                        .frame(height: 28, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Palette.mascot.opacity(0.10) : Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Palette.mascot : Color.primary.opacity(0.08),
                              lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your own picture")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: look

    /// What it wears: the coat, or a picture of your own instead.
    @ViewBuilder
    private func coats(_ mascot: Mascot) -> some View {
        divider
        section("Look") {
            if !store.usingOwnImage {
                row("Coat", "The colours the character is drawn in.") { EmptyView() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(mascot.skins.keys.sorted(), id: \.self) { coat in
                        let on = store.skin == coat
                        Button { store.skin = coat } label: {
                            Text(coat).font(.system(size: 11.5, weight: on ? .semibold : .regular))
                                .frame(maxWidth: .infinity).padding(.vertical, 5)
                                .foregroundStyle(on ? Palette.ink(Palette.mascot) : .primary)
                                .background(Capsule().fill(on ? Palette.wash(Palette.mascot) : Color.primary.opacity(0.05)))
                                .overlay(Capsule().strokeBorder(on ? Palette.mascot : .clear, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
                Hairline().padding(.horizontal, 14)
            }
            row("Your own picture", OwnFace.exists ? "Shown in place of a character, with the same status badge."
                                                   : "Any image, drawn as pixels like the cast.") {
                HStack(spacing: 8) {
                    if OwnFace.exists {
                        Button("Forget") {
                            OwnFace.forget()
                            store.figure = mascot.defaultFigure
                        }
                    }
                    Button(OwnFace.exists ? "Choose another…" : "Choose…") { store.chooseOwnImage() }
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: behaviour

    private var behaviour: some View {
        VStack(alignment: .leading, spacing: 22) {
            divider
            section("Behaviour") {
                toggleRow("Show it on the desktop",
                          "A small companion that stays when the window is closed. Click it to open wt-manager.",
                          $store.floatingMascot)
                Hairline().padding(.horizontal, 14)
                toggleRow("Let it wander", "Short strolls across the screen now and then. Off with Reduce Motion.",
                          $store.mascotWanders)
                    .disabled(!store.floatingMascot)
                    .opacity(store.floatingMascot ? 1 : 0.5)
                Hairline().padding(.horizontal, 14)
                toggleRow("Merged pull requests", "It says so when a branch you have checked out lands.",
                          $store.mergeNudges)
                Hairline().padding(.horizontal, 14)
                toggleRow("Celebrate a cleanup", "Pixel sparks and a proud face when space comes back.",
                          $store.celebrationsEnabled)
            }
        }
    }

    // MARK: parts

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
    }

    /// A titled group of rows on one card, the way System Settings does it.
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Palette.muted)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    /// A label with one line of what it means, and its control on the right.
    private func row<C: View>(_ title: String, _ detail: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func toggleRow(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        row(title, detail) {
            Toggle("", isOn: isOn).labelsHidden()
                .toggleStyle(.switch).controlSize(.small)
                .tint(Palette.mascot)
                .accessibilityLabel(title)
        }
    }
}
