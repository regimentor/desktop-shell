import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "AudioMath.js" as AudioMath

Scope {
    id: root
    readonly property bool ready: Pipewire.ready
    readonly property var nodes: Pipewire.nodes.values.filter(node => node.audio !== null)
    readonly property var streams: nodes.filter(node => node.ready && node.type === PwNodeType.AudioOutStream)
    readonly property var outputs: nodes.filter(node => node.ready && node.type === PwNodeType.AudioSink)
    readonly property var defaultOutput: Pipewire.defaultAudioSink
    readonly property var groups: buildGroups()
    // A group's state stays Unlinked until the group itself is bound in 0.3.1.
    // Binding individual links does not bind their group.
    PwObjectTracker { objects: root.nodes.concat(Array.from(Pipewire.linkGroups.values)) }
    property var proportions: ({})
    property var channelProportions: ({})
    onGroupsChanged: {
        const next = {};
        for (const group of groups) {
            const saved = proportions[group.key];
            if (saved && saved.members === membership(group.nodes)) next[group.key] = saved;
        }
        proportions = next;
        const channels = {};
        for (const node of nodes) {
            const key = nodeKey(node);
            if (channelProportions[key]) channels[key] = channelProportions[key];
        }
        channelProportions = channels;
    }

    function nodeKey(node: var): string {
        return String(node.properties["object.serial"] || node.id);
    }
    function membership(members: var): string {
        return members.map(node => nodeKey(node)).sort().join(",");
    }
    function usable(node: var): bool {
        return ready && node && nodes.includes(node) && node.ready && node.audio !== null;
    }
    function setDefaultOutput(node: var): void {
        if (!usable(node) || !outputs.includes(node)) return;
        Pipewire.preferredDefaultAudioSink = node;
    }
    function label(node: var): string {
        return node ? node.description || node.nickname || node.name || "Неизвестный выход" : "Нет выхода";
    }
    function streamLabel(node: var): string {
        return node.properties["media.name"] || node.properties["media.title"] || node.description || node.name || "Поток";
    }
    function buildGroups(): var {
        const result = [];
        for (const node of streams) {
            const props = node.properties;
            const key = AudioMath.identity(props, nodeKey(node));
            let group = result.find(item => item.key === key);
            if (!group) {
                const id = props["application.id"] || "";
                const desktop = DesktopEntries.applications.values.find(entry => entry.id === id || entry.id + ".desktop" === id);
                group = { key: key, name: desktop ? desktop.name : props["application.name"] || "Неизвестное приложение",
                    icon: desktop ? desktop.icon : props["application.icon-name"] || "application-x-executable", nodes: [] };
                result.push(group);
            }
            group.nodes.push(node);
        }
        return result.sort((a, b) => a.name.localeCompare(b.name) || a.key.localeCompare(b.key));
    }
    function volume(members: var): real {
        return AudioMath.maximum(members.filter(node => usable(node)).map(node => node.audio.volume));
    }
    function muteState(members: var): string {
        return AudioMath.muteState(members.filter(node => usable(node)).map(node => node.audio.muted));
    }
    function setNodeVolume(node: var, value: real): void {
        if (!usable(node)) return;
        // Quickshell already converts PipeWire's linear scale. Preserve channel
        // balance through zero too; its volume setter only preserves nonzero ratios.
        const key = nodeKey(node);
        const channels = Array.from(node.audio.channels);
        const signature = channels.join(",");
        const volumes = Array.from(node.audio.volumes);
        const average = node.audio.volume;
        if (average > 0) channelProportions[key] = { signature: signature, ratios: volumes.map(v => v / average) };
        const saved = channelProportions[key];
        if (average === 0 && saved && saved.signature === signature)
            node.audio.volumes = saved.ratios.map(ratio => ratio * AudioMath.clamp(value));
        else node.audio.volume = AudioMath.clamp(value);
    }
    function setVolume(group: var, value: real): void {
        if (!group || !group.nodes.every(node => usable(node))) return;
        const saved = proportions[group.key];
        const members = membership(group.nodes);
        const result = AudioMath.scaled(group.nodes.map(node => node.audio.volume), value,
            saved && saved.members === members ? saved.ratios : null);
        if (result.ratios) proportions[group.key] = { members: members, ratios: result.ratios };
        group.nodes.forEach((node, index) => setNodeVolume(node, result.values[index]));
    }
    function toggleMute(members: var): void {
        const live = members.filter(node => usable(node));
        const mute = muteState(live) !== "muted";
        for (const node of live) node.audio.muted = mute;
    }
    function targets(node: var): var {
        return Pipewire.linkGroups.values.filter(link => link.source === node
            && (link.state === PwLinkState.Active || link.state === PwLinkState.Paused)
            && outputs.includes(link.target)).map(link => link.target);
    }
    function outputLabel(members: var): string {
        const routes = members.map(node => targets(node));
        if (routes.every(route => route.length === 0)) return "Нет выхода";
        const first = routes.length && routes[0][0];
        if (first && routes.every(route => route.length === 1 && route[0] === first)) return label(first);
        return "Разные выходы";
    }
}
