//
//  CoverImageSelectionViewController.swift
//  Ello
//
//  Created by Colin Gray on 5/15/2015.
//  Copyright (c) 2015 Ello. All rights reserved.
//

public class CoverImageSelectionViewController: OnboardingUploadImageViewController {
    var onboardingHeader: UIView?

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Onboarding Cover Image Selection"

        setupOnboardingHeader()
        setupChooseCoverImage()
        setupChooseImageButton()
    }

    public func onboardingWillProceed(proceed: (OnboardingData?) -> Void) {
        if let image = selectedImage {
            self.userUploadImage(image, proceed: proceed)
        }
    }

}

// MARK: View setup
private extension CoverImageSelectionViewController {

    func setupOnboardingHeader() {
        let onboardingHeader = OnboardingHeaderView(frame: CGRect(
            x: 0,
            y: 0,
            width: view.frame.width,
            height: 0
            ))
        onboardingHeader.autoresizingMask = .FlexibleWidth
        let header = NSLocalizedString("Customize your profile.", comment: "Header Image Selection text")
        let message = NSLocalizedString("This is what other people will see when viewing your profile, make it look good!", comment: "Header Image Selection text")
        onboardingHeader.header = header
        onboardingHeader.message = message
        onboardingHeader.autoresizingMask = .FlexibleWidth | .FlexibleBottomMargin
        onboardingHeader.sizeToFit()
        view.addSubview(onboardingHeader)
        self.onboardingHeader = onboardingHeader
    }

    func setupChooseCoverImage() {
        let chooseCoverImage = chooseCoverImageDefault()
        let aspect = view.frame.width / chooseCoverImage.size.width
        let chooseCoverImageView = UIImageView(frame: CGRect(
            x: 0,
            y: onboardingHeader!.frame.maxY + 23,
            width: view.frame.width,
            height: chooseCoverImage.size.height * aspect
            ))
        chooseCoverImageView.contentMode = .ScaleAspectFill
        chooseCoverImageView.clipsToBounds = true
        chooseCoverImageView.autoresizingMask = .FlexibleLeftMargin | .FlexibleRightMargin | .FlexibleBottomMargin
        chooseCoverImageView.image = chooseCoverImage
        view.addSubview(chooseCoverImageView)
        self.chooseCoverImageView = chooseCoverImageView
    }

    func setupChooseImageButton() {
        let chooseImageButton = ElloButton(frame: CGRect(
            x: 0,
            y: chooseCoverImageView!.frame.maxY + 8,
            width: view.frame.width,
            height: 90
            ).inset(all: 15))
        chooseImageButton.autoresizingMask = .FlexibleLeftMargin | .FlexibleRightMargin | .FlexibleBottomMargin
        chooseImageButton.setTitle(NSLocalizedString("Choose Your Header", comment: "Choose your header button"), forState: .Normal)
        chooseImageButton.addTarget(self, action: Selector("chooseImageTapped"), forControlEvents: .TouchUpInside)
        view.addSubview(chooseImageButton)
        self.chooseImageButton = chooseImageButton
    }

}

extension CoverImageSelectionViewController {

    override public func userSetImage(image: UIImage) {
        chooseCoverImageView?.image = image
        super.userSetImage(image)
    }

    public func userUploadImage(image: UIImage, proceed: (OnboardingData?) -> Void) {
        ElloHUD.showLoadingHud()

        ProfileService().updateUserCoverImage(image, success: { _ in
            ElloHUD.hideLoadingHud()
            self.onboardingData?.coverImage = image
            proceed(self.onboardingData)
        }, failure: { _, _ in
            ElloHUD.hideLoadingHud()
            self.userUploadFailed()
        })
    }

    override public func userUploadFailed() {
        chooseCoverImageView?.image = chooseCoverImageDefault()
        onboardingData?.coverImage = nil
        super.userUploadFailed()
    }

}

