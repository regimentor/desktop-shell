import QtQuick
import Quickshell

QtObject {
    id: root
    property var cache: ({})
    readonly property var catalogue: DesktopEntries.applications.values
    onCatalogueChanged: cache = ({})
    function resolve(appClass: string, initialClass: string): string {
        const key = appClass + "\n" + initialClass;
        if (cache[key]) return cache[key];
        let entry = null;
        for (const name of [appClass, initialClass]) {
            if (name) entry = DesktopEntries.byId(name.replace(/\.desktop$/, ""));
            if (entry) break;
        }
        if (!entry) for (const name of [appClass, initialClass]) {
            if (name) entry = DesktopEntries.heuristicLookup(name);
            if (entry) break;
        }
        const icon = entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : "";
        const fallback = Quickshell.iconPath("application-x-executable", true) || Qt.resolvedUrl("application.svg").toString();
        cache[key] = icon || fallback;
        return cache[key];
    }
}
