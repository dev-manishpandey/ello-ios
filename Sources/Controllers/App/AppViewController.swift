////
///  AppViewController.swift
//

import SwiftyUserDefaults
import PromiseKit
import AudioToolbox


struct HapticFeedbackNotifications {
    static let successfulUserEvent = TypedNotification<(Void)>(name: "co.ello.HapticFeedbackNotifications.successfulUserEvent")
}

struct StatusBarNotifications {
    static let statusBarVisibility = TypedNotification<(Bool)>(name: "co.ello.StatusBarNotifications.statusBarVisibility")
}

enum LoggedOutAction {
    case relationshipChange
    case postTool
    case artistInviteSubmit
}

struct LoggedOutNotifications {
    static let userActionAttempted = TypedNotification<LoggedOutAction>(name: "co.ello.LoggedOutNotifications.userActionAttempted")
}


@objc
protocol HasAppController {
    var appViewController: AppViewController? { get }
}


class AppViewController: BaseElloViewController {
    override func trackerName() -> String? { return nil }

    private var _mockScreen: AppScreenProtocol?
    var screen: AppScreenProtocol {
        set(screen) { _mockScreen = screen }
        get { return _mockScreen ?? (self.view as! AppScreen) }
    }

    var visibleViewController: UIViewController?

    private var userLoggedOutObserver: NotificationObserver?
    private var successfulUserEventObserver: NotificationObserver?
    private var receivedPushNotificationObserver: NotificationObserver?
    private var externalWebObserver: NotificationObserver?
    private var internalWebObserver: NotificationObserver?
    private var apiOutOfDateObserver: NotificationObserver?
    private var pushPayload: PushPayload?
    private var deepLinkPath: String?

    override func loadView() {
        self.view = AppScreen()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNotificationObservers()
    }

    deinit {
        removeNotificationObservers()
    }

    var isStartup = true
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if isStartup {
            isStartup = false
            checkIfLoggedIn()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        postNotification(Application.Notifications.ViewSizeWillChange, value: size)
    }

    override func didSetCurrentUser() {
        super.didSetCurrentUser()
        ElloWebBrowserViewController.currentUser = currentUser

        if let vc = visibleViewController as? ControllerThatMightHaveTheCurrentUser {
            vc.currentUser = currentUser
        }
    }

// MARK: - Private

    private func checkIfLoggedIn() {
        let authToken = AuthToken()

        if authToken.isPasswordBased {
            loadCurrentUser(animateLogo: true)
        }
        else {
            showStartupScreen()
        }
    }

    @discardableResult
    func loadCurrentUser(animateLogo: Bool = false) -> Promise<User> {
        if animateLogo {
            screen.animateLogo()
        }

        return ProfileService().loadCurrentUser()
            .then { user -> User in
                self.logInNewUser()
                JWT.refresh()

                self.screen.stopAnimatingLogo()
                self.currentUser = user

                let shouldShowOnboarding = Onboarding.shared.shouldShowOnboarding(user)
                let shouldShowCreatorType = Onboarding.shared.shouldShowCreatorType(user)
                if shouldShowOnboarding || shouldShowCreatorType {
                    self.showOnboardingScreen(user)
                }
                else {
                    self.showMainScreen(user)
                }

                return user
            }
            .catch { _ in
                if animateLogo {
                    self.showStartupScreen()
                    self.screen.stopAnimatingLogo()
                }
            }
    }

    private func setupNotificationObservers() {
        userLoggedOutObserver = NotificationObserver(notification: AuthenticationNotifications.userLoggedOut) { [weak self] in
            self?.userLoggedOut()
        }
        successfulUserEventObserver = NotificationObserver(notification: HapticFeedbackNotifications.successfulUserEvent) { _ in
            AudioServicesPlaySystemSound(1520)
        }
        receivedPushNotificationObserver = NotificationObserver(notification: PushNotificationNotifications.interactedWithPushNotification) { [weak self] payload in
            self?.receivedPushNotification(payload)
        }
        externalWebObserver = NotificationObserver(notification: ExternalWebNotification) { [weak self] url in
            self?.showExternalWebView(url)
        }
        internalWebObserver = NotificationObserver(notification: InternalWebNotification) { [weak self] url in
            self?.navigateToDeepLink(url)
        }
        apiOutOfDateObserver = NotificationObserver(notification: ErrorStatusCode.status410.notification) { [weak self] error in
            let message = InterfaceString.App.OldVersion
            let alertController = AlertViewController(message: message)

            let action = AlertAction(title: InterfaceString.OK, style: .dark, handler: nil)
            alertController.addAction(action)

            self?.present(alertController, animated: true, completion: nil)
            self?.apiOutOfDateObserver?.removeObserver()
            postNotification(AuthenticationNotifications.invalidToken, value: false)
        }
    }

