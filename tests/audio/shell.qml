import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../../launcher"

ShellRoot {
    id: root
    AudioModel { id: model }
    AudioRouter { id: route; audio: model }
    property int stage: 0
    property int ticks: 0
    property var group: model.groups.find(item => item.key === "app:daevox.test")
    property var first: group ? group.nodes[0] : null
    property var second: group ? group.nodes[1] : null
    property var sinkA: model.outputs.find(node => node.name === "test-a")
    property var sinkB: model.outputs.find(node => node.name === "test-b")
    property real previousSinkVolume: 0
    Process {
        id: newcomer
        command: ["pw-play", "--raw", "--rate", "48000", "--channels", "2", "--target", "test-b", "-P",
            "{ application.id = daevox.test application.name = Test media.name = Third node.dont-move = true }", "/dev/zero"]
    }
    Process { id: removeOutput }
    Process {
        id: disableRouting
        command: ["wpctl", "settings", "linking.allow-moving-streams", "false"]
        onExited: route.check()
    }

    function check(condition: bool, label: string): void {
        if (!condition) throw new Error("FAIL " + label);
    }
    function near(actual: real, expected: real): bool { return Math.abs(actual - expected) < 0.002; }
    function next(): void { stage++; ticks = 0; }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            try {
                root.ticks++;
                root.check(root.ticks < 100, "timeout at stage " + root.stage);
                if (root.stage === 0) {
                    if (!root.group || root.group.nodes.length !== 2 || !root.sinkA || !root.sinkB || !route.available) return;
                    root.check(model.groups.length === 1, "application.id groups different clients");
                    root.first.audio.volumes = [1.0, 0.6];
                    model.setNodeVolume(root.second, 0.4);
                    root.next();
                } else if (root.stage === 1) {
                    if (!root.near(model.volume(root.group.nodes), 0.8) || !root.near(root.second.audio.volume, 0.4)) return;
                    model.setVolume(root.group, 0.6);
                    root.next();
                } else if (root.stage === 2) {
                    root.check(root.near(root.first.audio.volume, 0.6) && root.near(root.second.audio.volume, 0.3), "80/40 -> 60/30");
                    root.check(root.near(root.first.audio.volumes[0], 0.75) && root.near(root.first.audio.volumes[1], 0.45), "channel balance");
                    model.setVolume(root.group, 0);
                    root.next();
                } else if (root.stage === 3) {
                    root.check(model.volume(root.group.nodes) === 0, "group zero");
                    model.setVolume(root.group, 0.6);
                    root.next();
                } else if (root.stage === 4) {
                    root.check(root.near(root.first.audio.volume, 0.6) && root.near(root.second.audio.volume, 0.3), "restore group ratios");
                    root.check(root.near(root.first.audio.volumes[0], 0.75) && root.near(root.first.audio.volumes[1], 0.45), "restore channel balance");
                    root.first.audio.muted = true;
                    root.second.audio.muted = false;
                    root.next();
                } else if (root.stage === 5) {
                    root.check(model.muteState(root.group.nodes) === "mixed", "partial mute");
                    model.toggleMute(root.group.nodes);
                    root.next();
                } else if (root.stage === 6) {
                    root.check(model.muteState(root.group.nodes) === "muted", "mute all");
                    model.setVolume(root.group, 0.5);
                    root.next();
                } else if (root.stage === 7) {
                    root.check(model.muteState(root.group.nodes) === "muted", "volume does not unmute");
                    model.toggleMute(root.group.nodes);
                    root.previousSinkVolume = root.sinkB.audio.volume;
                    Pipewire.preferredDefaultAudioSink = root.sinkA;
                    root.next();
                } else if (root.stage === 8) {
                    if (model.defaultOutput !== root.sinkA) return;
                    model.setNodeVolume(model.defaultOutput, 0.35);
                    model.toggleMute([model.defaultOutput]);
                    root.next();
                } else if (root.stage === 9) {
                    root.check(root.near(root.sinkA.audio.volume, 0.35), "system default volume");
                    root.check(root.near(root.sinkB.audio.volume, root.previousSinkVolume), "other sink untouched");
                    root.check(model.muteState(root.group.nodes) === "audible", "system mute leaves streams alone");
                    Pipewire.preferredDefaultAudioSink = root.sinkB;
                    root.next();
                } else if (root.stage === 10) {
                    if (model.defaultOutput !== root.sinkB) return;
                    root.check(root.near(model.defaultOutput.audio.volume, root.previousSinkVolume), "default follows actual state");
                    route.move(root.group, root.sinkB);
                    root.check(route.pending, "route pending before confirmation");
                    root.next();
                } else if (root.stage === 11) {
                    if (route.pending) return;
                    console.log("Routing evidence:", JSON.stringify(Pipewire.linkGroups.values.map(link => ({
                        source: link.source ? link.source.name : "", target: link.target ? link.target.name : "", state: link.state
                    }))));
                    root.check(route.message === "Выход переключён", route.message);
                    root.check(model.outputLabel(root.group.nodes) === "Test Headphones", "actual routes confirmed");
                    model.setVolume(root.group, 0);
                    newcomer.running = true;
                    root.next();
                } else if (root.stage === 12) {
                    if (root.group.nodes.length !== 3) return;
                    const third = root.group.nodes.find(node => node.properties["media.name"] === "Third");
                    // WirePlumber may itself restore zero for this application.
                    root.check(root.first.audio.volume === 0 && root.second.audio.volume === 0, "newcomer leaves existing streams unchanged");
                    model.setNodeVolume(third, 0);
                    root.next();
                } else if (root.stage === 13) {
                    root.check(model.volume(root.group.nodes) === 0, "all zero after newcomer");
                    model.setVolume(root.group, 0.3);
                    root.next();
                } else if (root.stage === 14) {
                    root.check(root.group.nodes.every(node => root.near(node.audio.volume, 0.3)), "membership invalidates remembered ratios");
                    route.move(root.group, root.sinkA);
                    root.next();
                } else if (root.stage === 15) {
                    if (route.pending) return;
                    root.check(route.confirmed === 2 && route.message.includes("2/3"), "partial transfer reported: " + route.message);
                    root.check(model.outputLabel(root.group.nodes) === "Разные выходы", "mixed outputs");
                    root.next();
                } else if (root.stage === 16) {
                    route.move(root.group, root.sinkA);
                    removeOutput.command = ["pw-cli", "destroy", String(root.sinkA.id)];
                    removeOutput.running = true;
                    root.next();
                } else if (root.stage === 17) {
                    if (root.sinkA || route.pending) return;
                    root.check(route.message === "Устройство отключено", "pending target disappearance");
                    root.check(model.outputLabel(root.group.nodes) !== "Test Speakers", "disconnected target is not displayed");
                    root.check(root.group.nodes.every(node => !node.audio.muted), "disconnect does not automute");
                    newcomer.running = false;
                    disableRouting.running = true;
                    root.next();
                } else if (root.stage === 18) {
                    if (disableRouting.running || route.unavailableReason === "Проверка маршрутизации…") return;
                    root.check(!route.available && model.ready, "unavailable routing leaves audio observation working");
                    model.setVolume(root.group, 0.4);
                    removeOutput.command = ["pw-cli", "destroy", String(root.sinkB.id)];
                    removeOutput.running = true;
                    root.next();
                } else if (root.stage === 19) {
                    if (model.outputs.length || model.defaultOutput) return;
                    root.check(!model.usable(model.defaultOutput), "no default sink disables controls");
                    model.setNodeVolume(model.defaultOutput, 0.5);
                    model.toggleMute([model.defaultOutput]);
                    console.log("AUDIO INTEGRATION PASS: groups, scale, ratios, channel balance, mute, default sink, metadata routing, membership, partial transfer, disconnect, unavailable routing, no outputs");
                    Qt.quit();
                }
            } catch (error) {
                console.error(String(error));
                Qt.quit();
            }
        }
    }
}
