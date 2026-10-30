import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

// UI only. All state and CLI I/O live in the EasyEffectsState singleton so the
// bar pill, Control Center tile and Control Center detail (which DMS renders as
// separate instances) share one source of truth and one poller.
PluginComponent {
    id: root

    // --- Reusable inline UI pieces ---
    // Kept in this one file on purpose: only the manifest's `component` file is
    // cache-busted on `dms ipc plugins reload`, so extra widget files wouldn't
    // hot-reload reliably. Inline components stay reloadable and uncluttered.
    // (EasyEffectsState is exempt: it's a singleton, created once and reused.)

    // A full-width action button: icon + label, hover highlight, click handler.
    component ActionButton: StyledRect {
        id: actionButton
        required property string icon
        required property string label
        signal clicked

        width: parent.width
        height: 32
        radius: Theme.cornerRadius
        color: actionMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DIcon {
                name: actionButton.icon
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: actionButton.label
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: actionButton.clicked()
        }
    }

    // Header: section title plus the bypass and refresh icon buttons.
    component PanelHeader: Row {
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
            visible: EasyEffectsState.eeRunning
            color: bypassMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            DIcon {
                name: "power_settings_new"
                anchors.centerIn: parent
                color: EasyEffectsState.bypassed ? Theme.surfaceVariantText : Theme.primary
            }

            MouseArea {
                id: bypassMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: EasyEffectsState.toggleBypass()
            }
        }

        StyledRect {
            id: refreshButton
            width: 32
            height: 32
            radius: Theme.cornerRadius
            color: refreshMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            DIcon {
                name: "refresh"
                anchors.centerIn: parent
                color: Theme.surfaceText
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: EasyEffectsState.refresh(true)
            }
        }
    }

    // A titled list of selectable presets (used for both output and input).
    component ProfileList: Column {
        id: list
        required property string title
        required property var profiles
        required property int activeIndex
        signal selected(string name)

        width: parent.width
        spacing: Theme.spacingS
        visible: list.profiles.length > 0

        StyledText {
            text: list.title
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceVariantText
        }

        Repeater {
            model: list.profiles.length

            StyledRect {
                width: parent.width
                height: 32
                radius: Theme.cornerRadius
                color: {
                    if (list.activeIndex === index) {
                        return Theme.primaryContainer
                    } else if (rowMouse.containsMouse) {
                        return Theme.surfaceContainerHighest
                    } else {
                        return Theme.surfaceContainerHigh
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    DIcon {
                        name: list.activeIndex === index ? "check_circle" : "radio_button_unchecked"
                        color: list.activeIndex === index ? Theme.primary : Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: list.profiles[index] || "Unknown"
                        color: Theme.surfaceText
                        font.weight: list.activeIndex === index ? Font.Medium : Font.Normal
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: list.selected(list.profiles[index])
                }
            }
        }
    }

    // Shared body for both the bar popout and the Control Center detail panel.
    // `requestClose()` lets the host (popout or control center) close after an action.
    component ProfilePanel: Column {
        id: panel
        signal requestClose

        spacing: Theme.spacingS
        topPadding: Theme.spacingS
        bottomPadding: Theme.spacingS

        // Window-safe refresh whenever the panel is shown (no bypass read), so
        // an open Easy Effects window isn't hidden just by opening the panel.
        Component.onCompleted: EasyEffectsState.refresh(false)

        PanelHeader {}

        Item { height: Theme.spacingXS }

        // Not-running state: detect, don't launch.
        Column {
            width: parent.width
            spacing: Theme.spacingM
            visible: EasyEffectsState.detected && !EasyEffectsState.eeRunning

            StyledText {
                width: parent.width
                text: "Easy Effects is not running."
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
                wrapMode: Text.WordWrap
            }

            ActionButton {
                icon: "play_arrow"
                label: "Start Easy Effects service"
                onClicked: EasyEffectsState.startService()
            }
        }

        ProfileList {
            title: "Output"
            profiles: EasyEffectsState.outputProfiles
            activeIndex: EasyEffectsState.currentOutputIndex
            onSelected: name => {
                EasyEffectsState.loadProfile(name)
                panel.requestClose()
            }
        }

        Item { height: Theme.spacingM; visible: EasyEffectsState.inputProfiles.length > 0 }

        ProfileList {
            title: "Input"
            profiles: EasyEffectsState.inputProfiles
            activeIndex: EasyEffectsState.currentInputIndex
            onSelected: name => {
                EasyEffectsState.loadProfile(name)
                panel.requestClose()
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.surfaceVariantText
            opacity: 0.2
        }

        ActionButton {
            icon: "open_in_new"
            label: "Open Easy Effects"
            onClicked: {
                Quickshell.execDetached(["easyeffects"])
                panel.requestClose()
            }
        }
    }

    // --- Bar pills ---

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DIcon {
                name: "graphic_eq"
                opacity: EasyEffectsState.bypassed ? 0.5 : 1.0
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: EasyEffectsState.statusLine
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DIcon {
                name: "graphic_eq"
                opacity: EasyEffectsState.bypassed ? 0.5 : 1.0
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: EasyEffectsState.bypassed ? "Off" : EasyEffectsState.currentOutputProfile
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // --- Bar popout ---

    popoutContent: Component {
        PopoutComponent {
            id: popout
            showCloseButton: true

            ProfilePanel {
                width: parent.width - Theme.spacingM
                anchors.horizontalCenter: parent.horizontalCenter
                onRequestClose: popout.closePopout()
            }
        }
    }

    popoutWidth: 260

    // --- Control Center surface ---
    // The plugin appears in the Control Center widget picker because ccWidgetIcon
    // is set. Clicking the tile toggles bypass; expanding it shows the profile
    // list (the same ProfilePanel as the bar popout).
    ccWidgetIcon: "graphic_eq"
    ccWidgetPrimaryText: "Audio Effects"
    ccWidgetSecondaryText: EasyEffectsState.statusLine
    ccWidgetIsActive: EasyEffectsState.eeRunning && !EasyEffectsState.bypassed

    onCcWidgetToggled: EasyEffectsState.toggleBypass()

    ccDetailContent: Component {
        Rectangle {
            width: parent.width
            height: parent.height
            radius: Theme.cornerRadius
            color: Theme.nestedSurface
            border.color: Theme.outlineMedium
            border.width: Theme.layerOutlineWidth
            clip: true

            ProfilePanel {
                id: detailPanel
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacingM
                onRequestClose: PopoutService.closeControlCenter()
            }

            // Size the detail page from the panel's real height instead of a
            // hand-maintained estimate. The host reads ccDetailHeight reactively.
            Binding {
                target: root
                property: "ccDetailHeight"
                value: Math.min(detailPanel.implicitHeight + Theme.spacingM * 2, 600)
            }
        }
    }
}