    private func removeNotificationObservers() {
        userLoggedOutObserver?.removeObserver()
        successfulUserEventObserver?.removeObserver()
        receivedPushNotificationObserver?.removeObserver()
        externalWebObserver?.removeObserver()
        internalWebObserver?.removeObserver()
        apiOutOfDateObserver?.removeObserver()
    }
}


// MARK: Screens
extension AppViewController {

    private func showStartupScreen(_ completion: @escaping Block = {}) {
        let initialController = HomeViewController(usage: .loggedOut)
        let childNavController = ElloNavigationController(rootViewController: initialController)
        let loggedOutController = LoggedOutViewController()
        let parentNavController = ElloNavigationController(rootViewController: loggedOutController)

        loggedOutController.addChildViewController(childNavController)
        childNavController.didMove(toParentViewController: loggedOutController)

        swapViewController(parentNavController) {
            if let deepLinkPath = self.deepLinkPath {
                self.navigateToDeepLink(deepLinkPath)
                self.deepLinkPath = .none
            }
        }
    }

    func showJoinScreen(invitationCode: String? = nil) {
        guard
            let nav = visibleViewController as? UINavigationController,
            let loggedOutController = nav.childViewControllers.first as? LoggedOutViewController
        else { return }

        if !(nav.visibleViewController is LoggedOutViewController) {
            _ = nav.popToRootViewController(animated: false)
        }

        pushPayload = .none
        let joinController = JoinViewController()
        joinController.invitationCode = invitationCode
        nav.setViewControllers([loggedOutController, joinController], animated: true)
    }

    func showLoginScreen() {
        guard
            let nav = visibleViewController as? UINavigationController,
            let loggedOutController = nav.childViewControllers.first as? LoggedOutViewController
        else { return }

        if !(nav.visibleViewController is LoggedOutViewController) {
            _ = nav.popToRootViewController(animated: false)
        }

        pushPayload = .none
        let loginController = LoginViewController()
        nav.setViewControllers([loggedOutController, loginController], animated: true)
    }

    func showForgotPasswordResetScreen(authToken: String) {
        guard
            let nav = visibleViewController as? UINavigationController,
            let loggedOutController = nav.childViewControllers.first as? LoggedOutViewController
        else { return }

        if !(nav.visibleViewController is LoggedOutViewController) {
            _ = nav.popToRootViewController(animated: false)
        }

        pushPayload = .none
        let forgotPasswordResetController = ForgotPasswordResetViewController(authToken: authToken)
        nav.setViewControllers([loggedOutController, forgotPasswordResetController], animated: true)
    }

    func showForgotPasswordEmailScreen() {
        guard
            let nav = visibleViewController as? UINavigationController,
            let loggedOutController = nav.childViewControllers.first as? LoggedOutViewController
        else { return }

        if !(nav.visibleViewController is LoggedOutViewController) {
            _ = nav.popToRootViewController(animated: false)
        }

        pushPayload = .none
        let loginController = LoginViewController()
        let forgotPasswordEmailController = ForgotPasswordEmailViewController()
        nav.setViewControllers([loggedOutController, loginController, forgotPasswordEmailController], animated: true)
    }

    func showOnboardingScreen(_ user: User) {
        currentUser = user

        let vc = OnboardingViewController()
        vc.currentUser = user

        swapViewController(vc) {}
    }

    func doneOnboarding() {
        Onboarding.shared.updateVersionToLatest()
        self.showMainScreen(currentUser!)
    }

