#if DEBUG
import Foundation

// Explicit test mode only. Release builds contain neither the fake transport nor launch hooks.
actor LiveUITestAPI {
    private var scores: [String: JSONValue] = [:]
    private let mode: String
    private var metricsRequests = 0
    private var paginationAttempts = 0
    init(mode: String) { self.mode = mode }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(250))
        let path = request.url!.path
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        var body: Any = ["data": [], "meta": [:]]
        var status = 200
        let now = Date.now.addingTimeInterval(-30).ISO8601Format()
        if path.hasSuffix("/v2/observations") {
            let rows: [[String: Any]]
            if mode.hasPrefix("trace-list") {
                let cursor = items.first { $0.name == "cursor" }?.value
                let page = cursor == "page-2" ? 1 : cursor == "page-3" ? 2 : 0
                if page == 1 {
                    paginationAttempts += 1
                    if mode == "trace-list-retry" && paginationAttempts == 1 {
                        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
                    }
                }
                let startIndex = page * 12
                let count = page == 2 ? 2 : 12
                let durations = [0.701, 0.864, 6.4, 0.934, 1.5, 8.2]
                rows = (startIndex..<(startIndex + count)).map { index in
                    let start = Date.now.addingTimeInterval(-23 * 3600 - Double(index * 10))
                    let duration = durations[index % durations.count]
                    var row: [String: Any] = [
                        "id":"list-root-\(index)", "traceId":"list-\(index)", "name":"handle-customer-message", "type":"AGENT", "isRootObservation":true,
                        "startTime":start.ISO8601Format(.init(includingFractionalSeconds: true)),
                        "endTime":start.addingTimeInterval(duration).ISO8601Format(.init(includingFractionalSeconds: true)),
                        "totalCost":duration > 5 ? 0.002 : 0, "environment":"production"
                    ]
                    if index == 0 { row["input"] = "Trou noir capitaine" }
                    if index == 1 { row["input"] = "Utiliser adresse" }
                    if index == 12 || index == 13 { row["level"] = "ERROR"; row["statusMessage"] = "Provider timeout" }
                    return row
                }
                body = ["data":rows, "meta":page < 2 ? ["cursor":"page-\(page + 2)"] : [:]]
                return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            } else if mode == "review" {
                rows = [
                    ["id":"root", "traceId":"trace-live", "name":"Support agent", "type":"AGENT", "isRootObservation":true, "startTime":now, "endTime":Date.now.ISO8601Format(), "environment":"production", "input":"How do I reset my password?", "output":#"[{"role":"user","content":"Earlier question in transcript"},{"role":"assistant","content":"Choose Forgot password. The link expires after 30 minutes."}]"#],
                    ["id":"retrieval", "traceId":"trace-live", "name":"Password reset", "type":"RETRIEVER", "parentObservationId":"root", "isRootObservation":false, "startTime":now, "endTime":Date.now.ISO8601Format(), "output":#"[{"role":"tool","content":"Reset links are valid for 30 minutes."},{"role":"tool","content":"We never ask for your password by email."}]"#]
                ]
            } else if mode == "trace-detail" || mode == "trace-scores" {
                let start = Date.now.addingTimeInterval(-22 * 3600)
                func timestamp(_ offset: Double) -> String { start.addingTimeInterval(offset).ISO8601Format(.init(includingFractionalSeconds: true)) }
                let output = mode == "trace-scores" ? #"[{"role":"user","content":"Earlier user turn"},{"role":"assistant","content":"Tu commandes à emporter ou en livraison ?"}]"# : "Tu commandes à emporter ou en livraison ?\n\n—\nv2 browse | Reset"
                let traceID = "2966b30641238103ed2c9d5e4dc24c6"
                rows = [
                    ["id":"root", "traceId":traceID, "name":"handle-customer-message", "type":"AGENT", "isRootObservation":true, "startTime":timestamp(0), "endTime":timestamp(0.701), "environment":"production", "input":"Trou noir capitaine", "output":output],
                    ["id":"turn", "traceId":traceID, "name":"conversation-turn", "type":"CHAIN", "parentObservationId":"root", "isRootObservation":false, "startTime":timestamp(0.055), "endTime":timestamp(0.701), "environment":"production"]
                ]
            } else {
                rows = [["id":"root", "traceId":"trace-live", "name":"Live agent", "type":"AGENT", "isRootObservation":true,"startTime":now,"endTime":Date.now.ISO8601Format(),"sessionId":"session-live","environment":"production","input":"Live question","output":"Live answer","promptName":"folder/live","promptVersion":2]]
            }
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
                if view == "scores-numeric" {
                    if mode == "quality" {
                        body = ["data": [
                            ["name":"cart_expected","dataType":"BOOLEAN","avg_value":0.625,"count_count":24],
                            ["name":"cart_expected","dataType":"NUMERIC","avg_value":4.2,"count_count":12],
                            ["name":"support_answer_relevance_and_completeness","dataType":"NUMERIC","avg_value":0.9,"count_count":8]
                        ]]
                    } else { body = ["data":[["name":"human","dataType":"BOOLEAN","avg_value":0.8,"count_count":5]]] }
                }
                else if dimensions.contains(where: { $0["field"] == "level" }) { body = ["data":[["level":"DEFAULT","count_count":10,"sum_totalCost":0.2,"time_dimension":now]]] }
                else { body = ["data":[["count_count":1,"p95_latency":3200,"time_dimension":now,"name":"step","traceName":"Live agent","providedModelName":"live-model","sum_totalCost":0.2]]] }
            }
        } else if path.hasSuffix("/v2/prompts") {
            body = ["data":[["name":"folder/live","type":"text","versions":[1,2],"labels":["production","latest"],"lastUpdatedAt":now]],"meta":["page":1,"totalPages":1]]
        } else if path.contains("/v2/prompts/") {
            let version = items.first { $0.name == "version" }?.value.flatMap(Int.init) ?? (items.first { $0.name == "label" }?.value == "production" ? 1 : 2)
            body = ["name":"folder/live","type":"text","version":version,"labels":[version == 1 ? "production" : "latest"],"prompt":version == 1 ? "Original prompt." : "Improved prompt."]
        } else if path.hasSuffix("/v3/scores") {
            if mode == "trace-detail" || mode == "trace-scores" {
                let subject: [String: Any] = ["kind":"trace", "id":"2966b30641238103ed2c9d5e4dc24c6"]
                var rows: [[String: Any]] = [["id":"review", "name":"salle215-review-thumbs", "dataType":"BOOLEAN", "value":true, "subject":subject]]
                if mode == "trace-scores" {
                    rows += [
                        ["id":"expected", "name":"cart_expected", "dataType":"BOOLEAN", "value":false, "subject":subject],
                        ["id":"relevance", "name":"support_answer_relevance_and_completeness", "dataType":"NUMERIC", "value":0.87, "comment":"Evaluator note", "subject":subject],
                        ["id":"topic", "name":"topic", "dataType":"CATEGORICAL", "value":"On-topic", "subject":subject]
                    ]
                }
                body = ["data":rows, "meta":[:]]
                return (try JSONSerialization.data(withJSONObject:body), HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
            }
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
