import Foundation

// Sends a GA4 Measurement-Protocol style request. It is captured on the wire
// the instant the button is pressed, so Appetize's proxy sees it right away and
// the auditor website decodes v / tid / cid / en / custom params from the query.
enum Analytics {
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
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err { log("ERR  \(event): \(err.localizedDescription)"); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            log("SENT \(event)  ->  HTTP \(code)")
        }.resume()
    }
}
