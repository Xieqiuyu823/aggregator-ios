import Foundation

/// The workflow files shipped with wzdnzd/aggregator.
enum Workflow: String, CaseIterable, Identifiable {
    case process = "process.yaml"
    case collect = "collect.yaml"
    case refresh = "refresh.yaml"

    var id: String { rawValue }
    var file: String { rawValue }
    var title: String {
        switch self {
        case .process: return "完整处理"
        case .collect: return "收集订阅"
        case .refresh: return "刷新订阅"
        }
    }
    var description: String {
        switch self {
        case .process: return "按配置采集、检测并输出订阅"
        case .collect: return "收集订阅并推送到 Gist"
        case .refresh: return "更新现有订阅"
        }
    }
}

struct WorkflowRun: Decodable, Identifiable {
    let id: Int64
    let name: String
    let status: String
    let conclusion: String?
    let createdAt: Date?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion
        case createdAt = "created_at"
        case htmlURL = "html_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        // GitHub may return null for a run whose workflow has been removed.
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名工作流"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        htmlURL = try container.decodeIfPresent(URL.self, forKey: .htmlURL)
    }
}

private struct RunsResponse: Decodable { let workflow_runs: [WorkflowRun] }
private struct GitHubErrorResponse: Decodable { let message: String? }

enum GitHubClientError: LocalizedError {
    case invalidSettings
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidSettings: return "请填写有效的 GitHub 用户名、仓库名、分支和令牌。"
        case .invalidResponse: return "GitHub 返回了无法识别的响应。"
        case let .http(code, message): return "GitHub 请求失败（\(code)）：\(message)"
        }
    }
}

struct GitHubClient {
    let owner: String
    let repository: String
    let branch: String
    let token: String

    private func request(path: [String], method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        // Repository path components must not introduce additional URL segments.
        let validName = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard !owner.isEmpty, !repository.isEmpty, !branch.isEmpty, !token.isEmpty,
              owner.unicodeScalars.allSatisfy({ validName.contains($0) }),
              repository.unicodeScalars.allSatisfy({ validName.contains($0) }),
              owner != ".", owner != "..", repository != ".", repository != ".." else {
            throw GitHubClientError.invalidSettings
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/" + (["repos", owner, repository] + path).joined(separator: "/")
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GitHubClientError.invalidSettings }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(GitHubErrorResponse.self, from: data).message) ?? "请检查仓库、权限和工作流配置。"
            throw GitHubClientError.http(http.statusCode, message)
        }
        return data
    }

    func runs() async throws -> [WorkflowRun] {
        let request = try request(path: ["actions", "runs"], query: [URLQueryItem(name: "per_page", value: "30")])
        let data = try await send(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RunsResponse.self, from: data).workflow_runs
    }

    func dispatch(_ workflow: Workflow) async throws {
        let body = try JSONEncoder().encode(["ref": branch])
        let request = try request(path: ["actions", "workflows", workflow.rawValue, "dispatches"], method: "POST", body: body)
        _ = try await send(request)
    }
}
