import WidgetKit
import SwiftUI

@main
struct MettitiWidgetsBundle: WidgetBundle {
    var body: some Widget {
        EmojiWidget()
        DescriptionWidget()
        CombinedWidget()
    }
}
