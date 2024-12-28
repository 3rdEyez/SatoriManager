/*
This is a UI file (.ui.qml) that is intended to be edited in Qt Design Studio only.
It is supposed to be strictly declarative and only uses a subset of QML. If you edit
this file manually, you might introduce QML code that is not supported by Qt Design Studio.
Check out https://doc.qt.io/qtcreator/creator-quick-ui-forms.html for details on .ui.qml files.
*/
import QtQuick 6.2
import QtQuick.Controls 6.2
import QtQuick.Shapes 6.2
import SatoriManager

Rectangle {
    id: rectangle
    width: 640
    height: 480
    color: "#f3f4f6"
    radius: 10
    border.color: "#d1d5db"
    border.width: 1

    property alias button_Manual: button_Manual
    property alias control: control
    property alias button_connect: button_connect
    property alias button_facialRecognition: button_facialRecognition
    property alias button_sleep: button_sleep
    property alias button_auto: button_auto
    property alias button_disconnect: button_disconnect

    Rectangle {
        id: header
        width: parent.width
        height: 50
        color: "#a78bfa"
        radius: 10
        anchors.top: parent.top
        Text {
            anchors.centerIn: parent
            text: qsTr("控制面板")
            color: "white"
            font.pixelSize: 24
            font.bold: true
        }
    }

    Column {
        id: mainLayout
        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.leftMargin: 20
        anchors.topMargin: 10
        spacing: 15
        width: parent.width - 2 * anchors.leftMargin
        height: parent.height - header.height - 80

        Row {
            id: row
            width: parent.width
            height: parent.height * 0.5
            spacing: 15

            property int buttonFontSize: 18

            Column {
                // 用来放切换模式的按钮
                id: modeColumn
                width: (parent.width - parent.spacing) * 0.5
                height: parent.height
                spacing: 10

                StyledButton {
                    id: button_auto
                    text: qsTr("自动模式")
                    font.pixelSize: row.buttonFontSize
                    width: parent.width * 0.8
                    height:(parent.height - 4 * parent.spacing )/4
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledButton {
                    id: button_sleep
                    text: qsTr("睡眠模式")
                    font.pixelSize: row.buttonFontSize
                    width: button_auto.width
                    height: button_auto.height
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledButton {
                    id: button_facialRecognition
                    text: qsTr("人脸识别")
                    font.pixelSize: row.buttonFontSize
                    width: button_auto.width
                    height: button_auto.height
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledButton {
                    id: button_Manual
                    text: qsTr("手动模式")
                    font.pixelSize: row.buttonFontSize
                    width: button_auto.width
                    height: button_auto.height
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Column {
                // 用于播放预设动作的按钮
                id: actionColumn
                width: modeColumn.width
                height: parent.height
                spacing: 10

                Repeater {
                    model: MobileClient.getPresetActionNames()
                    StyledButton {
                        text: modelData
                        width: parent.width * 0.8
                        height:(parent.height - 4 * parent.spacing )/4
                        font.pixelSize: row.buttonFontSize
                        onClicked: MobileClient.executePresetAction(modelData)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }

    StyledButton {
        id: button_connect
        text: qsTr("连接")
        font.pixelSize: row.buttonFontSize
        width: 120
        height: 40
        opacity: 1
        anchors.bottom: joystickBackground.top
        anchors.bottomMargin: 10
        anchors.horizontalCenter: joystickBackground.horizontalCenter
        normalColor: "#10b981" // 绿色
    }

    DelayButton {
        id: button_disconnect
        text: qsTr("断开")
        font.pixelSize: row.buttonFontSize
        x: button_connect.x
        y: button_connect.y
        width: 120
        height: 40
        z: -1
        background: Rectangle { color: "#ef4444"; radius: 8 } // 红色
    }

    Rectangle {
        id: joystickBackground
        width: parent.width * 0.5
        height: width
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80
        anchors.horizontalCenter: parent.horizontalCenter
        color: "#F17EB7"
        radius: width / 2

        Joystick {
            id: control
            width: parent.width
            height: parent.height
            anchors.centerIn: parent
        }
    }
}
