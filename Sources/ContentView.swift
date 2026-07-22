import SwiftUI

struct ContentView: View {
    @State private var log: [String] = []

    var body: some View {
        VStack(spacing: 14) {
            Text("Analytics Auditor")
                .font(.title2).bold()
            Text("iOS capture test. Each button sends one analytics event immediately.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Fire test_event") { fire("test_event") }
                .buttonStyle(.borderedProminent)
            Button("Fire login") { fire("login") }
                .buttonStyle(.bordered)
            Button("Fire purchase") { fire("purchase") }
                .buttonStyle(.bordered)

            Divider()
            Text("Sent so far").font(.caption).foregroundColor(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(log.indices, id: \.self) { i in
                        Text(log[i]).font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    func fire(_ event: String) {
        Analytics.send(event) { line in
            DispatchQueue.main.async { log.insert(line, at: 0) }
        }
    }
}