    func showMainScreen(_ user: User) {
        Tracker.shared.identify(user: user)

        let vc = ElloTabBarController()
        ElloWebBrowserViewController.elloTabBarController = vc
        vc.currentUser = user

        swapViewController(vc) {
            if let payload = self.pushPayload {
                self.navigateToDeepLink(payload.applicationTarget)
                self.pushPayload = .none
            }
            if let deepLinkPath = self.deepLinkPath {
                self.navigateToDeepLink(deepLinkPath)
                self.deepLinkPath = .none
            }

            vc.activateTabBar()
            PushNotificationController.shared.requestPushAccessIfNeeded(vc)
        }
    }
}

extension AppViewController {

    func showExternalWebView(_ url: String) {
        if let externalURL = URL(string: url), ElloWebViewHelper.bypassInAppBrowser(externalURL) {
            UIApplication.shared.openURL(externalURL)
        }
        else {
            let externalWebController = ElloWebBrowserViewController.navigationControllerWithWebBrowser()
            present(externalWebController, animated: true, completion: nil)

            if let externalWebView = externalWebController.rootWebBrowser() {
                externalWebView.tintColor = UIColor.greyA
                externalWebView.loadURLString(url)
            }
        }
        Tracker.shared.webViewAppeared(url)
    }

    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
        // Unsure why WKWebView calls this controller - instead of it's own parent controller
        if let vc = presentedViewController {
            vc.present(viewControllerToPresent, animated: flag, completion: completion)
        } else {
            super.present(viewControllerToPresent, animated: flag, completion: completion)
        }
    }

}

// MARK: Screen transitions
extension AppViewController {

    func swapViewController(_ newViewController: UIViewController, completion: @escaping Block) {
        newViewController.view.alpha = 0

        visibleViewController?.willMove(toParentViewController: nil)
        newViewController.willMove(toParentViewController: self)

        prepareToShowViewController(newViewController)

        if let tabBarController = visibleViewController as? ElloTabBarController {
            tabBarController.deactivateTabBar()
        }

        UIView.animate(withDuration: 0.2, animations: {
            self.visibleViewController?.view.alpha = 0
            newViewController.view.alpha = 1
            self.screen.hide()
        }, completion: { _ in
            self.visibleViewController?.view.removeFromSuperview()
            self.visibleViewController?.removeFromParentViewController()

            self.addChildViewController(newViewController)

            self.visibleViewController?.didMove(toParentViewController: nil)
            newViewController.didMove(toParentViewController: self)

            self.visibleViewController = newViewController
            completion()
        })
    }

    func removeViewController(_ completion: @escaping Block = {}) {
        if presentingViewController != nil {
            dismiss(animated: false, completion: .none)
        }
        self.showStatusBar(true)

        if let visibleViewController = visibleViewController {
            visibleViewController.willMove(toParentViewController: nil)

            if let tabBarController = visibleViewController as? ElloTabBarController {
                tabBarController.deactivateTabBar()
            }

            UIView.animate(withDuration: 0.2, animations: {
                visibleViewController.view.alpha = 0
            }, completion: { _ in
                self.showStartupScreen()
                visibleViewController.view.removeFromSuperview()
                visibleViewController.removeFromParentViewController()
                self.visibleViewController = nil
                completion()
            })
        }
        else {
            showStartupScreen()
            completion()
        }
    }

    private func prepareToShowViewController(_ newViewController: UIViewController) {
        view.addSubview(newViewController.view)
        newViewController.view.frame = self.view.bounds
        newViewController.view.autoresizingMask = [.flexibleHeight, .flexibleWidth]
    }

}


// MARK: Logout events
extension AppViewController {
    func userLoggedOut() {
        logOutCurrentUser()

        if isLoggedIn() {
            removeViewController()
        }
    }

