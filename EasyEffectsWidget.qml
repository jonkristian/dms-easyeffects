import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // Easy Effects is the source of truth. This plugin only reads its state
    // and reflects it; it never launches a windowed instance and persists
    // nothing of its own. Startup is left to the user's easyeffects service.
    //
    // Passive reads avoid the Easy Effects CLI entirely (the preset list is
    // read from disk), because every CLI flag except `-s` hides an open
    // Easy Effects window as a side effect. Active presets use the window-safe
    // `-s`; bypass state (`-b 3`, which does hide the window) is only read on
    // startup / explicit refresh, never when just opening the popout.
    property var outputProfiles: []
    property var inputProfiles: []
    property string activeOutput: ""
    property string activeInput: ""
    property bool bypassed: false
    property bool eeRunning: false
    property bool detected: false

    property int currentOutputIndex: outputProfiles.indexOf(activeOutput)
    property int currentInputIndex: inputProfiles.indexOf(activeInput)
    property string currentOutputProfile: activeOutput !== "" ? activeOutput : "None"
    property string currentInputProfile: activeInput !== "" ? activeInput : "None"

    property string listBuffer: ""
    property string pendingPreset: ""
    property bool pendingFull: false

    Component.onCompleted: refresh(true)

    // refresh(full): always re-read the preset list from disk and the running
    // state. When running, also read active presets (window-safe). Only a
    // "full" refresh additionally reads bypass state (which hides an open
    // window), so the popout's open refresh passes full=false.
    function refresh(full) {
        root.pendingFull = (full === true)
        root.listBuffer = ""
        listProc.running = true
        runningCheck.running = true
    }

    // Preset list straight from disk -> no Easy Effects invocation, no window
    // side effect, works even when Easy Effects isn't running.
    Process {
        id: listProc
        command: ["sh", "-c", "base=\"${XDG_DATA_HOME:-$HOME/.local/share}/easyeffects\"; for d in output input; do echo \"@@$d@@\"; ls -1 \"$base/$d\" 2>/dev/null; done"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                root.listBuffer += data + "\n"
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.parseList(root.listBuffer)
            root.listBuffer = ""
        }
    }

    function parseList(buffer) {
        var outputs = []
        var inputs = []
        var section = ""
        var lines = buffer.split("\n")

        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].trim()
            if (t === "@@output@@") {
                section = "output"
            } else if (t === "@@input@@") {
                section = "input"
            } else if (t !== "" && /\.json$/.test(t)) {
                // Strip ".json"; ignore other files (e.g. exported ParametricEq .txt).
                var name = t.substring(0, t.length - 5)
                if (section === "output") {
                    outputs.push(name)
                } else if (section === "input") {
                    inputs.push(name)
                }
            }
        }

        root.outputProfiles = outputs
        root.inputProfiles = inputs
    }

    Process {
        id: runningCheck
        command: ["pgrep", "-x", "easyeffects"]
        running: false
        onExited: (exitCode, exitStatus) => {
            root.eeRunning = (exitCode === 0)
            root.detected = true
            if (root.eeRunning) {
                pollTimer.stop()
                // `-s` is the only read that does not hide an open window.
                activeProc.running = true
                if (root.pendingFull) {
                    bypassReadProc.running = true
                }
            } else {
                root.activeOutput = ""
                root.activeInput = ""
                pollTimer.start()
            }
        }
    }

    // While Easy Effects isn't running, keep re-detecting (cheaply, via pgrep)
    // until it appears. Never query, never launch.
    Timer {
        id: pollTimer
        interval: 3000
        repeat: true
        onTriggered: refresh(false)
    }

    // Active presets via the window-safe `-s`. It always prints both an
    // "input:" and "output:" line, so empty values clear the active state.
    Process {
        id: activeProc
        command: ["easyeffects", "-s"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                var t = data.trim()
                var low = t.toLowerCase()
                if (low.indexOf("output:") === 0) {
                    root.activeOutput = t.substring(t.indexOf(":") + 1).trim()
                } else if (low.indexOf("input:") === 0) {
                    root.activeInput = t.substring(t.indexOf(":") + 1).trim()
                }
            }
        }
    }

    // Bypass state. `-b 3` hides an open window, so this only runs on a full
    // refresh (startup / refresh button), not when opening the popout.
    Process {
        id: bypassReadProc
        command: ["easyeffects", "-b", "3"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                var t = data.trim()
                if (t !== "") {
                    // 1 = bypass enabled (effects off), 2 = disabled.
                    root.bypassed = (t === "1")
                }
            }
        }
    }

    // --- Actions (only triggered by explicit user interaction) ---

    function loadProfile(name) {
        root.pendingPreset = name
        if (root.eeRunning) {
            doLoad()
        } else {
            // Don't launch a bare (windowed) instance; bring up the service.
            Quickshell.execDetached(["systemctl", "--user", "start", "easyeffects.service"])
            serviceTimer.start()
        }
    }

    function doLoad() {
        loadProc.command = ["easyeffects", "-l", root.pendingPreset]
        loadProc.running = true
    }

    Timer {
        id: serviceTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.eeRunning = true
            doLoad()
        }
    }

    Process {
        id: loadProc
        command: ["easyeffects", "-l", ""]
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                ToastService.showError("Easy Effects", "Failed to load preset")
            }
            // Re-read active state (window-safe).
            refresh(false)
        }
    }

    function toggleBypass() {
        if (!root.eeRunning) {
            return
        }
        // bypassed -> disable bypass (2, effects on); not bypassed -> enable (1, effects off)
        var target = root.bypassed ? "2" : "1"
        bypassWriteProc.command = ["easyeffects", "-b", target]
        bypassWriteProc.running = true
        root.bypassed = !root.bypassed
    }

    Process {
        id: bypassWriteProc
        command: ["easyeffects", "-b", "3"]
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // Revert optimistic flip on failure.
                root.bypassed = !root.bypassed
                ToastService.showError("Easy Effects", "Failed to toggle bypass")
            }
        }
    }

    function startService() {
        Quickshell.execDetached(["systemctl", "--user", "start", "easyeffects.service"])
        serviceDetectTimer.start()
    }

    Timer {
        id: serviceDetectTimer
        interval: 1500
        repeat: false
        onTriggered: refresh(true)
    }

    horizontalBarPill: Component {
        Row {
            spacing: 8

            DankIcon {
                name: "graphic_eq"
                opacity: root.bypassed ? 0.5 : 1.0
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.bypassed ? "Bypassed" : (root.currentOutputProfile + (root.currentInputProfile !== "None" ? " / " + root.currentInputProfile : ""))
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 4

            DankIcon {
                name: "graphic_eq"
                opacity: root.bypassed ? 0.5 : 1.0
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.bypassed ? "Off" : root.currentOutputProfile
                font.pixelSize: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            showCloseButton: true

            Component.onCompleted: {
                // Window-safe refresh on open (no bypass read), so an open
                // Easy Effects window isn't hidden just by opening the popout.
                root.refresh(false)
            }

            Column {
                width: parent.width - Theme.spacingM
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: Theme.spacingS
                bottomPadding: Theme.spacingS
                spacing: Theme.spacingS

                Row {
                    width: parent.width
                    height: 40
                    spacing: Theme.spacingS

                    StyledText {
                        text: "Audio Profiles"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Normal
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - bypassButton.width - refreshButton.width - Theme.spacingS * 2
                    }

                    // Global bypass toggle (effects on/off). Highlighted when effects are active.
                    StyledRect {
                        id: bypassButton
                        width: 32
                        height: 32
                        radius: Theme.cornerRadius
                        visible: root.eeRunning
                        color: bypassMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            name: "power_settings_new"
                            anchors.centerIn: parent
                            color: root.bypassed ? Theme.surfaceVariantText : Theme.primary
                        }

                        MouseArea {
                            id: bypassMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleBypass()
                        }
                    }

                    StyledRect {
                        id: refreshButton
                        width: 32
                        height: 32
                        radius: Theme.cornerRadius
                        color: refreshMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            name: "refresh"
                            anchors.centerIn: parent
                            color: Theme.surfaceText
                        }

                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh(true)
                        }
                    }
                }

                Item { height: Theme.spacingXS }

                // Not-running state: detect, don't launch.
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.detected && !root.eeRunning

                    StyledText {
                        width: parent.width
                        text: "Easy Effects is not running."
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        wrapMode: Text.WordWrap
                    }

                    StyledRect {
                        width: parent.width
                        height: 32
                        radius: Theme.cornerRadius
                        color: startMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "play_arrow"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: "Start Easy Effects service"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: startMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.startService()
                        }
                    }
                }

                // Output Presets
                StyledText {
                    text: "Output"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                    visible: root.outputProfiles.length > 0
                }

                Repeater {
                    model: root.outputProfiles.length

                    StyledRect {
                        width: parent.width
                        height: 32
                        radius: Theme.cornerRadius
                        color: {
                            if (root.currentOutputIndex === index) {
                                return Theme.primaryContainer
                            } else if (outputMouse.containsMouse) {
                                return Theme.surfaceContainerHighest
                            } else {
                                return Theme.surfaceContainerHigh
                            }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingS

                            DankIcon {
                                name: root.currentOutputIndex === index ? "check_circle" : "radio_button_unchecked"
                                color: root.currentOutputIndex === index ? Theme.primary : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.outputProfiles[index] || "Unknown"
                                color: Theme.surfaceText
                                font.weight: root.currentOutputIndex === index ? Font.Medium : Font.Normal
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: outputMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.loadProfile(root.outputProfiles[index])
                                popout.closePopout()
                            }
                        }
                    }
                }

                Item { height: Theme.spacingM; visible: root.inputProfiles.length > 0 }

                // Input Presets
                StyledText {
                    text: "Input"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                    visible: root.inputProfiles.length > 0
                }

                Repeater {
                    model: root.inputProfiles.length

                    StyledRect {
                        width: parent.width
                        height: 32
                        radius: Theme.cornerRadius
                        color: {
                            if (root.currentInputIndex === index) {
                                return Theme.primaryContainer
                            } else if (inputMouse.containsMouse) {
                                return Theme.surfaceContainerHighest
                            } else {
                                return Theme.surfaceContainerHigh
                            }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingS

                            DankIcon {
                                name: root.currentInputIndex === index ? "check_circle" : "radio_button_unchecked"
                                color: root.currentInputIndex === index ? Theme.primary : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.inputProfiles[index] || "Unknown"
                                color: Theme.surfaceText
                                font.weight: root.currentInputIndex === index ? Font.Medium : Font.Normal
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: inputMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.loadProfile(root.inputProfiles[index])
                                popout.closePopout()
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceVariantText
                    opacity: 0.2
                }

                StyledRect {
                    width: parent.width
                    height: 32
                    radius: Theme.cornerRadius
                    color: openMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "open_in_new"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Open Easy Effects"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: openMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["easyeffects"])
                            popout.closePopout()
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 260
}
