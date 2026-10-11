#if DEBUG
import Foundation

// Explicit test mode only. Release builds contain neither the fake transport nor launch hooks.
actor LiveUITestAPI {
    private var scores: [String: JSONValue] = [:]
    private let mode: String
    private var metricsRequests = 0
    init(mode: String) { self.mode = mode }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(250))
        let path = request.url!.path
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        var body: Any = ["data": [], "meta": [:]]
        var status = 200
        let now = Date.now.addingTimeInterval(-30).ISO8601Format()
        if path.hasSuffix("/v2/observations") {
            let rows: [[String: Any]] = [["id":"root", "traceId":"trace-live", "name":"Live agent", "type":"AGENT", "isRootObservation":true,"startTime":now,"endTime":Date.now.ISO8601Format(),"sessionId":"session-live","environment":"production","input":"Live question","output":"Live answer","promptName":"folder/live","promptVersion":2]]
            body = ["data": mode == "empty" ? [] : rows, "meta":[:]]
        } else if path.hasSuffix("/v2/metrics") {
            metricsRequests += 1
            if mode == "limit" || (mode == "cached-limit" && metricsRequests > 4) { status = 429; body = [:] }
            else if mode == "empty" { body = ["data":[]] }
            else {
                let json = items.first { $0.name == "query" }!.value!
                let query = try JSONSerialization.jsonObject(with:Data(json.utf8)) as! [String:Any]
                let view = query["view"] as? String
                let dimensions = query["dimensions"] as? [[String:String]] ?? []
                if view == "scores-numeric" { body = ["data":[["name":"human","dataType":"BOOLEAN","avg_value":0.8,"count_count":5]]] }
                else if dimensions.contains(where: { $0["field"] == "level" }) { body = ["data":[["level":"DEFAULT","count_count":10,"sum_totalCost":0.2,"time_dimension":now]]] }
                else { body = ["data":[["count_count":1,"p95_latency":3200,"time_dimension":now,"name":"step","traceName":"Live agent","providedModelName":"live-model","sum_totalCost":0.2]]] }
            }
        } else if path.hasSuffix("/v2/prompts") {
            body = ["data":[["name":"folder/live","type":"text","versions":[1,2],"labels":["production","latest"],"lastUpdatedAt":now]],"meta":["page":1,"totalPages":1]]
        } else if path.contains("/v2/prompts/") {
            let version = items.first { $0.name == "version" }?.value.flatMap(Int.init) ?? (items.first { $0.name == "label" }?.value == "production" ? 1 : 2)
            body = ["name":"folder/live","type":"text","version":version,"labels":[version == 1 ? "production" : "latest"],"prompt":version == 1 ? "Original prompt." : "Improved prompt."]
        } else if path.hasSuffix("/v3/scores") {
            let encoder = JSONEncoder()
            let data = try encoder.encode(JSONValue.object(["data": .array(scores.values.map { $0 }), "meta": .object([:])]))
            return (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        } else if path.hasSuffix("/scores"), request.httpMethod == "POST" {
            let write = try JSONDecoder().decode(JSONValue.self,from:request.httpBody!)
            guard case .object(var values) = write, let id = values["id"]?.string else { throw LangfuseError.invalidResponse }
            values["value"] = .bool(values["value"]?.number == 1)
            values["subject"] = .object(["kind":.string("trace"),"id":.string("trace-live")])
            scores[id] = .object(values); body = ["id":id]
        } else if request.httpMethod == "DELETE" { scores[request.url!.lastPathComponent] = nil; body = [:] }
        return (try JSONSerialization.data(withJSONObject:body),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Retry-After":"30"])!)
    }
}
#endif
