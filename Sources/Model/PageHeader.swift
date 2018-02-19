////
///  PageHeader.swift
//

import SwiftyJSON


@objc(PageHeader)
final class PageHeader: JSONAble {
    // version 1: initial
    static let Version = 1

    enum Kind: String {
        case artistInvite = "ARTIST_INVITE"
        case category = "CATEGORY"
        case editorial = "EDITORIAL"
        case generic = "GENERIC"
    }

    let id: String
    let postToken: String?
    let header: String
    let subheader: String
    let ctaCaption: String
    let ctaURL: URL?
    let image: Asset?
    var tileURL: URL? { return image?.oneColumnAttachment?.url }
    var kind: Kind

    var user: User? {
        return getLinkObject("user") as? User
    }

    init(
        id: String,
        postToken: String?,
        header: String,
        subheader: String,
        ctaCaption: String,
        ctaURL: URL?,
        image: Asset?,
        kind: Kind
    ) {
        self.id = id
        self.postToken = postToken
        self.header = header
        self.subheader = subheader
        self.ctaCaption = ctaCaption
        self.ctaURL = ctaURL
        self.image = image
        self.kind = kind
        super.init(version: PageHeader.Version)
    }

    required init(coder: NSCoder) {
        let decoder = Coder(coder)
        id = decoder.decodeKey("id")
        postToken = decoder.decodeOptionalKey("postToken")
        header = decoder.decodeKey("header")
        subheader = decoder.decodeKey("subheader")
        ctaCaption = decoder.decodeKey("ctaCaption")
        ctaURL = decoder.decodeOptionalKey("ctaURL")
        image = decoder.decodeOptionalKey("image")
        let kindString: String = decoder.decodeKey("kind")
        kind = Kind(rawValue: kindString) ?? .generic
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        let encoder = Coder(coder)
        encoder.encodeObject(id, forKey: "id")
        encoder.encodeObject(postToken, forKey: "postToken")
        encoder.encodeObject(header, forKey: "header")
        encoder.encodeObject(subheader, forKey: "subheader")
        encoder.encodeObject(ctaCaption, forKey: "ctaCaption")
        encoder.encodeObject(ctaURL, forKey: "ctaURL")
        encoder.encodeObject(image, forKey: "image")
        encoder.encodeObject(kind.rawValue, forKey: "kind")
        super.encode(with: coder)
    }
}

extension PageHeader: JSONSaveable {
    var uniqueId: String? { return "PageHeader-\(id)" }
    var tableId: String? { return id }

}
