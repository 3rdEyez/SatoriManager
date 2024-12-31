import QtQuick 6.2
import QtQuick.Controls 6.2
import QtQuick.Shapes 6.2
import SatoriManager

Rectangle {
    id: rectangle
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
        height: parent.height * 0.1
        color: "#a78bfa"
        radius: 10
        anchors.top: parent.top

        Text {
            anchors.centerIn: parent
            text: qsTr("控制面板")
            color: "white"
            font.pixelSize: header.height * 0.4
            font.bold: true
        }
    }

    Column {
        id: mainLayout
        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.leftMargin: parent.width * 0.05
        anchors.topMargin: parent.height * 0.02
        spacing: parent.height * 0.02
        width: parent.width - 2 * anchors.leftMargin
        height: parent.height - header.height - parent.height * 0.15

        Row {
            id: row
            width: parent.width
            height: parent.height * 0.5
            spacing: parent.width * 0.02

            property int buttonFontSize: parent.height * 0.04

            Column {
                id: modeColumn
                width: (parent.width - parent.spacing) * 0.5
                height: parent.height
                spacing: parent.height * 0.04

                StyledButton {
                    id: button_auto
                    text: qsTr("自动模式")
                    font.pixelSize: row.buttonFontSize
                    width: parent.width * 0.8
                    height: (parent.height - 4 * parent.spacing) / 4
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
                id: actionColumn
                width: modeColumn.width
                height: parent.height
                spacing: parent.height * 0.02

                Repeater {
                    model: MobileClient.getPresetActionNames()
                    StyledButton {
                        text: modelData
                        width: parent.width * 0.8
                        height: (parent.height - 4 * parent.spacing) / 4
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
        width: parent.width * 0.4
        height: parent.height * 0.08
        opacity: 1
        anchors.bottom: joystickBackground.top
        anchors.bottomMargin: parent.height * 0.02
        anchors.horizontalCenter: joystickBackground.horizontalCenter
        normalColor: "#10b981"
    }

    DelayButton {
        id: button_disconnect
        text: qsTr("断开")
        font.pixelSize: row.buttonFontSize
        x: button_connect.x
        y: button_connect.y
        width: button_connect.width
        height: button_connect.height
        z: -1
        background: Rectangle { color: "#ef4444"; radius: 8 }
    }

    Rectangle {
        id: joystickBackground
        width: parent.width * 0.5
        height: width
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.1
        anchors.horizontalCenter: parent.horizontalCenter
        color: "#F17EB7"
        radius: width / 2
        clip: false

        Joystick {
            id: control
            width: parent.width
            height: parent.height
            anchors.centerIn: parent
        }
    }
}