    func forceLogOut(_ shouldAlert: Bool) {
        logOutCurrentUser()

        if isLoggedIn() {
            removeViewController {
                if shouldAlert {
                    let message = InterfaceString.App.LoggedOut
                    let alertController = AlertViewController(message: message)

                    let action = AlertAction(title: InterfaceString.OK, style: .dark, handler: nil)
                    alertController.addAction(action)

                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }

    func isLoggedIn() -> Bool {
        if let visibleViewController = visibleViewController, visibleViewController is ElloTabBarController
        {
            return true
        }
        return false
    }

    private func logInNewUser() {
        URLCache.shared.removeAllCachedResponses()
        TemporaryCache.clear()
    }

    private func logOutCurrentUser() {
        PushNotificationController.shared.deregisterStoredToken()
        ElloProvider.shared.logout()
        GroupDefaults.resetOnLogout()
        UIApplication.shared.applicationIconBadgeNumber = 0
        URLCache.shared.removeAllCachedResponses()
        TemporaryCache.clear()
        ElloLinkedStore.clearDB()
        var cache = InviteCache()
        cache.clear()
        Tracker.shared.identify(user: nil)
        currentUser = nil
    }
}

// MARK: Invitations screen

// MARK: InviteResponder
extension AppViewController: InviteResponder {

    func onInviteFriends() {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }

        Tracker.shared.inviteFriendsTapped()
        AddressBookController.promptForAddressBookAccess(fromController: self, completion: { result in
            nextTick {
                switch result {
                case let .success(addressBook):
                    Tracker.shared.contactAccessPreferenceChanged(true)
                    let vc = OnboardingInviteViewController(addressBook: addressBook)
                    vc.currentUser = self.currentUser
                    if let navigationController = self.navigationController {
                        navigationController.pushViewController(vc, animated: true)
                    }
                    else {
                        self.present(vc, animated: true, completion: nil)
                    }
                case let .failure(addressBookError):
                    guard addressBookError != .cancelled else { return }

                    Tracker.shared.contactAccessPreferenceChanged(false)
                    let message = addressBookError.rawValue
                    let alertController = AlertViewController(
                        message: InterfaceString.Friends.ImportError(message)
                    )

                    let action = AlertAction(title: InterfaceString.OK, style: .dark, handler: .none)
                    alertController.addAction(action)

                    self.present(alertController, animated: true, completion: .none)
                }
            }
        })
    }

    func sendInvite(person: LocalPerson, isOnboarding: Bool, completion: @escaping Block) {
        guard let email = person.emails.first else { return }

        if isOnboarding {
            Tracker.shared.onboardingFriendInvited()
        }
        else {
            Tracker.shared.friendInvited()
        }
        ElloHUD.showLoadingHudInView(view)
        InviteService().invite(email)
            .always { [weak self] in
                guard let `self` = self else { return }
                ElloHUD.hideLoadingHudInView(self.view)
                completion()
            }
    }
}

// MARK: Push Notification Handling
extension AppViewController {
    func receivedPushNotification(_ payload: PushPayload) {
        if self.visibleViewController is ElloTabBarController {
            navigateToDeepLink(payload.applicationTarget)
        } else {
            self.pushPayload = payload
        }
    }
}

// MARK: URL Handling
extension AppViewController {
    func navigateToDeepLink(_ path: String) {
        Tracker.shared.deepLinkVisited(path)

        let (type, data) = ElloURI.match(path)
        navigateToURI(path: path, type: type, data: data)
    }

    func navigateToURI(path: String, type: ElloURI, data: String?) {
        guard type.shouldLoadInApp else {
            showExternalWebView(path)
            return
        }

        guard !stillLoggingIn() && !stillSettingUpLoggedOut() else {
            self.deepLinkPath = path
            return
        }

        guard isLoggedIn() || !type.requiresLogin else {
            presentLoginOrSafariAlert(path)
            return
        }

        switch type {
        case .invite, .join, .signup, .login:
            guard !isLoggedIn() else { return }
            switch type {
            case .invite:
                showJoinScreen(invitationCode: data)
            case .join, .signup:
                showJoinScreen()
            case .login:
                showLoginScreen()
            default:
                break
            }
        case .artistInvitesBrowse:
            showArtistInvitesScreen()
        case .artistInvitesDetail, .pushNotificationArtistInvite:
            showArtistInvitesScreen(slug: data)
        case .exploreRecommended,
             .exploreRecent,
             .exploreTrending,
             .discover:
            showCategoryScreen(slug: Category.featured.slug)
        case .discoverRandom,
             .discoverRecent,
             .discoverRelated,
             .discoverTrending,
             .category:
            guard let slug = data else { return }
            showCategoryScreen(slug: slug)
        case .invitations:
            showInvitationScreen()
        case .forgotMyPassword:
            showForgotPasswordEmailScreen()
        case .resetMyPassword:
            guard let token = data else { return }
            showForgotPasswordResetScreen(authToken: token)
        case .enter:
            showLoginScreen()
        case .exit, .root, .explore:
            break
        case .friends,
             .following,
             .noise,
             .starred:
            showFollowingScreen()
        case .notifications:
            guard let category = data else { return }
            showNotificationsScreen(category: category)
        case .onboarding:
            guard let user = currentUser else { return }
            showOnboardingScreen(user)
        case .post:
            guard let postId = data else { return }
            showPostDetailScreen(postParam: postId, path: path)
        case .pushNotificationComment,
             .pushNotificationPost:
            guard let postId = data else { return }
            showPostDetailScreen(postParam: postId, path: path, isSlug: false)
        case .profile:
            guard let userId = data else { return }
            showProfileScreen(userParam: userId, path: path)
        case .pushNotificationUser:
            guard let userId = data else { return }
            showProfileScreen(userParam: userId, path: path, isSlug: false)
        case .profileFollowers,
             .profileFollowing:
            guard let username = data else { return }
            showProfileFollowersScreen(username: username)
        case .profileLoves:
            guard let username = data else { return }
            showProfileLovesScreen(username: username)
        case .search,
             .searchPeople,
             .searchPosts:
            showSearchScreen(terms: data)
        case .settings:
            showSettingsScreen()
        case .wtf:
            showExternalWebView(path)
        default:
            guard let pathURL = URL(string: path) else { return }
            UIApplication.shared.openURL(pathURL)
        }
    }

    private func stillLoggingIn() -> Bool {
        let authToken = AuthToken()
        return !isLoggedIn() && authToken.isPasswordBased
    }

    private func stillSettingUpLoggedOut() -> Bool {
        let authToken = AuthToken()
        let isLoggedOut = !isLoggedIn() && authToken.isAnonymous
        let nav = self.visibleViewController as? UINavigationController
        let loggedOutVC = nav?.viewControllers.first as? LoggedOutViewController
        let childNav = loggedOutVC?.childViewControllers.first as? UINavigationController
        return childNav == nil && isLoggedOut
    }

    private func presentLoginOrSafariAlert(_ path: String) {
        guard !isLoggedIn() else {
            return
        }

        let alertController = AlertViewController(message: path)

        let yes = AlertAction(title: InterfaceString.App.LoginAndView, style: .dark) { _ in
            self.deepLinkPath = path
            self.showLoginScreen()
        }
        alertController.addAction(yes)

        let viewBrowser = AlertAction(title: InterfaceString.App.OpenInSafari, style: .light) { _ in
            guard let pathURL = URL(string: path) else { return }
            UIApplication.shared.openURL(pathURL)
        }
        alertController.addAction(viewBrowser)

        self.present(alertController, animated: true, completion: nil)
    }

    private func showInvitationScreen() {
        guard
            let vc = self.visibleViewController as? ElloTabBarController
        else { return }

        vc.selectedTab = .discover

        onInviteFriends()
    }

    private func showArtistInvitesScreen(slug: String? = nil) {
        if let slug = slug {
            guard !DeepLinking.alreadyOnArtistInvites(navVC: pushDeepNavigationController(), slug: slug) else { return }

            Tracker.shared.artistInviteOpened(slug: slug)
            let vc = ArtistInviteDetailController(slug: slug)
            vc.currentUser = currentUser

            pushDeepLinkViewController(vc)
        }
        else if let vc = self.visibleViewController as? ElloTabBarController {
            vc.selectedTab = .home
            let navVC = vc.selectedViewController as? ElloNavigationController
            let homeVC = navVC?.viewControllers.first as? HomeViewController
            homeVC?.showArtistInvitesViewController()
            navVC?.popToRootViewController(animated: true)
        }
    }

    private func showCategoryScreen(slug: String) {
        if let vc = self.visibleViewController as? ElloTabBarController {
            Tracker.shared.categoryOpened(slug)
            vc.selectedTab = .discover
            let navVC = vc.selectedViewController as? ElloNavigationController
            let catVC = navVC?.viewControllers.first as? CategoryViewController
            catVC?.selectCategoryFor(slug: slug)
            navVC?.popToRootViewController(animated: true)
        }
        else if
            let topNav = self.visibleViewController as? UINavigationController,
            let loggedOutController = topNav.viewControllers.first as? LoggedOutViewController,
            let childNav = loggedOutController.childViewControllers.first as? UINavigationController,
            let categoryViewController = childNav.viewControllers.first as? CategoryViewController
        {
            childNav.popToRootViewController(animated: true)
            categoryViewController.selectCategoryFor(slug: slug)
        }
    }

    private func showFollowingScreen() {
        guard
            let vc = self.visibleViewController as? ElloTabBarController
        else { return }

        vc.selectedTab = .home

        guard
            let navVC = vc.selectedViewController as? ElloNavigationController,
            let homeVC = navVC.visibleViewController as? HomeViewController
        else { return }

        homeVC.showFollowingViewController()
    }

    private func showNotificationsScreen(category: String) {
        guard
            let vc = self.visibleViewController as? ElloTabBarController
        else { return }

        vc.selectedTab = .notifications

        guard
            let navVC = vc.selectedViewController as? ElloNavigationController,
            let notificationsVC = navVC.visibleViewController as? NotificationsViewController
        else { return }

        let notificationFilterType = NotificationFilterType.fromCategory(category)
        notificationsVC.categoryFilterType = notificationFilterType
        notificationsVC.activatedCategory(notificationFilterType)
    }

    private func showProfileScreen(userParam: String, path: String, isSlug: Bool = true) {
        let param = isSlug ? "~\(userParam)" : userParam
        let profileVC = ProfileViewController(userParam: param)
        profileVC.deeplinkPath = path
        profileVC.currentUser = currentUser
        pushDeepLinkViewController(profileVC)
    }

    private func showPostDetailScreen(postParam: String, path: String, isSlug: Bool = true) {
        let param = isSlug ? "~\(postParam)" : postParam
        let postDetailVC = PostDetailViewController(postParam: param)
        postDetailVC.deeplinkPath = path
        postDetailVC.currentUser = currentUser
        pushDeepLinkViewController(postDetailVC)
    }

    private func showProfileFollowersScreen(username: String) {
        let endpoint = ElloAPI.userStreamFollowers(userId: "~\(username)")
        let noResultsTitle: String
        let noResultsBody: String
        if username == currentUser?.username {
            noResultsTitle = InterfaceString.Followers.CurrentUserNoResultsTitle
            noResultsBody = InterfaceString.Followers.CurrentUserNoResultsBody
        }
        else {
            noResultsTitle = InterfaceString.Followers.NoResultsTitle
            noResultsBody = InterfaceString.Followers.NoResultsBody
        }
        let followersVC = SimpleStreamViewController(endpoint: endpoint, title: "@" + username + "'s " + InterfaceString.Followers.Title)
        followersVC.streamViewController.noResultsMessages = NoResultsMessages(title: noResultsTitle, body: noResultsBody)
        followersVC.currentUser = currentUser
        pushDeepLinkViewController(followersVC)
    }

    private func showProfileFollowingScreen(_ username: String) {
        let endpoint = ElloAPI.userStreamFollowing(userId: "~\(username)")
        let noResultsTitle: String
        let noResultsBody: String
        if username == currentUser?.username {
            noResultsTitle = InterfaceString.Following.CurrentUserNoResultsTitle
            noResultsBody = InterfaceString.Following.CurrentUserNoResultsBody
        }
        else {
            noResultsTitle = InterfaceString.Following.NoResultsTitle
            noResultsBody = InterfaceString.Following.NoResultsBody
        }
        let vc = SimpleStreamViewController(endpoint: endpoint, title: "@" + username + "'s " + InterfaceString.Following.Title)
        vc.streamViewController.noResultsMessages = NoResultsMessages(title: noResultsTitle, body: noResultsBody)
        vc.currentUser = currentUser
        pushDeepLinkViewController(vc)
    }

    private func showProfileLovesScreen(username: String) {
        let endpoint = ElloAPI.loves(userId: "~\(username)")
        let noResultsTitle: String
        let noResultsBody: String
        if username == currentUser?.username {
            noResultsTitle = InterfaceString.Loves.CurrentUserNoResultsTitle
            noResultsBody = InterfaceString.Loves.CurrentUserNoResultsBody
        }
        else {
            noResultsTitle = InterfaceString.Loves.NoResultsTitle
            noResultsBody = InterfaceString.Loves.NoResultsBody
        }
        let vc = SimpleStreamViewController(endpoint: endpoint, title: "@" + username + "'s " + InterfaceString.Loves.Title)
        vc.streamViewController.noResultsMessages = NoResultsMessages(title: noResultsTitle, body: noResultsBody)
        vc.currentUser = currentUser
        pushDeepLinkViewController(vc)
    }

    private func showSearchScreen(terms: String?) {
        let search = SearchViewController()
        search.currentUser = currentUser
        if let terms = terms, !terms.isEmpty {
            search.searchForPosts(terms.urlDecoded().replacingOccurrences(of: "+", with: " ", options: NSString.CompareOptions.literal, range: nil))
        }
        pushDeepLinkViewController(search)
    }

    private func showSettingsScreen() {
        guard
            let settings = UIStoryboard(name: "Settings", bundle: .none).instantiateInitialViewController() as? SettingsContainerViewController,
            let currentUser = currentUser
        else { return }

        settings.currentUser = currentUser
        pushDeepLinkViewController(settings)
    }

    private func pushDeepNavigationController() -> UINavigationController? {
        var navController: UINavigationController?

        if
            let tabController = self.visibleViewController as? ElloTabBarController,
            let tabNavController = tabController.selectedViewController as? UINavigationController
        {
            let topNavVC = topViewController(self)?.navigationController
            navController = topNavVC ?? tabNavController
        }
        else if
            let nav = self.visibleViewController as? UINavigationController,
            let loggedOutVC = nav.viewControllers.first as? LoggedOutViewController,
            let childNav = loggedOutVC.childViewControllers.first as? UINavigationController
        {
            navController = childNav
        }

        return navController
    }

    private func pushDeepLinkViewController(_ vc: UIViewController) {
        pushDeepNavigationController()?.pushViewController(vc, animated: true)
    }

    private func selectTab(_ tab: ElloTab) {
        ElloWebBrowserViewController.elloTabBarController?.selectedTab = tab
    }


}

extension AppViewController {

    func topViewController(_ base: UIViewController?) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            if let selected = tab.selectedViewController {
                return topViewController(selected)
            }
        }
        if let presented = base?.presentedViewController {
            return topViewController(presented)
        }
        return base
    }
}

