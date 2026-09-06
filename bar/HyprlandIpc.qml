pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property string socketDirectory: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    property int timeoutMs: 2500
    property int generation: 0
    property bool online: false
    property var queue: []
    property var requestSocket: null
    property var eventSocket: null
    property int retryMs: 250
    signal opened()
    signal eventReceived(string line)
    signal response(string key, string body)
    signal unavailable(string reason)

    function start(): void {
        retry.stop();
        const socket = eventFactory.createObject(root, { epoch: generation });
        eventSocket = socket;
        deadline.restart();
        socket.connected = true;
    }
    function fail(reason: string): void {
        ++generation;
        online = false;
        queue = [];
        deadline.stop();
        const request = requestSocket, events = eventSocket;
        requestSocket = null;
        eventSocket = null;
        if (request) { request.connected = false; request.destroy(); }
        if (events) { events.connected = false; events.destroy(); }
        unavailable(reason);
        retry.interval = retryMs;
        retryMs = Math.min(8000, retryMs * 2);
        retry.restart();
    }
    function enqueue(key: string, command: string): void {
        if (!online) return;
        queue.push({ key: key, command: command });
        pump();
    }
    function pump(): void {
        if (!online || requestSocket || !queue.length) return;
        const job = queue.shift();
        const socket = requestFactory.createObject(root, { epoch: generation, key: job.key, command: job.command });
        requestSocket = socket;
        deadline.restart();
        socket.connected = true;
    }
    function finish(socket: var): void {
        if (!socket || socket.epoch !== generation || socket !== requestSocket) return;
        deadline.stop();
        requestSocket = null;
        const key = socket.key, body = socket.body;
        socket.destroy();
        response(key, body);
        Qt.callLater(pump);
    }
    Component.onCompleted: start()
    Timer { id: retry; onTriggered: root.start() }
    Timer { id: deadline; interval: root.timeoutMs; onTriggered: root.fail("IPC timeout") }
    Component {
        id: eventFactory
        Socket {
            id: events
            required property int epoch
            path: root.socketDirectory + "/.socket2.sock"
            parser: SplitParser {
                onRead: data => {
                    if (events.epoch === root.generation && events.connected)
                        root.eventReceived(data);
                }
            }
            onConnectionStateChanged: {
                if (epoch !== root.generation) return;
                if (connected) {
                    root.deadlineStop();
                    root.online = true;
                    root.opened();
                } else root.fail("Event stream disconnected");
            }
            onError: error => { if (epoch === root.generation) root.fail("Event socket error " + error); }
        }
    }
    function deadlineStop(): void { deadline.stop(); }
    Component {
        id: requestFactory
        Socket {
            id: request
            required property int epoch
            required property string key
            required property string command
            property bool sent: false
            readonly property string body: collector.text
            path: root.socketDirectory + "/.socket.sock"
            // Collect bytes before decoding, including UTF-8 split across reads.
            parser: StdioCollector { id: collector; waitForEnd: false }
            onConnectionStateChanged: {
                if (epoch !== root.generation) return;
                if (connected) { sent = true; write(command); flush(); }
                else if (sent) Qt.callLater(() => root.finish(request));
            }
            onError: error => {
                // PeerClosedError is the normal response delimiter on this socket.
                if (epoch === root.generation && !(error === 1 && sent))
                    root.fail("Request socket error " + error);
            }
        }
    }
}
