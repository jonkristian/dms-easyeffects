import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var outputProfiles: []
    property var inputProfiles: []
    property int currentOutputIndex: pluginData.currentOutputIndex || -1
    property int currentInputIndex: pluginData.currentInputIndex || -1
    property string currentOutputProfile: currentOutputIndex >= 0 && currentOutputIndex < outputProfiles.length ? outputProfiles[currentOutputIndex] : "None"
    property string currentInputProfile: currentInputIndex >= 0 && currentInputIndex < inputProfiles.length ? inputProfiles[currentInputIndex] : "None"
    property bool profilesLoaded: false
    property var profileLines: []

    Component.onCompleted: {
        // Load profiles dynamically
        loadProfiles.running = true
    }

    function syncActiveProfile() {
        // Reset before checking
        root.activeOutputProfile = ""
        root.activeInputProfile = ""
        checkActiveOutput.running = true
    }

    property string activeOutputProfile: ""
    property string activeInputProfile: ""

    Process {
        id: checkActiveOutput
        command: ["easyeffects", "-a", "output"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim() !== '') {
                    root.activeOutputProfile = data.trim()
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            // Now check input
            checkActiveInput.running = true
        }
    }

    Process {
        id: checkActiveInput
        command: ["easyeffects", "-a", "input"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim() !== '') {
                    root.activeInputProfile = data.trim()
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            // Find output profile index
            var outputIdx = -1
            for (var i = 0; i < root.outputProfiles.length; i++) {
                if (root.outputProfiles[i] === root.activeOutputProfile) {
                    outputIdx = i
                    break
                }
            }
            // If empty, set to None (-1)
            if (root.activeOutputProfile === "") {
                outputIdx = -1
            }

            // Find input profile index
            var inputIdx = -1
            for (var j = 0; j < root.inputProfiles.length; j++) {
                if (root.inputProfiles[j] === root.activeInputProfile) {
                    inputIdx = j
                    break
                }
            }
            // If empty, set to None (-1)
            if (root.activeInputProfile === "") {
                inputIdx = -1
            }

            root.currentOutputIndex = outputIdx
            root.currentInputIndex = inputIdx
            pluginService.savePluginData(pluginId, "currentOutputIndex", outputIdx)
            pluginService.savePluginData(pluginId, "currentInputIndex", inputIdx)
        }
    }

    Process {
        id: loadProfiles
        command: ["easyeffects", "-p"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                if (data && data.trim() !== '') {
                    root.profileLines.push(data.trim())
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            var outputProfiles = []
            var inputProfiles = []

            // Parse output: "Output Presets: profile1,profile2,"
            //               "Input Presets: profile3,profile4,"
            for (var i = 0; i < root.profileLines.length; i++) {
                var line = root.profileLines[i]
                if (line.startsWith("Output Presets:")) {
                    var outputStr = line.substring("Output Presets:".length).trim()
                    if (outputStr) {
                        outputProfiles = outputStr.split(',').map(s => s.trim()).filter(s => s !== '')
                    }
                } else if (line.startsWith("Input Presets:")) {
                    var inputStr = line.substring("Input Presets:".length).trim()
                    if (inputStr) {
                        inputProfiles = inputStr.split(',').map(s => s.trim()).filter(s => s !== '')
                    }
                }
            }

            root.outputProfiles = outputProfiles
            root.inputProfiles = inputProfiles
            root.profilesLoaded = true

            // Reset for next time
            root.profileLines = []

            // Check what's actually active in Easy Effects
            syncActiveProfile()
        }
    }

    Process {
        id: checkInstalled
        command: ["sh", "-c", "command -v easyeffects"]
        running: false

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // Easy Effects is installed, check if running
                checkRunning.running = true
            } else {
                // Not installed
                console.error("Easy Effects is not installed")
                ToastService.showError("Easy Effects", "Easy Effects is not installed. Please install it first.")
            }
        }
    }

    Process {
        id: checkRunning
        command: ["pgrep", "-x", "easyeffects"]
        running: false

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // Easy Effects is running, switch profile
                switchProfileCommand.running = true
            } else {
                // Easy Effects not running, start it first
                console.warn("Easy Effects not running, starting service...")
                startProcess.running = true
            }
        }
    }

    Process {
        id: startProcess
        command: ["easyeffects", "--gapplication-service"]
        running: false

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // Give it a moment to start, then switch profile
                switchTimer.start()
            } else {
                console.error("Failed to start Easy Effects")
                ToastService.showError("Easy Effects", "Failed to start Easy Effects. Is it installed?")
            }
        }
    }

    Timer {
        id: switchTimer
        interval: 500
        repeat: false
        onTriggered: switchProfileCommand.running = true
    }

    Process {
        id: switchProfileCommand
        command: ["sh", "-c", ""]
        running: false

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("Easy Effects: Failed to load profile with code", exitCode)
                ToastService.showError("Easy Effects", "Failed to switch profile")
            }
        }
    }

    property int pendingProfileIndex: -1

    function loadOutputProfile(index) {
        root.currentOutputIndex = index
        pluginService.savePluginData(pluginId, "currentOutputIndex", index)

        var profileName = root.outputProfiles[index]
        switchProfileCommand.command = ["sh", "-c", "easyeffects -l \"" + profileName + "\""]
        checkInstalled.running = true
    }

    function loadInputProfile(index) {
        root.currentInputIndex = index
        pluginService.savePluginData(pluginId, "currentInputIndex", index)

        var profileName = root.inputProfiles[index]
        switchProfileCommand.command = ["sh", "-c", "easyeffects -l \"" + profileName + "\""]
        checkInstalled.running = true
    }

    function resetAllProfiles() {
        root.currentOutputIndex = -1
        root.currentInputIndex = -1
        pluginService.savePluginData(pluginId, "currentOutputIndex", -1)
        pluginService.savePluginData(pluginId, "currentInputIndex", -1)

        switchProfileCommand.command = ["sh", "-c", "easyeffects -r"]
        checkInstalled.running = true
    }

    horizontalBarPill: Component {
        Row {
            spacing: 8

            DankIcon {
                name: "graphic_eq"
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.currentOutputProfile + (root.currentInputProfile !== "None" ? " / " + root.currentInputProfile : "")
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 4

            DankIcon {
                name: "graphic_eq"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.currentOutputProfile
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
                // Sync with active profile when popout opens
                root.syncActiveProfile()
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
                        width: parent.width - resetButton.width - refreshButton.width - Theme.spacingS * 2
                    }

                    StyledRect {
                        id: resetButton
                        width: resetText.width + Theme.spacingS * 2
                        height: 32
                        radius: Theme.cornerRadius
                        color: resetMouseHeader.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: resetText
                            text: "Clear"
                            anchors.centerIn: parent
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        MouseArea {
                            id: resetMouseHeader
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.resetAllProfiles()
                                popout.closePopout()
                            }
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
                            onClicked: {
                                root.profileLines = []
                                loadProfiles.running = true
                            }
                        }
                    }
                }

                Item { height: Theme.spacingXS }

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
                                root.loadOutputProfile(index)
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
                                root.loadInputProfile(index)
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
