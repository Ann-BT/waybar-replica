import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Io
import Quickshell.Widgets
import "."

ShellRoot {
    id: root

    // Theme Colors
    property color mSurface: "#091516"
    property color mOutline: "#324b4c"
    property color mPrimary: "#88d990"
    property color mSecondary: "#9cd49f"
    property color mOnSurface: "#d7e5e5"
    property color mOnPrimary: "#0f1414"

    onMPrimaryChanged: Theme.active = mPrimary
    onMOnSurfaceChanged: Theme.text = mOnSurface
    onMSurfaceChanged: Theme.background = mSurface

    Component.onCompleted: {
        Theme.active = root.mPrimary
        Theme.text = root.mOnSurface
        Theme.background = root.mSurface
    }

    // Wallpaper Selector State
    property bool wallpaperMode: false
    property var wallpapersList: []
    property string currentWallpaperPath: ""
    property string applyingPath: ""
    property int selectedIndex: 0

    // App Launcher State
    property bool launcherMode: false
    property var allAppsList: []
    property var filteredAppsList: []
    property string launcherSearchQuery: ""
    property int launcherSelectedIndex: 0
    property bool popupActive: false
    property real currentBarWidth: 200
    property var pinnedAppsList: []

    // Session State
    property bool sessionMode: false
    property int sessionSelectedIndex: 0

    // Notification State
    property bool notificationMode: false
    property string notifAppName: ""
    property string notifSummary: ""
    property string notifBody: ""

    Timer {
        id: notificationCloseTimer
        interval: 4000 // Display notification for 4 seconds
        repeat: false
        onTriggered: {
            root.notificationMode = false
        }
    }

    // Control Center State
    property bool controlCenterMode: false
    property bool ccWifi: false
    property string ccWifiSsid: ""
    property bool ccBluetooth: false
    property string ccProfile: ""

    // Control Center Sub-menu details
    property int ccPage: 0
    property string selectedWifiSsid: ""
    property string selectedWifiSecurity: ""
    property string wifiPasswordQuery: ""
    property string ccActionStatus: ""

    property string _ccBuf: ""
    Process {
        id: controlCenterProc
        command: ["bash", "/home/merlin/.config/quickshell/waybar-replica/scripts/control_center.sh", "get"]
        stdout: SplitParser {
            onRead: function(line) { root._ccBuf += line }
        }
        onExited: function() {
            if (root._ccBuf !== "") {
                try {
                    var obj = JSON.parse(root._ccBuf)
                    root.ccWifi = obj.wifi
                    root.ccWifiSsid = obj.wifi_ssid
                    root.ccBluetooth = obj.bluetooth
                    root.ccProfile = obj.profile ? obj.profile : ""
                } catch(e) {
                    console.log("Error parsing control center JSON: " + e)
                }
            }
            root._ccBuf = ""
        }
        
        function run(action) {
            if (running) return
            root._ccBuf = ""
            command = ["bash", "/home/merlin/.config/quickshell/waybar-replica/scripts/control_center.sh", action || "get"]
            running = true
        }
    }



    Timer {
        id: popupCloseTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.popupActive = false
        }
    }

    // IPC to toggle app launcher
    IpcHandler {
        target: "waybarLauncher"
        function toggle(): void {
            root.launcherMode = !root.launcherMode
        }
    }

    // IPC to toggle wallpaper selector
    IpcHandler {
        target: "wallpaperSelectorToggle"
        function toggle(): void {
            root.wallpaperMode = !root.wallpaperMode
        }
    }

    // IPC to toggle session menu
    IpcHandler {
        target: "sessionToggle"
        function toggle(): void {
            root.sessionMode = !root.sessionMode
        }
    }

    // IPC to toggle control center
    IpcHandler {
        target: "controlCenterToggle"
        function toggle(): void {
            root.controlCenterMode = !root.controlCenterMode
        }
    }

    // IPC to receive notifications
    IpcHandler {
        target: "notificationService"
        function display(appName: string, summary: string, body: string) {
            if (!root.launcherMode && !root.wallpaperMode && !root.sessionMode) {
                root.notifAppName = appName
                root.notifSummary = summary
                root.notifBody = body
                root.notificationMode = true
                notificationCloseTimer.restart()
            }
        }
    }

    // Process to list wallpapers in ~/Pictures/Wallpapers
    Process {
        id: listWallpapersProc
        command: [
            "bash", "-c",
            "find /home/merlin/Pictures/Wallpapers -maxdepth 1 -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "-o -iname '*.gif' -o -iname '*.webp' \\) | sort"
        ]
        property var tempWalls: []
        stdout: SplitParser {
            onRead: function(line) {
                var t = line.trim()
                if (t !== "") listWallpapersProc.tempWalls.push(t)
            }
        }
        onExited: function() {
            root.wallpapersList = listWallpapersProc.tempWalls
        }
        
        function run() {
            if (running) return
            tempWalls = []
            running = true
        }
    }

    // Loader for current wallpaper path from Brain_Shell configuration
    function loadCurrentWallpaper() {
        readConfigProc.running = true
    }

    property string _cfgBuf: ""
    Process {
        id: readConfigProc
        command: ["bash", "-c", "cat /home/merlin/.config/Brain_Shell/src/user_data/wallpaper.json 2>/dev/null"]
        stdout: SplitParser {
            onRead: function(line) { root._cfgBuf += line }
        }
        onExited: function() {
            if (root._cfgBuf !== "") {
                try {
                    var obj = JSON.parse(root._cfgBuf)
                    if (obj.currentWall) root.currentWallpaperPath = obj.currentWall
                } catch(e) {}
            }
            root._cfgBuf = ""
        }
    }

    // Process to apply wallpaper
    Process {
        id: applyWallpaperProc
        stdout: SplitParser {
            onRead: (line) => console.log("applyWallpaperProc stdout: " + line)
        }
        stderr: SplitParser {
            onRead: (line) => console.log("applyWallpaperProc stderr: " + line)
        }
        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.currentWallpaperPath = root.applyingPath
            }
            root.applyingPath = ""
            root.wallpaperMode = false
            saveConfig()
        }
    }

    function applyWallpaper(path) {
        if (applyingPath !== "") return
        applyingPath = path
        applyWallpaperProc.command = ["bash", "/home/merlin/.config/quickshell/waybar-replica/scripts/apply_wallpaper.sh", path]
        applyWallpaperProc.running = true
    }

    // Save configuration
    function saveConfig() {
        var json = JSON.stringify({
            currentWall: root.currentWallpaperPath,
            wallpaperDir: "~/Pictures/Wallpapers",
            scheme: "content"
        })
        saveConfigProc.command = [
            "bash", "-c",
            "mkdir -p ~/.config/Brain_Shell/src/user_data && " +
            "printf '%s' '" + json.replace(/'/g, "'\\''") + "' > ~/.config/Brain_Shell/src/user_data/wallpaper.json"
        ]
        saveConfigProc.running = true
    }

    Process {
        id: saveConfigProc
    }

    // App Launcher Processes & Functions
    Process {
        id: listAppsProc
        command: ["python3", "/home/merlin/.config/quickshell/waybar-replica/scripts/list_apps.py"]
        property string _buf: ""
        stdout: SplitParser {
            onRead: (line) => listAppsProc._buf += line
        }
        onExited: (code) => {
            if (code === 0 && listAppsProc._buf !== "") {
                try {
                    root.allAppsList = JSON.parse(listAppsProc._buf)
                    filterApps()
                } catch(e) {}
            }
            listAppsProc._buf = ""
        }
    }

    Process {
        id: launchAppProc
    }

    Process {
        id: savePinnedProc
    }

    function savePinnedApps(list) {
        var json = JSON.stringify({ pinned: list })
        savePinnedProc.command = [
            "bash", "-c",
            "mkdir -p ~/.config/Brain_Shell/src/user_data && " +
            "printf '%s' '" + json.replace(/'/g, "'\\''") + "' > ~/.config/Brain_Shell/src/user_data/pinned_apps.json"
        ]
        savePinnedProc.running = true
    }

    function filterApps() {
        var query = root.launcherSearchQuery.toLowerCase().trim()
        var filtered = []
        for (var i = 0; i < root.allAppsList.length; i++) {
            var app = root.allAppsList[i]
            var isPinned = root.pinnedAppsList.indexOf(app.name) !== -1
            var appCopy = {
                name: app.name,
                exec: app.exec,
                icon: app.icon,
                pinned: isPinned
            }
            if (query === "" || appCopy.name.toLowerCase().indexOf(query) !== -1) {
                filtered.push(appCopy)
            }
        }
        filtered.sort(function(a, b) {
            if (a.pinned && !b.pinned) return -1
            if (!a.pinned && b.pinned) return 1
            if (a.pinned && b.pinned) {
                var idxA = root.pinnedAppsList.indexOf(a.name)
                var idxB = root.pinnedAppsList.indexOf(b.name)
                return idxA - idxB
            }
            return a.name.localeCompare(b.name)
        })
        root.filteredAppsList = filtered
        root.launcherSelectedIndex = 0
    }

    function launchApp(execCmd) {
        launchAppProc.command = ["bash", "-c", execCmd]
        launchAppProc.running = true
        root.launcherMode = false
    }

    onLauncherSearchQueryChanged: {
        filterApps()
    }

    onLauncherModeChanged: {
        if (launcherMode) {
            popupCloseTimer.stop()
            root.popupActive = true
            root.wallpaperMode = false
            root.sessionMode = false
            root.controlCenterMode = false
            root.notificationMode = false
            listAppsProc.running = true
            root.launcherSearchQuery = ""
            root.launcherSelectedIndex = 0
        } else if (!root.wallpaperMode && !root.sessionMode && !root.controlCenterMode) {
            popupCloseTimer.restart()
        }
    }

    onWallpaperModeChanged: {
        if (wallpaperMode) {
            popupCloseTimer.stop()
            root.popupActive = true
            root.launcherMode = false
            root.sessionMode = false
            root.controlCenterMode = false
            root.notificationMode = false
            listWallpapersProc.run()
            loadCurrentWallpaper()
            root.selectedIndex = 0
        } else if (!root.launcherMode && !root.sessionMode && !root.controlCenterMode) {
            popupCloseTimer.restart()
        }
    }

    onSessionModeChanged: {
        if (sessionMode) {
            popupCloseTimer.stop()
            root.popupActive = true
            root.launcherMode = false
            root.wallpaperMode = false
            root.controlCenterMode = false
            root.notificationMode = false
            root.sessionSelectedIndex = 0
        } else if (!root.launcherMode && !root.wallpaperMode && !root.controlCenterMode) {
            popupCloseTimer.restart()
        }
    }

    onControlCenterModeChanged: {
        if (controlCenterMode) {
            popupCloseTimer.stop()
            root.popupActive = true
            root.launcherMode = false
            root.wallpaperMode = false
            root.sessionMode = false
            root.notificationMode = false
            root.ccPage = 0
            root.selectedWifiSsid = ""
            root.wifiPasswordQuery = ""
            controlCenterProc.run("get")
        } else {
            root.ccPage = 0
            root.selectedWifiSsid = ""
            root.wifiPasswordQuery = ""
            if (!root.launcherMode && !root.wallpaperMode && !root.sessionMode) {
                popupCloseTimer.restart()
            }
        }
    }

    function triggerSessionAction(index) {
        root.sessionMode = false
        if (index === 0) {
            Quickshell.execDetached(["hyprlock"])
        } else if (index === 1) {
            Quickshell.execDetached(["hyprctl", "dispatch", "exit"])
        } else if (index === 2) {
            Quickshell.execDetached(["systemctl", "suspend"])
        } else if (index === 3) {
            Quickshell.execDetached(["systemctl", "reboot"])
        } else if (index === 4) {
            Quickshell.execDetached(["systemctl", "poweroff"])
        }
    }

    FileView {
        id: colorsFile
        path: "/home/merlin/.local/state/quickshell/user/generated/colors.json"
        watchChanges: true
        preload: true

        onFileChanged: reload()

        onLoaded: {
            try {
                var obj = JSON.parse(text())
                if (obj.surface) mSurface = obj.surface
                if (obj.outline) mOutline = obj.outline
                if (obj.primary) mPrimary = obj.primary
                if (obj.secondary) mSecondary = obj.secondary
                if (obj.on_surface) mOnSurface = obj.on_surface
                if (obj.on_primary) mOnPrimary = obj.on_primary
            } catch (e) {
                console.log("Error parsing colors.json: " + e)
            }
        }
    }

    FileView {
        id: pinnedAppsFile
        path: "/home/merlin/.config/Brain_Shell/src/user_data/pinned_apps.json"
        watchChanges: true
        preload: true

        onFileChanged: reload()

        onLoaded: {
            try {
                var obj = JSON.parse(text())
                if (obj && Array.isArray(obj.pinned)) {
                    root.pinnedAppsList = obj.pinned
                }
            } catch (e) {
                console.log("Error parsing pinned_apps.json: " + e)
            }
            filterApps()
        }
    }

    // Time & Date updater source
    QtObject {
        id: timeDateSource
        property string timeString: ""
        property string dateString: ""

        function update() {
            var d = new Date();
            timeString = Qt.formatDateTime(d, "HH:mm");
            dateString = " • " + Qt.formatDateTime(d, "MMMM d");
        }

        Component.onCompleted: update()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: timeDateSource.update()
    }

    // ─────────────────────────────────────────────
    // BAR WINDOW — pill-shaped, no keyboard focus
    // ─────────────────────────────────────────────
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData
            property bool trayExpanded: false

            WlrLayershell.namespace: "quickshell:bar"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 80

            mask: Region {
                item: barPill
            }

            // The pill-shaped bar
            Rectangle {
                id: barPill
                height: 32
                width: mainRow.implicitWidth + 28
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6
                radius: height / 2
                color: Qt.rgba(root.mSurface.r, root.mSurface.g, root.mSurface.b, 0.75)
                border.width: 1
                border.color: Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.15)
                opacity: (root.wallpaperMode || root.launcherMode || root.sessionMode || root.controlCenterMode) ? 0.0 : 1.0
                visible: opacity > 0

                onWidthChanged: {
                    root.currentBarWidth = width
                }

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                states: [
                    State {
                        name: "notification"
                        when: root.notificationMode
                        PropertyChanges {
                            target: barPill
                            width: 400
                            height: 64
                            radius: 16
                        }
                        PropertyChanges {
                            target: mainRow
                            opacity: 0.0
                        }
                        PropertyChanges {
                            target: notificationUI
                            opacity: 1.0
                        }
                    }
                ]

                transitions: [
                    Transition {
                        from: "*"
                        to: "notification"
                        // Animate pill growth
                        NumberAnimation {
                            properties: "width,height,radius"
                            duration: 350
                            easing.type: Easing.OutCubic
                        }
                        // Fade out normal bar content instantly
                        NumberAnimation {
                            target: mainRow
                            property: "opacity"
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                        // Fade in notification content
                        NumberAnimation {
                            target: notificationUI
                            property: "opacity"
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    },
                    Transition {
                        from: "notification"
                        to: "*"
                        // Animate pill shrinking
                        NumberAnimation {
                            properties: "width,height,radius"
                            duration: 350
                            easing.type: Easing.OutCubic
                        }
                        // Fade out notification content instantly
                        NumberAnimation {
                            target: notificationUI
                            property: "opacity"
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                        // Fade in normal bar content AFTER the pill has shrunk
                        SequentialAnimation {
                            PauseAnimation { duration: 150 }
                            NumberAnimation {
                                target: mainRow
                                property: "opacity"
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]

                // Notification Content
                Row {
                    id: notificationUI
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 12
                    opacity: 0.0
                    visible: opacity > 0

                    // Notification Icon (Nerd Font bell)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰂜"
                        color: root.mPrimary
                        font {
                            family: "JetBrains Mono NF"
                            pixelSize: 24
                        }
                    }

                    // Notification Text details
                    Column {
                        width: parent.width - 44
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: root.notifAppName ? root.notifAppName.toUpperCase() : ""
                            color: root.mPrimary
                            font {
                                family: "Google Sans Flex"
                                pixelSize: 9
                                bold: true
                            }
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            width: parent.width
                            text: root.notifSummary
                            color: root.mOnSurface
                            font {
                                family: "Google Sans Flex"
                                pixelSize: 12
                                bold: true
                            }
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Text {
                            width: parent.width
                            text: root.notifBody
                            color: Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.7)
                            font {
                                family: "Google Sans Flex"
                                pixelSize: 11
                            }
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }

                // Main content row
                Row {
                    id: mainRow
                    height: 32
                    anchors.centerIn: parent
                    spacing: 12
                    opacity: 1.0
                    visible: opacity > 0

                    // 1. Clock (Time) with Hover Reveal for Date
                    MouseArea {
                        id: timeArea
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter
                        hoverEnabled: true
                        width: timeContentRow.implicitWidth + 8

                        Row {
                            id: timeContentRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                id: timeText
                                text: timeDateSource.timeString
                                color: root.mOnSurface
                                font {
                                    family: "Google Sans Flex"
                                    pixelSize: 13
                                    bold: true
                                }
                            }

                            Row {
                                id: dateDetailRow
                                clip: true
                                anchors.verticalCenter: parent.verticalCenter
                                width: timeArea.containsMouse ? implicitWidth : 0
                                Behavior on width {
                                    NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
                                }

                                Text {
                                    text: timeDateSource.dateString
                                    color: Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.7)
                                    font {
                                        family: "Google Sans Flex"
                                        pixelSize: 13
                                        bold: true
                                    }
                                }
                            }
                        }
                    }

                    // 2. Workspaces (Sliding highlights, occupied only + active)
                    Item {
                        id: workspacesContainer
                        anchors.verticalCenter: parent.verticalCenter
                        height: 24
                        width: workspacesRow.width

                        property int focusedIndex: {
                            for (var i = 0; i < 10; i++) {
                                var wsId = i + 1
                                if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wsId) {
                                    return i
                                }
                            }
                            return -1
                        }

                        property real highlightX: {
                            if (focusedIndex < 0) return 0
                            var x = 0
                            for (var i = 0; i < focusedIndex; i++) {
                                var item = workspacesRepeater.itemAt(i)
                                if (item && item.visible) {
                                    x += item.width + 4
                                }
                            }
                            return x
                        }

                        property bool hasFocused: focusedIndex >= 0

                        Rectangle {
                            id: highlightPill
                            width: 24
                            height: 24
                            radius: 8
                            color: root.mPrimary
                            opacity: workspacesContainer.hasFocused ? 1.0 : 0.0
                            x: workspacesContainer.highlightX
                            y: 0
                            z: 0

                            Behavior on x {
                                NumberAnimation {
                                    duration: 380
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.2
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                            }

                            Rectangle {
                                id: trailGlow
                                anchors.centerIn: parent
                                width: parent.width + 4
                                height: parent.height + 4
                                radius: 10
                                color: "transparent"
                                border.width: 2
                                border.color: root.mPrimary
                                opacity: 0.0
                                z: -1

                                SequentialAnimation on opacity {
                                    id: trailAnim
                                    running: false
                                    NumberAnimation { to: 0.5; duration: 80; easing.type: Easing.OutQuad }
                                    NumberAnimation { to: 0.0; duration: 350; easing.type: Easing.InOutCubic }
                                }
                            }

                            transform: Scale {
                                id: pillScale
                                origin.x: 12; origin.y: 12
                                xScale: 1.0; yScale: 1.0
                            }
                            SequentialAnimation {
                                id: scaleAnim
                                running: false
                                ParallelAnimation {
                                    NumberAnimation { target: pillScale; property: "xScale"; to: 1.15; duration: 100; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: pillScale; property: "yScale"; to: 0.88; duration: 100; easing.type: Easing.OutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: pillScale; property: "xScale"; to: 0.95; duration: 120; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: pillScale; property: "yScale"; to: 1.05; duration: 120; easing.type: Easing.InOutQuad }
                                }
                                ParallelAnimation {
                                    NumberAnimation { target: pillScale; property: "xScale"; to: 1.0; duration: 180; easing.type: Easing.OutElastic; easing.amplitude: 0.6 }
                                    NumberAnimation { target: pillScale; property: "yScale"; to: 1.0; duration: 180; easing.type: Easing.OutElastic; easing.amplitude: 0.6 }
                                }
                            }
                        }

                        onFocusedIndexChanged: {
                            if (focusedIndex >= 0) {
                                scaleAnim.restart()
                                trailAnim.restart()
                            }
                        }

                        Row {
                            id: workspacesRow
                            spacing: 4

                            Repeater {
                                id: workspacesRepeater
                                model: 10
                                delegate: MouseArea {
                                    id: wsButton
                                    property int wsId: index + 1
                                    property bool isFocused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wsId
                                    property bool isOccupied: Hyprland.workspaces.values.some(function(ws) { return ws.id === wsId; })

                                    visible: isFocused || isOccupied
                                    width: visible ? 24 : 0
                                    height: 24
                                    cursorShape: Qt.PointingHandCursor
                                    z: 1

                                    Behavior on width {
                                        NumberAnimation { duration: 250; easing.type: Easing.InOutCubic }
                                    }

                                    onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + wsId + " })"])

                                    Text {
                                        anchors.centerIn: parent
                                        text: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"][index]
                                        color: wsButton.isFocused ? root.mOnPrimary : (wsButton.isOccupied ? root.mOnSurface : Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.4))
                                        font {
                                            family: "Google Sans Flex"
                                            pixelSize: 13
                                            bold: true
                                        }
                                        Behavior on color {
                                            ColorAnimation { duration: 250; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 3. Battery Status (with Hover details)
                    MouseArea {
                        id: batteryArea
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter
                        hoverEnabled: true
                        width: batteryContentRow.implicitWidth + 8

                        Row {
                            id: batteryContentRow
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: {
                                    if (!UPower.displayDevice) return "";
                                    var pct = Math.round(UPower.displayDevice.percentage * 100);
                                    var icon = "󰁹";
                                    if (pct < 20) icon = "󰁺";
                                    else if (pct < 40) icon = "󰁼";
                                    else if (pct < 60) icon = "󰁾";
                                    else if (pct < 80) icon = "󰂂";
                                    return icon;
                                }
                                color: root.mPrimary
                                font {
                                    family: "JetBrains Mono NF"
                                    pixelSize: 13
                                    bold: true
                                }
                            }

                            Row {
                                id: batteryDetailRow
                                spacing: 4
                                clip: true
                                anchors.verticalCenter: parent.verticalCenter
                                width: batteryArea.containsMouse ? implicitWidth : 0
                                Behavior on width {
                                    NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
                                }

                                Text {
                                    text: {
                                        if (!UPower.displayDevice) return "";
                                        var pct = Math.round(UPower.displayDevice.percentage * 100);
                                        var isCharging = UPower.displayDevice.state === UPowerDeviceState.Charging;
                                        var isPluggedIn = UPower.displayDevice.state === UPowerDeviceState.FullyCharged || UPower.displayDevice.state === UPowerDeviceState.PendingCharge;
                                        
                                        var pctText = pct + "%";
                                        var stateText = "";
                                        if (isCharging) stateText = " 󱐥";
                                        else if (isPluggedIn) stateText = " 󰚥";

                                        var timeText = "";
                                        var seconds = 0;
                                        if (isCharging || isPluggedIn) {
                                            seconds = UPower.displayDevice.timeToFull;
                                            if (seconds > 0) {
                                                var hFull = Math.floor(seconds / 3600);
                                                var mFull = Math.floor((seconds % 3600) / 60);
                                                timeText = " (" + hFull + "h " + mFull + "m to full)";
                                            }
                                        } else {
                                            seconds = UPower.displayDevice.timeToEmpty;
                                            if (seconds > 0) {
                                                var hEmpty = Math.floor(seconds / 3600);
                                                var mEmpty = Math.floor((seconds % 3600) / 60);
                                                timeText = " (" + hEmpty + "h " + mEmpty + "m left)";
                                            }
                                        }

                                        return pctText + stateText + timeText;
                                    }
                                    color: root.mPrimary
                                    font {
                                        family: "JetBrains Mono NF"
                                        pixelSize: 13
                                        bold: true
                                    }
                                }
                            }
                        }
                    }

                    // 4. System Tray (Collapsible Drawer)
                    Row {
                        id: trayContainer
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        // Tray Items Container
                        Row {
                            id: trayIconsRow
                            spacing: 6
                            clip: true
                            anchors.verticalCenter: parent.verticalCenter
                            width: barWindow.trayExpanded ? implicitWidth : 0
                            Behavior on width {
                                NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
                            }

                            Repeater {
                                model: SystemTray.items.values
                                delegate: MouseArea {
                                    id: trayItem
                                    required property var modelData
                                    width: 18
                                    height: 18
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                                    QsMenuAnchor {
                                        id: menuAnchor
                                        menu: trayItem.modelData.menu
                                    }

                                    onPressed: (event) => {
                                        if (event.button === Qt.LeftButton) {
                                            modelData.activate();
                                        } else if (event.button === Qt.RightButton) {
                                            if (trayItem.modelData.hasMenu) {
                                                menuAnchor.open();
                                            } else {
                                                modelData.secondaryActivate();
                                            }
                                        }
                                    }

                                    IconImage {
                                        source: modelData.icon
                                        anchors.fill: parent
                                    }
                                }
                            }
                        }

                        // Toggle Arrow Button
                        MouseArea {
                            width: 16
                            height: 24
                            anchors.verticalCenter: parent.verticalCenter
                            cursorShape: Qt.PointingHandCursor
                            onClicked: barWindow.trayExpanded = !barWindow.trayExpanded
                            visible: SystemTray.items.values.length > 0

                            Text {
                                anchors.centerIn: parent
                                text: barWindow.trayExpanded ? "󰅁" : "󰅂"
                                color: root.mPrimary
                                font {
                                    family: "JetBrains Mono NF"
                                    pixelSize: 13
                                    bold: true
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ───────────────────────────────────────────────────────
    // POPUP WINDOW — separate surface with exclusive keyboard
    // This maps fresh each time, guaranteeing keyboard focus
    // ───────────────────────────────────────────────────────
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: popupWindow
            required property var modelData
            screen: modelData

            visible: root.popupActive

            WlrLayershell.namespace: "quickshell:popup"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            mask: Region {
                item: popupPill
            }

            // Pill-shaped popup that morphs from bar size
            Rectangle {
                id: popupPill
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6

                property real targetWidth: root.launcherMode ? 600 : (root.wallpaperMode ? 800 : (root.sessionMode ? 440 : (root.controlCenterMode ? 400 : root.currentBarWidth)))
                property real targetHeight: root.launcherMode ? 450 : (root.wallpaperMode ? 400 : (root.sessionMode ? 108 : (root.controlCenterMode ? (root.ccPage === 0 ? 232 : 360) : 32)))
                property real targetRadius: (root.launcherMode || root.wallpaperMode || root.sessionMode || root.controlCenterMode) ? 24 : 16

                width: targetWidth
                height: targetHeight
                radius: targetRadius
                color: Qt.rgba(root.mSurface.r, root.mSurface.g, root.mSurface.b, 0.88)
                border.width: 1
                border.color: Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.2)
                clip: true

                Behavior on width {
                    NumberAnimation { duration: 400; easing.type: Easing.OutQuart }
                }
                Behavior on height {
                    NumberAnimation { duration: 400; easing.type: Easing.OutQuart }
                }
                Behavior on radius {
                    NumberAnimation { duration: 400; easing.type: Easing.OutQuart }
                }

                // Focus scope to receive keyboard events
                FocusScope {
                    id: popupFocusScope
                    anchors.fill: parent
                    focus: true

                    Timer {
                        id: localFocusTimer
                        interval: 100
                        repeat: false
                        onTriggered: {
                            if (root.launcherMode) {
                                searchInput.forceActiveFocus()
                            } else if (root.wallpaperMode || root.sessionMode || root.controlCenterMode) {
                                popupFocusScope.forceActiveFocus()
                            }
                        }
                    }

                    Connections {
                        target: root
                        function onLauncherModeChanged() {
                            if (root.launcherMode) localFocusTimer.restart()
                        }
                        function onWallpaperModeChanged() {
                            if (root.wallpaperMode) localFocusTimer.restart()
                        }
                        function onSessionModeChanged() {
                            if (root.sessionMode) localFocusTimer.restart()
                        }
                        function onControlCenterModeChanged() {
                            if (root.controlCenterMode) localFocusTimer.restart()
                        }
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            if (root.controlCenterMode && root.selectedWifiSsid !== "") {
                                root.selectedWifiSsid = ""
                                event.accepted = true
                            } else {
                                root.wallpaperMode = false
                                root.launcherMode = false
                                root.sessionMode = false
                                root.controlCenterMode = false
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Left) {
                            if (root.wallpaperMode) {
                                root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                                event.accepted = true
                            } else if (root.sessionMode) {
                                root.sessionSelectedIndex = (root.sessionSelectedIndex - 1 + 5) % 5
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Right) {
                            if (root.wallpaperMode) {
                                root.selectedIndex = Math.min(root.wallpapersList.length - 1, root.selectedIndex + 1)
                                event.accepted = true
                            } else if (root.sessionMode) {
                                root.sessionSelectedIndex = (root.sessionSelectedIndex + 1) % 5
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Up) {
                            if (root.wallpaperMode) {
                                root.selectedIndex = Math.max(0, root.selectedIndex - 4)
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Down) {
                            if (root.wallpaperMode) {
                                root.selectedIndex = Math.min(root.wallpapersList.length - 1, root.selectedIndex + 4)
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.wallpaperMode && root.wallpapersList.length > 0) {
                                root.applyWallpaper(root.wallpapersList[root.selectedIndex])
                                event.accepted = true
                            } else if (root.sessionMode) {
                                root.triggerSessionAction(root.sessionSelectedIndex)
                                event.accepted = true
                            }
                        }
                    }

                    // ── Wallpaper Selector UI ──
                    Column {
                        id: wallpaperSelectorUI
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16
                        opacity: root.wallpaperMode ? 1.0 : 0.0
                        visible: root.wallpaperMode

                        Behavior on opacity {
                            NumberAnimation { duration: 250 }
                        }

                        // Header Row
                        Item {
                            width: parent.width
                            height: 24

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Select Wallpaper"
                                color: root.mOnSurface
                                font {
                                    family: "Google Sans Flex"
                                    pixelSize: 16
                                    bold: true
                                }
                            }

                            MouseArea {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.wallpaperMode = false

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: root.mPrimary
                                    font {
                                        family: "JetBrains Mono NF"
                                        pixelSize: 18
                                    }
                                }
                            }
                        }

                        // List of Wallpapers
                        GridView {
                            id: wallGridView
                            width: parent.width
                            height: 320
                            cellWidth: 192
                            cellHeight: 160
                            clip: true
                            model: root.wallpapersList

                            Connections {
                                target: root
                                function onSelectedIndexChanged() {
                                    wallGridView.positionViewAtIndex(root.selectedIndex, GridView.Contain)
                                }
                            }

                            delegate: Rectangle {
                                width: 176
                                height: 144
                                x: 8
                                y: 8
                                radius: 12
                                clip: true
                                color: Qt.rgba(root.mSurface.r, root.mSurface.g, root.mSurface.b, 0.5)
                                border.width: index === root.selectedIndex ? 4 : (root.currentWallpaperPath === modelData ? 2 : 1)
                                border.color: index === root.selectedIndex ? root.mPrimary : (root.currentWallpaperPath === modelData ? root.mSecondary : Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.2))

                                scale: index === root.selectedIndex ? 1.08 : 1.0

                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                Behavior on border.width { NumberAnimation { duration: 150 } }

                                Image {
                                    source: "file://" + modelData
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    opacity: status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: root.applyingPath === modelData ? "black" : "transparent"
                                    opacity: root.applyingPath === modelData ? 0.6 : (index === root.selectedIndex ? 0.1 : 0.0)
                                    radius: 12
                                    Behavior on opacity { NumberAnimation { duration: 200 } }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: root.applyingPath === modelData
                                        text: "Applying…"
                                        color: "white"
                                        font {
                                            family: "Google Sans Flex"
                                            pixelSize: 13
                                            bold: true
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: {
                                        if (containsMouse) {
                                            root.selectedIndex = index
                                        }
                                    }
                                    onClicked: {
                                        root.applyWallpaper(modelData)
                                    }
                                }
                            }
                        }
                    }

                    // ── Session Menu UI ──
                    Column {
                        id: sessionMenuUI
                        anchors.fill: parent
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 6
                        opacity: root.sessionMode ? 1.0 : 0.0
                        visible: root.sessionMode

                        Behavior on opacity {
                            NumberAnimation { duration: 250 }
                        }

                        // Header Row
                        Item {
                            width: parent.width
                            height: 24

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Session Options"
                                color: root.mOnSurface
                                font {
                                    family: "Google Sans Flex"
                                    pixelSize: 15
                                    bold: true
                                }
                            }

                            MouseArea {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sessionMode = false

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: root.mPrimary
                                    font {
                                        family: "JetBrains Mono NF"
                                        pixelSize: 18
                                    }
                                }
                            }
                        }

                        // Buttons Row
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 16

                            Repeater {
                                model: [
                                    { name: "Lock", icon: "󰌾", cmd: "hyprlock" },
                                    { name: "Logout", icon: "󰗽", cmd: "exit" },
                                    { name: "Suspend", icon: "󰤄", cmd: "suspend" },
                                    { name: "Reboot", icon: "󰜉", cmd: "reboot" },
                                    { name: "Poweroff", icon: "󰐥", cmd: "poweroff" }
                                ]

                                delegate: Rectangle {
                                    width: 64
                                    height: 52
                                    radius: 12
                                    color: index === root.sessionSelectedIndex ? Qt.rgba(root.mPrimary.r, root.mPrimary.g, root.mPrimary.b, 0.15) : "transparent"
                                    border.width: 1
                                    border.color: index === root.sessionSelectedIndex ? root.mPrimary : Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.15)

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.icon
                                            color: index === root.sessionSelectedIndex ? root.mPrimary : root.mOnSurface
                                            font {
                                                family: "JetBrains Mono NF"
                                                pixelSize: 20
                                            }
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.name
                                            color: index === root.sessionSelectedIndex ? root.mPrimary : Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.7)
                                            font {
                                                family: "Google Sans Flex"
                                                pixelSize: 10
                                                bold: index === root.sessionSelectedIndex
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onContainsMouseChanged: {
                                            if (containsMouse) {
                                                root.sessionSelectedIndex = index
                                            }
                                        }
                                        onClicked: {
                                            root.triggerSessionAction(index)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Control Center UI ──
                    Column {
                        id: controlCenterUI
                        anchors.fill: parent
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        opacity: root.controlCenterMode ? 1.0 : 0.0
                        visible: root.controlCenterMode

                        Behavior on opacity {
                            NumberAnimation { duration: 250 }
                        }

                        // Header Row
                        Item {
                            width: parent.width
                            height: 24
                            visible: root.ccPage === 0

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Control Center"
                                color: root.mOnSurface
                                font {
                                    family: "Google Sans Flex"
                                    pixelSize: 15
                                    bold: true
                                }
                            }

                            MouseArea {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.controlCenterMode = false

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: root.mPrimary
                                    font {
                                        family: "JetBrains Mono NF"
                                        pixelSize: 18
                                    }
                                }
                            }
                        }

                        // PAGE 0: Main Control Center grid (2x2)
                        Grid {
                            width: parent.width
                            columns: 2
                            spacing: 12
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: root.ccPage === 0

                            // 1. Wifi Tile
                            Rectangle {
                                width: (parent.width - 12) / 2
                                height: 80
                                radius: 16
                                color: root.ccWifi ? Qt.rgba(root.mPrimary.r, root.mPrimary.g, root.mPrimary.b, 0.15) : Qt.rgba(root.mSurface.r, root.mSurface.g, root.mSurface.b, 0.3)
                                border.width: 1
                                border.color: root.ccWifi ? root.mPrimary : Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.15)

                                // Card body click: opens subpage
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.ccPage = 1
                                        wifiTab.openTab()
                                    }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 12
                                    width: parent.width - 24

                                    // Icon click: toggles power
                                    Item {
                                        width: 28
                                        height: 28
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.ccWifi ? "󰤨" : "󰤮"
                                            color: root.ccWifi ? root.mPrimary : root.mOnSurface
                                            font { family: "JetBrains Mono NF"; pixelSize: 24 }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: controlCenterProc.run("toggle-wifi")
                                        }
                                    }

                                    Column {
                                        width: parent.width - 40
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            text: "Wi-Fi"
                                            color: root.mOnSurface
                                            font { family: "Google Sans Flex"; pixelSize: 12; bold: true }
                                        }
                                        Text {
                                            text: root.ccWifi ? root.ccWifiSsid : "Off"
                                            color: Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.7)
                                            font { family: "Google Sans Flex"; pixelSize: 10 }
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                    }
                                }
                            }

                            // 2. Bluetooth Tile
                            Rectangle {
                                width: (parent.width - 12) / 2
                                height: 80
                                radius: 16
                                color: root.ccBluetooth ? Qt.rgba(root.mPrimary.r, root.mPrimary.g, root.mPrimary.b, 0.15) : Qt.rgba(root.mSurface.r, root.mSurface.g, root.mSurface.b, 0.3)
                                border.width: 1
                                border.color: root.ccBluetooth ? root.mPrimary : Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.15)

                                // Card body click: opens subpage
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.ccPage = 2
                                        btTab.openTab()
                                    }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 12
                                    width: parent.width - 24

                                    // Icon click: toggles power
                                    Item {
                                        width: 28
                                        height: 28
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.ccBluetooth ? "󰂯" : "󰂲"
                                            color: root.ccBluetooth ? root.mPrimary : root.mOnSurface
                                            font { family: "JetBrains Mono NF"; pixelSize: 24 }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: controlCenterProc.run("toggle-bluetooth")
                                        }
                                    }

                                    Column {
                                        width: parent.width - 40
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            text: "Bluetooth"
                                            color: root.mOnSurface
                                            font { family: "Google Sans Flex"; pixelSize: 12; bold: true }
                                        }
                                        Text {
                                            text: root.ccBluetooth ? "On" : "Off"
                                            color: Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.7)
                                            font { family: "Google Sans Flex"; pixelSize: 10 }
                                        }
                                    }
                                }
                            }

                            // 3. Battery Saver Tile
                            Rectangle {
                                width: (parent.width - 12) / 2
                                height: 80
                                radius: 16
                                property bool isSaver: root.ccProfile === "power-saver"
                                color: isSaver ? Qt.rgba(root.mPrimary.r, root.mPrimary.g, root.mPrimary.b, 0.15) : Qt.rgba(root.mSurface.r, root.mSurface.g, root.mSurface.b, 0.3)
                                border.width: 1
                                border.color: isSaver ? root.mPrimary : Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.15)

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: controlCenterProc.run("toggle-saver")
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 12
                                    width: parent.width - 24

                                    Text {
                                        text: parent.parent.isSaver ? "󰌢" : "󰗑"
                                        color: parent.parent.isSaver ? root.mPrimary : root.mOnSurface
                                        font { family: "JetBrains Mono NF"; pixelSize: 28 }
                                    }

                                    Column {
                                        width: parent.width - 40
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            text: "Battery Saver"
                                            color: root.mOnSurface
                                            font { family: "Google Sans Flex"; pixelSize: 12; bold: true }
                                        }
                                        Text {
                                            text: parent.parent.isSaver ? "On" : "Off"
                                            color: Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.7)
                                            font { family: "Google Sans Flex"; pixelSize: 10 }
                                        }
                                    }
                                }
                            }

                            // 4. Performance Mode / Fan Tile
                            Rectangle {
                                width: (parent.width - 12) / 2
                                height: 80
                                radius: 16
                                property bool isPerf: root.ccProfile === "performance"
                                color: isPerf ? Qt.rgba(root.mPrimary.r, root.mPrimary.g, root.mPrimary.b, 0.15) : Qt.rgba(root.mSurface.r, root.mSurface.g, root.mSurface.b, 0.3)
                                border.width: 1
                                border.color: isPerf ? root.mPrimary : Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.15)

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: controlCenterProc.run("cycle-performance")
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 12
                                    width: parent.width - 24

                                    Text {
                                        text: "󰈐"
                                        color: parent.parent.isPerf ? root.mPrimary : root.mOnSurface
                                        font { family: "JetBrains Mono NF"; pixelSize: 28 }
                                    }

                                    Column {
                                        width: parent.width - 40
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            text: "Fan Profile"
                                            color: root.mOnSurface
                                            font { family: "Google Sans Flex"; pixelSize: 12; bold: true }
                                        }
                                        Text {
                                            text: root.ccProfile ? root.ccProfile.charAt(0).toUpperCase() + root.ccProfile.slice(1) : "Balanced"
                                            color: Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.7)
                                            font { family: "Google Sans Flex"; pixelSize: 10 }
                                        }
                                    }
                                }
                            }
                        }

                        // PAGE 1: WiFi subpage
                        Item {
                            width: parent.width
                            height: 290
                            visible: root.ccPage === 1

                            WifiTab {
                                id: wifiTab
                                anchors.fill: parent
                                mPrimary: root.mPrimary
                                mOnSurface: root.mOnSurface
                                mSurface: root.mSurface
                                onBack: {
                                    root.ccPage = 0
                                    controlCenterProc.run("get")
                                }
                            }
                        }

                        // PAGE 2: Bluetooth subpage
                        Item {
                            width: parent.width
                            height: 290
                            visible: root.ccPage === 2

                            BluetoothTab {
                                id: btTab
                                anchors.fill: parent
                                mPrimary: root.mPrimary
                                mOnSurface: root.mOnSurface
                                mSurface: root.mSurface
                                onBack: {
                                    root.ccPage = 0
                                    controlCenterProc.run("get")
                                }
                            }
                        }
                    }

                    // ── App Launcher UI ──
                    Column {
                        id: appLauncherUI
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16
                        opacity: root.launcherMode ? 1.0 : 0.0
                        visible: root.launcherMode

                        Behavior on opacity {
                            NumberAnimation { duration: 250 }
                        }

                        // Header and Search bar
                        Row {
                            width: parent.width
                            spacing: 12

                            Rectangle {
                                width: parent.width - 36
                                height: 36
                                radius: 18
                                color: Qt.rgba(root.mSurface.r, root.mSurface.g, root.mSurface.b, 0.4)
                                border.width: 1
                                border.color: searchInput.activeFocus ? root.mPrimary : Qt.rgba(root.mOutline.r, root.mOutline.g, root.mOutline.b, 0.3)

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 8

                                    Text {
                                        text: "󰍉"
                                        color: searchInput.activeFocus ? root.mPrimary : root.mOnSurface
                                        font {
                                            family: "JetBrains Mono NF"
                                            pixelSize: 14
                                        }
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    TextInput {
                                        id: searchInput
                                        width: parent.width - 30
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.mOnSurface
                                        font {
                                            family: "Google Sans Flex"
                                            pixelSize: 14
                                        }
                                        focus: root.launcherMode
                                        text: root.launcherSearchQuery
                                        onTextChanged: {
                                            root.launcherSearchQuery = text
                                        }

                                        Keys.onPressed: (event) => {
                                            if (event.key === Qt.Key_Escape) {
                                                root.launcherMode = false
                                                event.accepted = true
                                            } else if (event.key === Qt.Key_Down) {
                                                root.launcherSelectedIndex = Math.min(root.filteredAppsList.length - 1, root.launcherSelectedIndex + 1)
                                                event.accepted = true
                                            } else if (event.key === Qt.Key_Up) {
                                                root.launcherSelectedIndex = Math.max(0, root.launcherSelectedIndex - 1)
                                                event.accepted = true
                                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                if (root.filteredAppsList.length > 0) {
                                                    root.launchApp(root.filteredAppsList[root.launcherSelectedIndex].exec)
                                                }
                                                event.accepted = true
                                            }
                                        }

                                        Connections {
                                            target: root
                                            function onLauncherModeChanged() {
                                                if (root.launcherMode) {
                                                    searchInput.text = ""
                                                    searchInput.forceActiveFocus()
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Close button
                            MouseArea {
                                width: 24
                                height: 36
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.launcherMode = false
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    color: root.mPrimary
                                    font {
                                        family: "JetBrains Mono NF"
                                        pixelSize: 18
                                    }
                                }
                            }
                        }

                        // List View of Apps
                        ListView {
                            id: appListView
                            width: parent.width
                            height: 340
                            spacing: 8
                            clip: true
                            model: root.filteredAppsList

                            Connections {
                                target: root
                                function onLauncherSelectedIndexChanged() {
                                    appListView.positionViewAtIndex(root.launcherSelectedIndex, ListView.Contain)
                                }
                            }

                            delegate: Rectangle {
                                id: appDelegate
                                width: appListView.width
                                height: 48
                                radius: 12
                                color: index === root.launcherSelectedIndex ? Qt.rgba(root.mPrimary.r, root.mPrimary.g, root.mPrimary.b, 0.15) : "transparent"
                                border.width: 1
                                border.color: index === root.launcherSelectedIndex ? root.mPrimary : "transparent"

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                property bool isPinned: modelData.pinned

                                MouseArea {
                                    id: delegateMouseArea
                                    anchors.left: parent.left
                                    anchors.right: pinButton.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: {
                                        if (containsMouse) {
                                            root.launcherSelectedIndex = index
                                        }
                                    }
                                    onClicked: {
                                        root.launchApp(modelData.exec)
                                    }
                                }

                                Row {
                                    id: appInfoRow
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.right: pinButton.left
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 12

                                    IconImage {
                                        source: modelData.icon ? (modelData.icon.startsWith("/") ? "file://" + modelData.icon : Quickshell.iconPath(modelData.icon)) : Quickshell.iconPath("application-x-executable")
                                        width: 24
                                        height: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: modelData.name
                                        color: index === root.launcherSelectedIndex ? root.mPrimary : root.mOnSurface
                                        font {
                                            family: "Google Sans Flex"
                                            pixelSize: 14
                                            bold: index === root.launcherSelectedIndex
                                        }
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        width: parent.width - 36
                                    }
                                }

                                MouseArea {
                                    id: pinButton
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32
                                    height: 32
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    z: 2

                                    onContainsMouseChanged: {
                                        if (containsMouse) {
                                            root.launcherSelectedIndex = index
                                        }
                                    }

                                    onClicked: {
                                        var currentPinned = root.pinnedAppsList.slice()
                                        var idx = currentPinned.indexOf(modelData.name)
                                        if (idx !== -1) {
                                            currentPinned.splice(idx, 1)
                                        } else {
                                            currentPinned.push(modelData.name)
                                        }
                                        root.savePinnedApps(currentPinned)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: appDelegate.isPinned ? "󰐃" : "󰐁"
                                        color: appDelegate.isPinned ? root.mPrimary : (pinButton.containsMouse ? root.mPrimary : Qt.rgba(root.mOnSurface.r, root.mOnSurface.g, root.mOnSurface.b, 0.4))
                                        font {
                                            family: "JetBrains Mono NF"
                                            pixelSize: 18
                                        }
                                        visible: appDelegate.isPinned || delegateMouseArea.containsMouse || pinButton.containsMouse
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
