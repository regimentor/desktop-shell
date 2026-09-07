import QtQuick

Image {
    id: root
    required property string name
    property color color: "white"
    readonly property var paths: ({
        apps: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
        volume: '<path d="M11 4 6 8H3v8h3l5 4Z"/><path d="M15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
        bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
        quiet: '<path d="M9 3a6 6 0 0 1 9 5v4M6 7c0 6-3 8-3 10h14M10 21h4M3 3l18 18"/>',
        messages: '<path d="M4 3h16v18l-4-3H4Z"/><path d="M8 7h8M8 11h8M8 15h4"/>',
        filter: '<path d="M3 4h18l-7 8v7l-4 2v-9Z"/>',
        trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/>',
        close: '<path d="m6 6 12 12M18 6 6 18"/>'
    })
    width: 20
    height: 20
    sourceSize: Qt.size(48, 48)
    source: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="'
        + color.toString() + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + (paths[name] || paths.messages) + '</svg>')
    fillMode: Image.PreserveAspectFit
}
