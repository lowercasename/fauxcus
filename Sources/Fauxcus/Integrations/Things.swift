import AppKit

enum Things {
    enum ThingsError: Error {
        case notInstalled
        case badURL
    }

    static var isInstalled: Bool {
        guard let probe = URL(string: "things:///") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    static func addTask(name: String, notes: String) throws {
        guard isInstalled else { throw ThingsError.notInstalled }
        var components = URLComponents()
        components.scheme = "things"
        components.host = ""
        components.path = "/add"
        components.queryItems = [
            URLQueryItem(name: "title", value: name),
            URLQueryItem(name: "notes", value: notes),
        ]
        guard let url = components.url else { throw ThingsError.badURL }
        NSWorkspace.shared.open(url)
    }
}
