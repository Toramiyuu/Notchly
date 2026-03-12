import SwiftUI

/// Conceptual protocol for a Notchly widget.
/// Concrete widgets are registered in WidgetRegistry using view-builder closures.
///
/// To add a new widget:
/// 1. Create a SwiftUI View for the widget body (e.g. `MyWidgetView`)
/// 2. Create a SwiftUI View for settings (e.g. `MyWidgetSettingsView`)
/// 3. Add a WidgetEntry to `WidgetRegistry.buildDefaultWidgets()`
