//@ pragma UseQApplication
//@ pragma IconTheme Adwaita
pragma ComponentBehavior: Bound
import Quickshell

ShellRoot {
    HyprlandState { id: barState }
    AppIconResolver { id: iconResolver }
    SystemClock { id: wallClock; precision: SystemClock.Minutes }
    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
            state: barState
            icons: iconResolver
            clock: wallClock
        }
    }
}
