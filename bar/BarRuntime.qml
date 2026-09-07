pragma ComponentBehavior: Bound
import Quickshell

Scope {
    id: root
    required property var desktop
    AppIconResolver { id: iconResolver }
    SystemClock { id: wallClock; precision: SystemClock.Minutes }
    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
            state: root.desktop
            icons: iconResolver
            clock: wallClock
        }
    }
}
