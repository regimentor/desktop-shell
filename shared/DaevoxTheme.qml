import QtQuick

QtObject {
    readonly property int motionQuick: 100
    readonly property int motionNormal: 150
    readonly property int motionEnter: 180
    readonly property int motionExit: 120

    // Catppuccin Mocha: base, surface0, text, subtext0, mauve, surface1, crust.
    readonly property string fontFamily: "Monoid"
    readonly property color background: "#1e1e2e"
    readonly property color surface: "#313244"
    readonly property color text: "#cdd6f4"
    readonly property color textMuted: "#a6adc8"
    readonly property color accent: "#cba6f7"
    readonly property color border: "#45475a"
    readonly property color shadow: "#8011111b"
    readonly property color transparent: "transparent"
    readonly property color urgent: "#f9e2af"
}
