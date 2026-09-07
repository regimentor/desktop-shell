import QtQuick
import QtTest
import Quickshell
import "../../notifications"
import "../../launcher"
import "../../desktop"

ShellRoot {
    id: root
    NotificationModel { id: model }
    DesktopState { id: desktopState }
    Launcher { desktop: desktopState; id: launcher; notifications: model }
    NotificationPopups { desktop: desktopState; id: popups; notifications: model }
    TestCase { id: tester; name: "Notification UI"; parent: launcher.contentItem; when: false }
    property int stage: 0
    property int ticks: 0
    property var pane: null
    property var search: null
    property var reply: null
    property var hoverCard: null
    property bool hoverPassed: false
    function check(value: bool, label: string): void { if (!value) throw new Error("FAIL " + label); }
    function seed(id: int, app: string, summary: string): void {
        model.engine.receive(id, {app: app,group:app,summary:summary,body:"Тестовое сообщение для проверки стопок и управления с клавиатуры.",
            icon:"",image:app==="Telegram" ? "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI2NCIgaGVpZ2h0PSI2NCI+PHJlY3Qgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiByeD0iMTIiIGZpbGw9IiM4OWI0ZmEiLz48Y2lyY2xlIGN4PSIzMiIgY3k9IjIzIiByPSIxMSIgZmlsbD0iIzFlMWUyZSIvPjxwYXRoIGQ9Ik0xMiA1OGMwLTI0IDQwLTI0IDQwIDAiIGZpbGw9IiMxZTFlMmUiLz48L3N2Zz4=" : "",timeout:0,urgency:1,transient:false,actions:[],reply:true});
    }
    Timer {
        interval: 200; running: true; repeat: true
        onTriggered: {
            try {
                root.check(++root.ticks < 75, "UI timeout " + root.stage);
                if (root.stage === 0) {
                    if (!model.initialized) return;
                    console.log("Actual compositor lock state:", model.lockState);
                    model.engine.setDnd(false);
                    model.engine.setLock("unlocked");
                    root.seed(1,"Telegram","Встречаемся у входа");
                    root.seed(2,"Telegram","Обновление встречи");
                    root.seed(3,"Files","Копирование завершено");
                    launcher.open();
                } else if (root.stage === 1) {
                    root.search=tester.findChild(launcher.contentItem,"launcherSearch");
                    root.pane=tester.findChild(launcher.contentItem,"notificationPane");
                    root.check(root.search && root.pane,"pane loaded");
                    root.search.forceActiveFocus();
                    tester.keyClick(Qt.Key_3,Qt.AltModifier);
                } else if (root.stage === 2) {
                    root.check(launcher.mode === "notifications","Alt+3");
                    tester.findChild(launcher.contentItem,"mode-apps").parent.grabToImage(result =>
                        result.saveToFile(Quickshell.env("DAEVOX_TEST_OUTPUT")+"/launcher-tabs.png"));
                    root.check(root.pane.rows.length === 2,"one stack and one single card");
                    root.pane.selected = "group:Telegram";
                    tester.keyClick(Qt.Key_Return);
                } else if (root.stage === 3) {
                    root.check(root.pane.rows.length === 4,"Enter expands stack");
                    tester.findChild(launcher.contentItem,"launcherPanel").grabToImage(result => {
                        result.saveToFile(Quickshell.env("DAEVOX_TEST_OUTPUT")+"/notifications-expanded.png");
                        root.search.text="встречи";
                    });
                } else if (root.stage === 4) {
                    root.check(root.pane.rows.length===1,"search filters group members");
                    tester.keyClick(Qt.Key_Backspace);
                    root.check(model.records.length===3,"Backspace in search edits text");
                    tester.keyClick(Qt.Key_Escape);
                    root.check(launcher.visible && root.search.text==="","Escape clears query");
                    root.pane.replyKey=model.records[0].key;
                } else if (root.stage === 5) {
                    root.reply=tester.findChild(root.pane,"notificationReply");
                    // Find the active editor; all rendered cards have an editor.
                    function active(item) {
                        if (item.objectName === "notificationReply" && item.visible && item.activeFocus) return item;
                        for (const child of item.children || []) { const found=active(child); if(found)return found; }
                        return null;
                    }
                    root.reply=active(root.pane);
                    root.check(root.reply!==null,"reply takes focus");
                    tester.keyClick(Qt.Key_A);
                    tester.keyClick(Qt.Key_Escape);
                } else if (root.stage === 6) {
                    root.check(!root.pane.replyKey && launcher.visible,"Escape closes only reply");
                    root.check(model.draft(model.records[0].key)==="a","draft retained");
                    root.pane.selected="group:Telegram";
                    root.pane.toggle("Telegram");
                    root.pane.forceActiveFocus();
                    launcher.handleKey({key:Qt.Key_Backspace,modifiers:0,accepted:false,isAutoRepeat:false},false);
                } else if (root.stage === 7) {
                    root.check(model.records.length===1 && model.records[0].app==="Files","Backspace deletes entire stack");
                    model.engine.setLock("locked");
                } else if (root.stage === 8) {
                    root.check(!launcher.visible,"lock closes launcher");
                    launcher.open(); root.check(!launcher.visible,"lock prevents reopening");
                    model.engine.setLock("unlocked"); launcher.open(); launcher.switchMode("notifications");
                    root.seed(4,"Telegram","Новая стопка"); root.seed(5,"Telegram","Последнее сообщение");
                } else if (root.stage === 9) {
                    root.pane.expanded={};
                    tester.findChild(launcher.contentItem,"launcherPanel").grabToImage(result => {
                        root.check(result.saveToFile(Quickshell.env("DAEVOX_TEST_OUTPUT")+"/notifications-stacks.png"),"screenshot");

                    });
                } else if (root.stage === 10) {
                    for (let i=10;i<22;i++) root.seed(i,"App " + i,"Проверка компактной карточки");
                } else if (root.stage === 11) {
                    const list=tester.findChild(root.pane,"notificationList");
                    list.positionViewAtBeginning();
                    root.hoverCard=list.itemAtIndex(0).item;
                    root.pane.selected=root.pane.rows[1].id;
                    console.log("Card height:",root.hoverCard.height);
                    tester.mouseMove(root.hoverCard,root.hoverCard.width/2,5);
                } else if (root.stage === 12) {
                    root.hoverPassed=String(root.hoverCard.border.color)===String(root.hoverCard.theme.accent);
                    tester.mouseMove(root.search,2,2);
                    root.search.forceActiveFocus();
                    tester.keyClick(Qt.Key_Down);
                } else if (root.stage === 13) {
                    const bar=tester.findChild(root.pane,"notificationScrollBar");
                    const gap=bar.mapToItem(root.pane,0,0).x-root.hoverCard.mapToItem(root.pane,root.hoverCard.width,0).x;
                    console.log("UI regression: hover="+root.hoverPassed+" scrollbar gap="+gap+" keyboard active="+bar.active);
                    root.check(root.hoverPassed,"hover highlights card");
                    root.check(gap>=4,"scrollbar gutter");
                    root.check(bar.active,"keyboard navigation reveals scrollbar");
                    console.log("NOTIFICATION UI PASS: navigation, stacks, reply, lock, hover, scrollbar");
                    Qt.quit();
                }
                root.stage++;
            } catch (error) { console.error(String(error)); Qt.quit(); }
        }
    }
}