var isShowingDebug = false

extension AppViewController {

    override var canBecomeFirstResponder: Bool {
        return debugAllowed
    }

    var debugAllowed: Bool {
        #if DEBUG
            return true
        #else
            return AuthToken().isStaff || DebugServer.fromDefaults != nil
        #endif
    }

    override func motionEnded(_ motion: UIEventSubtype, with event: UIEvent?) {
        guard debugAllowed, motion == .motionShake else { return }

        if isShowingDebug {
            closeDebugController()
        }
        else {
            showDebugController()
        }
    }

    func showDebugController() {
        isShowingDebug = true
        let ctlr = DebugController()

        ctlr.title = "Debugging"

        let nav = UINavigationController(rootViewController: ctlr)
        let bar = UIView(frame: CGRect(x: 0, y: -20, width: view.frame.width, height: 20))
        bar.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        bar.backgroundColor = .black
        nav.navigationBar.addSubview(bar)

        let closeItem = UIBarButtonItem.closeButton(target: self, action: #selector(AppViewController.closeDebugControllerTapped))
        ctlr.navigationItem.leftBarButtonItem = closeItem

        present(nav, animated: true, completion: nil)
    }

    @objc
    func closeDebugControllerTapped() {
        closeDebugController()
    }

    func closeDebugController(completion: (() -> Void)? = nil) {
        isShowingDebug = false
        dismiss(animated: true, completion: completion)
    }

}
