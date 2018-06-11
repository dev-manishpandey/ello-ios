////
///  Token.swift
//

enum Token {
    case id(String)
    case slug(String)

    static func fromParam(_ param: String) -> Token {
        if param.hasPrefix("~") {
            return .slug(String(param.dropFirst()))
        }
        else {
            return .id(param)
        }
    }

    func matches(id matchId: String, slug matchSlug: String) -> Bool {
        switch self {
        case let .id(id): return id == matchId
        case let .slug(slug): return slug == matchSlug
        }
    }

    var variable: GQLVariable {
        switch self {
        case let .id(id): return .optionalID("id", id)
        case let .slug(slug): return .optionalString("token", slug)
        }
    }

    var asId: String {
        switch self {
        case let .id(id): return id
        case let .slug(slug): return "~\(slug)"
        }
    }
}
