import Foundation

extension String {
    /// The resource's text in `locale`'s language. Setting the locale on the resource picks the
    /// language as well as the number formats; `String(localized:locale:)` only formats values.
    init(localized resource: LocalizedStringResource, in locale: Locale) {
        var resource = resource
        resource.locale = locale
        self.init(localized: resource)
    }
}
