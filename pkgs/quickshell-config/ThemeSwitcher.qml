import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: rootWindow

    property bool show: false
    property var shellRoot
    property real animHeight: animRect.height

    WlrLayershell.keyboardFocus: show ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    visible: show || animRect.opacity > 0

    Item {
        anchors.fill: parent
        focus: show
        Keys.onEscapePressed: show = false

        MouseArea {
            anchors.fill: parent
            enabled: show
            onClicked: show = false
        }

        Rectangle {
            id: animRect
            anchors.top: parent.top
            anchors.topMargin: show ? 16 : (shellRoot && shellRoot.isBarMode ? 0 : 4)
            anchors.horizontalCenter: parent.horizontalCenter

            width: show ? 320 : (shellRoot ? shellRoot.notchWidth + 32 : 120)
            height: show ? 120 : 32

            color: Qt.rgba(0.08, 0.08, 0.08, 0.95)
            radius: show ? 24 : (shellRoot && shellRoot.isBarMode ? 0 : 16)
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: show ? 1 : 0

            opacity: (!show && height <= 36) ? 0.0 : 1.0

            Behavior on radius { NumberAnimation { duration: (shellRoot && shellRoot.batteryMode) ? 0 : show ? 450 : 300; easing.type: show ? Easing.OutBack : Easing.OutExpo; easing.overshoot: show ? 1.2 : 0 } }
            Behavior on width { NumberAnimation { duration: (shellRoot && shellRoot.batteryMode) ? 0 : show ? 450 : 300; easing.type: show ? Easing.OutBack : Easing.OutExpo; easing.overshoot: show ? 1.2 : 0 } }
            Behavior on height { NumberAnimation { duration: (shellRoot && shellRoot.batteryMode) ? 0 : show ? 450 : 300; easing.type: show ? Easing.OutBack : Easing.OutExpo; easing.overshoot: show ? 1.2 : 0 } }
            Behavior on anchors.topMargin { NumberAnimation { duration: (shellRoot && shellRoot.batteryMode) ? 0 : show ? 450 : 300; easing.type: show ? Easing.OutBack : Easing.OutExpo; easing.overshoot: show ? 1.2 : 0 } }

            Item {
                anchors.fill: parent
                anchors.margins: 16
                opacity: show ? 1.0 : 0.0
                clip: true
                Behavior on opacity { NumberAnimation { duration: (shellRoot && shellRoot.batteryMode) ? 0 : show ? 300 : 100; easing.type: Easing.InOutQuad } }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    Text {
                        text: "Theme switching is disabled"
                        color: shellRoot ? shellRoot.colFg : "white"
                        font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                        font.pixelSize: 14
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Single-theme mode: monochrome"
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font.family: shellRoot ? shellRoot.fontFamily : "sans-serif"
                        font.pixelSize: 12
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }
}
