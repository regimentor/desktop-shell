import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string query: ""
    property string error: ""
    readonly property bool launching: launchProcess.running
    signal launched()

    // Reactive to the system catalogue, never rebuilt just because the window opens.
    readonly property var catalogue: DesktopEntries.applications.values.map(entry => ({
        entry: entry,
        name: normalize(entry.name),
        fields: [entry.genericName, entry.comment, entry.keywords.join(" "),
                 entry.command.join(" ")].map(value => normalize(value))
    }))
    readonly property var results: rank(catalogue, query)

    function normalize(value: string): string {
        return value.toLowerCase().replace(/ё/g, "е").trim();
    }

    // A single scoring seam for a future fuzzy matcher. All query words must match.
    function score(record: var, tokens: var): int {
        let total = 0;
        for (const token of tokens) {
            let best = -1;
            if (record.name === token) best = 100;
            else if (record.name.startsWith(token)) best = 80;
            else if (record.name.includes(token)) best = 60;
            for (let i = 0; i < record.fields.length; ++i) {
                if (record.fields[i].includes(token))
                    best = Math.max(best, 40 - i * 5);
            }
            if (best < 0) return -1;
            total += best;
        }
        return total;
    }

    function rank(records: var, text: string): var {
        const normalized = normalize(text);
        const tokens = normalized ? normalized.split(/\s+/) : [];
        return records.map(record => ({ record: record, score: score(record, tokens) }))
            .filter(hit => hit.score >= 0)
            .sort((a, b) => b.score - a.score
                || a.record.name.localeCompare(b.record.name)
                || a.record.entry.id.localeCompare(b.record.entry.id))
            .map(hit => hit.record.entry);
    }

    function launch(index: int): void {
        if (launching || index < 0 || index >= results.length) return;
        const entry = results[index];
        // Quickshell IDs omit the final .desktop suffix (including nested XDG IDs).
        const desktopId = entry.id + ".desktop";
        error = "";
        // 0.3.1 execute() ignores Terminal and field codes. Let UWSM launch the entry.
        launchProcess.command = ["uwsm", "app", "-t", "service", "--", desktopId];
        launchProcess.running = true;
    }

    Process {
        id: launchProcess
        stderr: SplitParser {
            onRead: data => {
                root.error = data.trim();
                console.warn("launcher:", data);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) {
                root.error = "";
                root.launched();
            } else if (!root.error) {
                root.error = "Launch failed (" + exitCode + "). Check the launcher log.";
            }
        }
    }
}
