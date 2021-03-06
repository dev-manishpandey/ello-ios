////
///  SearchStreamCell.swift
//

class SearchStreamCell: CollectionViewCell {
    static let reuseIdentifier = "SearchStreamCell"
    struct Size {
        static let insets: CGFloat = 10
    }

    private var debounced = debounce(0.8)
    private let searchField = SearchTextField()

    var placeholder: String? {
        get { return searchField.placeholder }
        set { searchField.placeholder = newValue }
    }
    var search: String? {
        get { return searchField.text }
        set { searchField.text = newValue }
    }

    override func style() {
        backgroundColor = .white
    }

    override func bindActions() {
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchFieldDidChange), for: .editingChanged)
    }

    override func arrange() {
        contentView.addSubview(searchField)

        searchField.snp.makeConstraints { make in
            make.top.bottom.equalTo(contentView)
            make.leading.trailing.equalTo(contentView).inset(Size.insets)
        }
    }
}

extension SearchStreamCell: DismissableCell {
    func didEndDisplay() {
        _ = searchField.resignFirstResponder()
    }
    func willDisplay() {
        // no op
    }
}

extension SearchStreamCell: UITextFieldDelegate {

    @objc
    func searchFieldDidChange() {
        let text = searchField.text ?? ""
        if text.isEmpty {
            clearSearch()
        }
        else {
            debounced { [weak self] in
                self?.performSearch()
            }
        }
    }

    @objc
    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.setNeedsLayout()
        textField.layoutIfNeeded()
    }

    @objc
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        _ = textField.resignFirstResponder()
        return true
    }

    private func performSearch() {
        guard
            let text = searchField.text,
            !text.isEmpty
        else { return }

        let responder: SearchStreamResponder? = findResponder()
        responder?.searchFieldChanged(text: text)
    }

    private func clearSearch() {
        let responder: SearchStreamResponder? = findResponder()
        responder?.searchFieldChanged(text: "")
        debounced {}
    }
}
