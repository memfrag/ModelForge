//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import AppKit
import ModelForgeKit

/// The project's types drawn as a graph, with a line from each type to the ones it refers
/// to.
///
/// The same compile the previews are drawn from, so it keeps up with the editor. Clicking
/// a type opens the file it is declared in, at the declaration.
struct TypeGraphView: View {

    @Bindable var session: ProjectSession
    let theme: EditorTheme

    @State private var zoom: Double = 1
    @State private var hovered: String?
    /// Which file the graph is cut down to, or `nil` for the whole project.
    @State private var focus: SourceFileID?
    @AppStorage("graph.showsLabels") private var showsLabels = true
    /// The zoom at which the whole graph fits the visible area, or 1 when it already does.
    @State private var fitZoom: Double = 1

    private var font: NSFont {
        NSFont.systemFont(ofSize: 12, weight: .medium)
    }

    private var graph: TypeGraph {
        guard let focus else { return session.typeGraph }
        return session.typeGraph.focused(on: focus)
    }

    /// Held rather than recomputed in `body`, which runs whenever the pointer moves onto
    /// or off a node.
    @State private var layout = TypeGraphLayout()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(PaneBackground())
        .onChange(of: graph, initial: true) { layout = TypeGraphLayout(graph: graph, font: font) }
        .onChange(of: session.sources.map(\.id)) { _, ids in
            if let focus, !ids.contains(focus) { self.focus = nil }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $focus) {
                Text("Whole project").tag(SourceFileID?.none)
                Divider()
                ForEach(session.sources) { file in
                    Text(file.displayName).tag(SourceFileID?.some(file.id))
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("Show one file's types, with whatever they connect to")

            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Toggle("Labels", isOn: $showsLabels)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Name the field or case each line comes from")

            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(value: $zoom, in: 0.4...2)
                .frame(width: 120)
                .controlSize(.small)
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)

            Button("Fit") { zoom = fitZoom }
                .controlSize(.small)
                .disabled(abs(zoom - fitZoom) < 0.01)
                .help("Zoom so the whole graph is visible")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var summary: String {
        guard !graph.isEmpty else { return "No types yet" }
        let types = graph.nodes.count
        let links = graph.edges.count
        var text = "\(types) \(types == 1 ? "type" : "types"), "
            + "\(links) \(links == 1 ? "reference" : "references")"
        if let focus {
            let context = graph.nodes.count { $0.sourceFile != focus }
            if context > 0 { text += " — \(context) from elsewhere" }
        }
        return text
    }

    // MARK: Canvas

    @ViewBuilder private var content: some View {
        if graph.isEmpty {
            ContentUnavailableView {
                Label("Nothing to draw", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text(session.result == nil
                     ? "Compiling…"
                     : "Declare a model, enum or union and it will appear here.")
            }
        } else {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    canvas(layout)
                        .frame(width: layout.size.width * zoom,
                               height: layout.size.height * zoom)
                }
                .onChange(of: CGSize(width: proxy.size.width, height: proxy.size.height),
                          initial: true) {
                    updateFitZoom(in: proxy.size)
                }
                .onChange(of: layout) { updateFitZoom(in: proxy.size) }
            }
        }
    }

    private func canvas(_ layout: TypeGraphLayout) -> some View {
        ZStack(alignment: .topLeading) {
            edges(layout)
            ForEach(layout.nodes) { positioned in
                nodeView(positioned)
                    .frame(width: positioned.frame.width, height: positioned.frame.height)
                    .position(x: positioned.frame.midX, y: positioned.frame.midY)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .scaleEffect(zoom, anchor: .topLeading)
    }

    private func edges(_ layout: TypeGraphLayout) -> some View {
        Canvas { context, _ in
            for positioned in layout.edges {
                let isLit = hovered == positioned.edge.from || hovered == positioned.edge.to
                var path = Path()
                path.move(to: positioned.start)
                path.addCurve(to: positioned.end,
                              control1: positioned.control1,
                              control2: positioned.control2)

                let style = StrokeStyle(lineWidth: isLit ? 1.8 : 1,
                                        // A reference that closes a cycle is drawn dashed:
                                        // it is the one the layering had to set aside.
                                        dash: positioned.edge.isBackEdge ? [4, 3] : [])
                context.stroke(path,
                               with: .color(isLit ? .accentColor : .secondary.opacity(0.35)),
                               style: style)

                if showsLabels || isLit {
                    draw(positioned.edge.label,
                         at: positioned.midpoint,
                         lit: isLit,
                         in: &context)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
    }

    /// The field or case a line comes from, on a chip so it stays readable where it
    /// crosses another line.
    private func draw(_ label: String,
                      at point: CGPoint,
                      lit: Bool,
                      in context: inout GraphicsContext) {
        var text = context.resolve(
            Text(label)
                .font(.system(size: 9, weight: lit ? .semibold : .regular)))
        text.shading = .color(lit ? .accentColor : .secondary)

        let size = text.measure(in: CGSize(width: 200, height: 40))
        let chip = CGRect(x: point.x - size.width / 2 - 3,
                          y: point.y - size.height / 2 - 1,
                          width: size.width + 6,
                          height: size.height + 2)

        context.fill(Path(roundedRect: chip, cornerRadius: 3),
                     with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.85)))
        context.draw(text, at: point, anchor: .center)
    }

    private func nodeView(_ positioned: TypeGraphLayout.PositionedNode) -> some View {
        let node = positioned.node
        let isCurrentFile = session.selectedFileID == node.sourceFile
        // While focused on a file, everything pulled in from elsewhere is context: still
        // there to give the references something to point at, but visibly not the subject.
        let isContext = focus != nil && node.sourceFile != focus

        return Button {
            session.reveal(node)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol(for: node.kind))
                    .font(.system(size: 10))
                    .foregroundStyle(colour(for: node.kind))
                Text(node.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.background.secondary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(hovered == node.name
                                          ? Color.accentColor
                                          : colour(for: node.kind).opacity(isCurrentFile ? 0.9 : 0.3),
                                          lineWidth: hovered == node.name || isCurrentFile ? 1.5 : 1)
                    }
            }
            .opacity(isContext ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? node.name : (hovered == node.name ? nil : hovered) }
        .help(isContext
              ? "\(node.kind.rawValue) \(node.name) — from \(session.fileName(for: node.sourceFile))"
              : "\(node.kind.rawValue) \(node.name) — in \(session.fileName(for: node.sourceFile))")
    }

    /// Never magnifies: a four-node schema blown up to fill the window looks broken, so
    /// fitting only ever zooms out.
    private func updateFitZoom(in viewport: CGSize) {
        guard !layout.isEmpty, viewport.width > 0, viewport.height > 0 else {
            fitZoom = 1
            return
        }
        fitZoom = min(1, min(viewport.width / layout.size.width,
                             viewport.height / layout.size.height))
    }

    private func symbol(for kind: NamedKind) -> String {
        switch kind {
        case .model: "cube"
        case .enum: "list.bullet"
        case .union: "arrow.triangle.branch"
        case .alias: "arrow.right"
        }
    }

    private func colour(for kind: NamedKind) -> Color {
        switch kind {
        case .model: Color(nsColor: theme.nsColor(for: .typeName))
        case .enum: Color(nsColor: theme.nsColor(for: .enumCase))
        case .union: Color(nsColor: theme.nsColor(for: .keyword))
        case .alias: Color(nsColor: theme.nsColor(for: .attribute))
        }
    }
}
