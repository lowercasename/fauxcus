import Foundation

enum Todoist {
    enum TodoistError: Error {
        case unauthorized
        case rateLimited
        case network
        case badResponse(Int)
    }

    static func createTask(name: String, notes: String, token: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.todoist.com/api/v1/tasks")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "content": name,
            "description": notes,
        ])
        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TodoistError.network
        }
        guard let http = response as? HTTPURLResponse else { throw TodoistError.badResponse(0) }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw TodoistError.unauthorized
        case 429: throw TodoistError.rateLimited
        default: throw TodoistError.badResponse(http.statusCode)
        }
    }
}
