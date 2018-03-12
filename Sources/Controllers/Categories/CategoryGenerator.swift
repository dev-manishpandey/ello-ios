////
///  CategoryGenerator.swift
//

import PromiseKit


protocol CategoryStreamDestination: StreamDestination {
    func set(subscribedCategories: [Category])
}

final class CategoryGenerator: StreamGenerator {
    var streamKind: StreamKind
    var currentUser: User?
    weak private var categoryStreamDestination: CategoryStreamDestination?
    weak var destination: StreamDestination? {
        get { return categoryStreamDestination }
        set {
            if !(newValue is CategoryStreamDestination) { fatalError("CategoryGenerator.destination must conform to CategoryStreamDestination") }
            categoryStreamDestination = newValue as? CategoryStreamDestination
        }
    }

    private var subscribedCategories: [Category]?
    private var streamSelection: (Category.Selection, DiscoverType)
    private var categorySelection: Category.Selection { return streamSelection.0 }
    private var stream: DiscoverType { return streamSelection.1 }
    private var pageHeader: PageHeader?
    private var posts: [Post]?
    private var localToken: String = ""
    private var loadingToken = LoadingToken()
    private let queue = OperationQueue()

    private var nextPageRequest: GraphQLRequest<(PageConfig, [Post])>?
    private var nextRequestGenerator: ((String) -> GraphQLRequest<(PageConfig, [Post])>)?

    init(selection: Category.Selection, stream: DiscoverType, currentUser: User?, destination: StreamDestination) {
        self.streamKind = .category(selection, stream)
        self.streamSelection = (selection, stream)
        self.currentUser = currentUser
        self.destination = destination
    }

    func headerItems() -> [StreamCellItem] {
        guard let pageHeader = pageHeader else { return [] }

        var items = [StreamCellItem(jsonable: pageHeader, type: .promotionalHeader)]
        if pageHeader.categoryId != nil {
            items.append(StreamCellItem(jsonable: pageHeader, type: .promotionalHeaderSubscription))
        }
        return items
    }

    func reset(selection _selection: Category.Selection? = nil, stream _stream: DiscoverType? = nil) {
        let selection = _selection ?? self.categorySelection
        let stream = _stream ?? self.stream
        self.streamSelection = (selection, stream)
        self.pageHeader = nil
        self.streamKind = .category(selection, stream)
    }

    func load(reloadPosts: Bool, reloadHeader: Bool, reloadCategories: Bool) {
        let doneOperation = AsyncOperation()
        queue.addOperation(doneOperation)

        localToken = loadingToken.resetInitialPageLoadingToken()

        let isInitialLoad = !reloadPosts && !reloadHeader && !reloadCategories
        if isInitialLoad {
            setPlaceHolders()
        }

        if reloadPosts {
            posts = nil
            self.destination?.replacePlaceholder(type: .streamItems, items: [StreamCellItem(type: .streamLoading)])
        }

        if reloadHeader {
            self.destination?.replacePlaceholder(type: .promotionalHeader, items: [])
        }

        if isInitialLoad || reloadHeader {
            pageHeader = nil
            loadPageHeader(doneOperation)
        }
        else {
            doneOperation.run()
        }

        if isInitialLoad || reloadCategories {
            subscribedCategories = nil
            loadSubscribedCategories()
        }

        if isInitialLoad || reloadPosts {
            loadCategoryPosts(doneOperation, reload: reloadPosts)
        }
    }

    func toggleGrid() {
        guard let posts = posts else { return }
        destination?.replacePlaceholder(type: .streamItems, items: parse(jsonables: posts))
    }

    func loadNextPage() -> Promise<[JSONAble]>? {
        guard
            let nextPageRequest = nextPageRequest
        else { return nil }

        return nextPageRequest
            .execute()
            .then { pageConfig, posts -> [JSONAble] in
                self.setNextPageConfig(pageConfig)
                if posts.count == 0 {
                    self.destination?.isPagingEnabled = false
                }
                return posts
            }
            .catch { error in
                let errorConfig = PageConfig(next: nil, isLastPage: true)
                self.destination?.setPagingConfig(responseConfig: ResponseConfig(pageConfig: errorConfig))
                self.destination?.isPagingEnabled = false
            }
    }
}

