import SwiftUI

struct ContentView: View {
    @State private var log: [String] = []
    @State private var started = false
    @State private var round = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("Analytics Auditor").font(.title2).bold()
            Text("Fires Firebase events and plain GA4 hits repeatedly, so a capture cannot miss the upload window.")
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
            guard !started else { return }
            started = true

            // Fire once immediately, then keep firing every 20 seconds.
            //
            // Why repeat: Firebase needs 70+ seconds to initialise on a cold
            // simulator, and only uploads some time after that. A single burst of
            // events at launch gives the capture exactly one narrow chance to see
            // an upload, and it is missed as often as not. Firing on a timer means
            // there is always fresh data queued and several upload opportunities
            // inside the recording window.
            fireRound()
            Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
                fireRound()
            }
        }
    }

    func fireRound() {
        round += 1
        log.insert("--- round \(round) ---", at: 0)
        fireBoth("app_open")
        fireBoth("login")
        fireBoth("purchase")
    }

    // Send the same event two ways:
    //   1. Through the Firebase SDK -> a compressed blob to Google's measurement host
    //   2. As a plain GA4 hit       -> readable in the URL, our control sample
    func fireBoth(_ event: String) {
        Analytics.sendFirebase(event) { line in
            DispatchQueue.main.async { log.insert(line, at: 0) }
        }
        Analytics.send(event) { line in
            DispatchQueue.main.async { log.insert(line, at: 0) }
        }
    }
}
