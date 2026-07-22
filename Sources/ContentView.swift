import SwiftUI

struct ContentView: View {
    @State private var log: [String] = []
    @State private var hasFired = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Analytics Auditor").font(.title2).bold()
            Text("Fires events on launch, and on each button.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

            Button("Fire test_event") { fire("test_event") }.buttonStyle(.borderedProminent)
            Button("Fire login") { fire("login") }.buttonStyle(.bordered)
            Button("Fire purchase") { fire("purchase") }.buttonStyle(.bordered)

            Divider()
            Text("Sent so far").font(.caption).foregroundColor(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(log.indices, id: \.self) { i in
                        Text(log[i]).font(.system(.caption, design: .monospaced))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .onAppear {
            // Fire automatically on launch, so a headless CI run captures traffic
            // with no taps needed. Guarded so it only runs once.
            guard !hasFired else { return }
            hasFired = true
            fire("app_open")
            fire("login")
            fire("purchase")
        }
    }

    func fire(_ event: String) {
        Analytics.send(event) { line in
            DispatchQueue.main.async { log.insert(line, at: 0) }
        }
    }
}
