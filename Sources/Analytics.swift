import Foundation
import FirebaseAnalytics

enum Analytics {

    /// Logs through the Firebase SDK. Firebase batches these and uploads them to
    /// app-measurement.com as a compressed binary blob. Launching the app with
    /// -FIRDebugEnabled makes it upload within seconds instead of up to an hour.
    static func sendFirebase(_ event: String, log: @escaping (String) -> Void) {
        FirebaseAnalytics.Analytics.logEvent(event, parameters: [
            "source": "ios_auditor_test" as NSObject,
            "run_id": 1 as NSObject
        ])
        log("FIREBASE \(event)  queued")
    }

    /// Control sample: a plain GA4 Measurement Protocol hit, readable in the URL.
    /// If this appears in the capture but the Firebase blob does not, we know the
    /// problem is Firebase-specific and not the capture itself.
    static func send(_ event: String, log: @escaping (String) -> Void) {
        var comps = URLComponents(string: "https://www.google-analytics.com/g/collect")!
        comps.queryItems = [
            URLQueryItem(name: "v",   value: "2"),
            URLQueryItem(name: "tid", value: "G-IOSAUDIT01"),
            URLQueryItem(name: "cid", value: "1784600000.1099998888"),
            URLQueryItem(name: "en",  value: event),
            URLQueryItem(name: "ep.source", value: "ios_auditor_test"),
            URLQueryItem(name: "epn.build",  value: "1"),
            URLQueryItem(name: "_p",  value: "1")
        ]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: URLRequest(url: url)) { _, resp, err in
            if let err = err { log("ERR  \(event): \(err.localizedDescription)"); return }
            log("GA4  \(event)  ->  HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
        }.resume()
    }
}
