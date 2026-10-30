pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

// Single source of truth shared across every surface (bar pill, Control Center
// tile, Control Center detail). DMS instantiates the plugin component once per
// surface, so state and the CLI reads/writes must live here or the surfaces
// disagree and each polls independently.
//
// Easy Effects is the source of truth. This service only reads its state and
// reflects it; it never launches a windowed instance and persists nothing of
// its own. Startup is left to the user's easyeffects service.
//
// Passive reads avoid the Easy Effects CLI entirely (the preset list is read
// from disk), because every CLI flag except `-s` hides an open Easy Effects
// window as a side effect. Active presets use the window-safe `-s`; bypass
// state (`-b 3`, which does hide the window) is only read on startup / explicit
// refresh, never when just opening a surface.
Singleton {
    id: root

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

    // Short status line shared by the bar pill and the Control Center tile.
    property string statusLine: {
        if (!detected)
            return ""
        if (!eeRunning)
            return "Not running"
        if (bypassed)
            return "Bypassed"
        var s = currentOutputProfile
        if (currentInputProfile !== "None")
            s += " / " + currentInputProfile
        return s
    }

    property string listBuffer: ""
    property string pendingPreset: ""
    property bool pendingFull: false

    // Not-running poll interval. Starts fast so a just-started service shows up
    // quickly, then backs off to pollMaxInterval so an idle widget costs almost
    // nothing. Any explicit refresh resets it.
    readonly property int pollMinInterval: 3000
    readonly property int pollMaxInterval: 60000
    property int pollInterval: pollMinInterval

    Component.onCompleted: refresh(true)

    // refresh(full): always re-read the preset list from disk and the running
    // state. When running, also read active presets (window-safe). Only a
    // "full" refresh additionally reads bypass state (which hides an open
    // window), so a surface opening passes full=false.
    function refresh(full) {
        root.pendingFull = (full === true)
        root.pollInterval = root.pollMinInterval
        root.listBuffer = ""
        listProc.running = true
        runningCheck.running = true
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

    function startService() {
        Quickshell.execDetached(["systemctl", "--user", "start", "easyeffects.service"])
        serviceDetectTimer.start()
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

    Process {
        id: runningCheck
        command: ["pidof", "easyeffects"]
        running: false
        onExited: (exitCode, exitStatus) => {
            root.eeRunning = (exitCode === 0)
            root.detected = true
            if (root.eeRunning) {
                pollTimer.stop()
                root.pollInterval = root.pollMinInterval
                // `-s` is the only read that does not hide an open window.
                activeProc.running = true
                if (root.pendingFull) {
                    bypassReadProc.running = true
                }
            } else {
                root.activeOutput = ""
                root.activeInput = ""
                pollTimer.restart()
            }
        }
    }

    // While Easy Effects isn't running, keep re-detecting until it appears,
    // backing off each time. Only `pidof` runs here (the preset list is re-read
    // on explicit refreshes). Never query, never launch.
    Timer {
        id: pollTimer
        interval: root.pollInterval
        repeat: false
        onTriggered: {
            root.pollInterval = Math.min(root.pollInterval * 2, root.pollMaxInterval)
            root.pendingFull = false
            runningCheck.running = true
        }
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
    // refresh (startup / refresh button), not when opening a surface.
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

    Timer {
        id: serviceTimer
        interval: 1500
        repeat: false
        onTriggered: {
            root.eeRunning = true
            root.doLoad()
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
            root.refresh(false)
        }
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

    Timer {
        id: serviceDetectTimer
        interval: 1500
        repeat: false
        onTriggered: root.refresh(true)
    }
}