extension CategoryGenerator {

    private func setPlaceHolders() {
        destination?.setPlaceholders(items: [
            StreamCellItem(type: .placeholder, placeholderType: .promotionalHeader),
            StreamCellItem(type: .placeholder, placeholderType: .streamSelection),
            StreamCellItem(type: .placeholder, placeholderType: .streamItems)
        ])
    }

    private func loadPageHeader(_ doneOperation: AsyncOperation) {
        let kind: API.PageHeaderKind
        if case let .category(slug) = categorySelection {
            kind = .category(slug)
        }
        else {
            kind = .generic
        }

        API().pageHeaders(kind: kind)
            .execute()
            .then { pageHeaders -> Void in
                guard self.loadingToken.isValidInitialPageLoadingToken(self.localToken) else { return }

                if let pageHeader = pageHeaders.randomItem() {
                    self.pageHeader = pageHeader
                    self.destination?.setPrimary(jsonable: pageHeader)
                }
                else {
                    self.destination?.primaryJSONAbleNotFound()
                }

                self.destination?.replacePlaceholder(type: .promotionalHeader, items: self.headerItems())
            }
            .catch { _ in
                self.destination?.primaryJSONAbleNotFound()
            }
            .always {
                doneOperation.run()
            }
    }

    private func loadSubscribedCategories() {
        API().subscribedCategories()
            .execute()
            .then { subscribedCategories -> Void in
                self.subscribedCategories = subscribedCategories
                self.categoryStreamDestination?.set(subscribedCategories: subscribedCategories)
            }
            .ignoreErrors()
    }

    private func loadCategoryPosts(_ doneOperation: AsyncOperation, reload: Bool) {
        let request: GraphQLRequest<(PageConfig, [Post])>
        let stream = self.stream

        switch categorySelection {
        case .all:
            request = API().globalPostStream(stream: stream)
            nextRequestGenerator = { next in return API().globalPostStream(stream: stream, before: next) }
        case .subscribed:
            request = API().subscribedPostStream(stream: stream)
            nextRequestGenerator = { next in return API().subscribedPostStream(stream: stream, before: next) }
        case let .category(slug):
            request = API().categoryPostStream(categorySlug: slug, stream: stream)
            nextRequestGenerator = { next in return API().categoryPostStream(categorySlug: slug, stream: stream, before: next) }
        }

        let displayPostsOperation = AsyncOperation()
        displayPostsOperation.addDependency(doneOperation)
        queue.addOperation(displayPostsOperation)

        request.execute()
            .then { pageConfig, posts -> Void in
                guard self.loadingToken.isValidInitialPageLoadingToken(self.localToken) else { return }

                self.setNextPageConfig(pageConfig)

                self.posts = posts
                var items = self.parse(jsonables: posts)
                let isPagingEnabled = items.count > 0
                if items.count == 0 {
                    items = [StreamCellItem(type: .emptyStream(height: 182))]
                }

                displayPostsOperation.run { inForeground {
                    if isPagingEnabled && !reload {
                        let metaItem = StreamCellItem(type: .streamSelection)
                        self.destination?.replacePlaceholder(type: .streamSelection, items: [metaItem])
                    }
                    else if !isPagingEnabled {
                        self.destination?.replacePlaceholder(type: .streamSelection, items: [])
                    }

                    self.destination?.replacePlaceholder(type: .streamItems, items: items) {
                        self.destination?.isPagingEnabled = isPagingEnabled
                    }
                } }
            }
            .catch { _ in
                self.destination?.primaryJSONAbleNotFound()
            }
    }

    private func setNextPageConfig(_ pageConfig: PageConfig) {
        self.destination?.setPagingConfig(responseConfig: ResponseConfig(pageConfig: pageConfig))

        if let next = pageConfig.next, let nextRequestGenerator = nextRequestGenerator {
            self.nextPageRequest = nextRequestGenerator(next)
        }
        else {
            self.nextPageRequest = nil
            self.nextRequestGenerator = nil
        }
    }
}
