import SwiftUI

struct ContentView: View {
    @State private var log: [String] = []
    @State private var hasFired = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Analytics Auditor").font(.title2).bold()
            Text("Fires Firebase events and plain GA4 hits, so both can be compared in one capture.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

            Button("Fire purchase") { fireBoth("purchase") }.buttonStyle(.borderedProminent)
            Button("Fire login") { fireBoth("login") }.buttonStyle(.bordered)

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
            guard !hasFired else { return }
            hasFired = true
            // Fire on launch so a headless run captures traffic with no taps.
            fireBoth("app_open")
            fireBoth("login")
            fireBoth("purchase")
        }
    }

    // Send the same event two ways:
    //   1. Through the Firebase SDK  -> ends up at app-measurement.com as a blob
    //   2. As a plain GA4 hit        -> readable in the URL, our control sample
    func fireBoth(_ event: String) {
        Analytics.sendFirebase(event) { line in
            DispatchQueue.main.async { log.insert(line, at: 0) }
        }
        Analytics.send(event) { line in
            DispatchQueue.main.async { log.insert(line, at: 0) }
        }
    }
}
