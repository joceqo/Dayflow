import SwiftUI

struct RuntimeConsoleView: View {
  @ObservedObject private var runtimeConsole = RuntimeConsoleStore.shared
  private let bottomAnchorID = "runtime-console-bottom-anchor"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Runtime Logs")
          .font(.custom("InstrumentSerif-Regular", size: 34))
          .foregroundStyle(Color(hex: "2E221B"))

        Spacer()

        Button("Clear") {
          runtimeConsole.clear()
        }
        .buttonStyle(.plain)
        .font(.custom("Nunito-SemiBold", size: 13))
        .foregroundStyle(Color(hex: "B46531"))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
          Capsule(style: .continuous)
            .fill(Color(hex: "F7F3F1"))
        )
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color(hex: "E4D7D0"), lineWidth: 1)
        )
        .pointingHandCursorOnHover(reassertOnPressEnd: true)
      }
      .padding(.horizontal, 18)
      .padding(.top, 16)
      .padding(.bottom, 12)

      if runtimeConsole.entries.isEmpty {
        ContentUnavailableView(
          "No logs yet",
          systemImage: "text.alignleft",
          description: Text("Logs appear here in real time while the app runs.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
              ForEach(Array(runtimeConsole.entries.reversed())) { entry in
                VStack(alignment: .leading, spacing: 4) {
                  HStack(spacing: 8) {
                    Circle()
                      .fill(entry.stream == "stderr" ? Color(hex: "D64545") : Color(hex: "4B84FF"))
                      .frame(width: 8, height: 8)

                    Text(logTimestamp(entry.timestamp))
                      .font(.system(size: 11, weight: .medium, design: .monospaced))
                      .foregroundStyle(Color(hex: "9E8880"))

                    Text(entry.stream.uppercased())
                      .font(.system(size: 10, weight: .semibold, design: .monospaced))
                      .foregroundStyle(Color(hex: "9E8880").opacity(0.85))
                  }

                  Text(entry.message)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(hex: "2E221B"))
                    .textSelection(.enabled)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
              }

              Color.clear
                .frame(height: 1)
                .id(bottomAnchorID)
            }
          }
          .onAppear {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
          }
          .onChange(of: runtimeConsole.entries.count) { _, _ in
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.white)
  }

  private func logTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: date)
  }
}

#Preview {
  RuntimeConsoleView()
}
