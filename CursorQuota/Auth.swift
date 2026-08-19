import Foundation
import SQLite3

enum TokenError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

enum Auth {
    static func jwtClaims(_ token: String) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw TokenError.message("Could not parse Cursor access token (not a JWT?)")
        }
        var payload = String(parts[1])
        let pad = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: payload.base64URLToBase64()),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokenError.message("Could not parse Cursor access token (not a JWT?)")
        }
        return json
    }

    static func cookieFromJWT(_ token: String) throws -> String {
        let claims = try jwtClaims(token)
        guard let sub = claims["sub"] as? String else {
            throw TokenError.message("Could not parse Cursor access token (not a JWT?)")
        }
        let userID = sub.split(separator: "|").last.map(String.init) ?? sub
        return "\(userID)%3A%3A\(token)"
    }

    static func sessionCookie() throws -> String {
        if let contents = try? String(contentsOf: AppConstants.tokenFile, encoding: .utf8) {
            let manual = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !manual.isEmpty {
                return manual.contains("%3A%3A") ? manual : try cookieFromJWT(manual)
            }
        }

        guard FileManager.default.fileExists(atPath: AppConstants.stateDB.path) else {
            throw TokenError.message("Cursor state DB not found — is Cursor installed?")
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let uri = URL(fileURLWithPath: AppConstants.stateDB.path).absoluteString + "?mode=ro"
        let openResult = sqlite3_open_v2(uri, &db, flags, nil)
        guard openResult == SQLITE_OK, let db else {
            let message = openResult == SQLITE_CANTOPEN
                ? "Cursor state DB not found — is Cursor installed?"
                : "Could not read Cursor state DB (code \(openResult))"
            throw TokenError.message(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5000)

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw TokenError.message("Could not read Cursor state DB")
        }
        defer { sqlite3_finalize(stmt) }

        let step = sqlite3_step(stmt)
        if step == SQLITE_BUSY || step == SQLITE_LOCKED {
            throw TokenError.message("Cursor state DB is locked — try again in a moment")
        }
        guard step == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) else {
            throw TokenError.message("No Cursor access token — log in to the Cursor app")
        }

        var token = String(cString: cString)
        if let data = token.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            token = decoded
        }

        if let exp = try jwtClaims(token)["exp"] as? TimeInterval,
           exp < Date().timeIntervalSince1970 {
            throw TokenError.message("Cursor token expired — open Cursor to refresh it")
        }

        return try cookieFromJWT(token)
    }
}

private extension String {
    func base64URLToBase64() -> String {
        var s = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s += String(repeating: "=", count: pad)
        return s
    }
}
