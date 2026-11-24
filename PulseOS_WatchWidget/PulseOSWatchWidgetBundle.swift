import WidgetKit
import SwiftUI

@main
struct PulseOSWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        HRVStateComplication()
        OvernightVitalsComplication()
    }
}
