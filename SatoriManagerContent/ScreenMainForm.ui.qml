
/*
This is a UI file (.ui.qml) that is intended to be edited in Qt Design Studio only.
It is supposed to be strictly declarative and only uses a subset of QML. If you edit
this file manually, you might introduce QML code that is not supported by Qt Design Studio.
Check out https://doc.qt.io/qtcreator/creator-quick-ui-forms.html for details on .ui.qml files.
*/
import QtQuick 6.2
import QtQuick.Controls 6.2
import SatoriManager

Rectangle {
    id: rectangle

    property alias button_Manual: button_Manual
    property alias control: control
    property alias button_connect: button_connect
    property alias button_facialRecognition: button_facialRecognition
    property alias button_sleep: button_sleep
    property alias button_auto: button_auto
    property alias button_disconnect: button_disconnect

    Column {
        id: mainLayout
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 10
        anchors.topMargin: 10
        spacing: 20
        width: parent.width - 2 * anchors.leftMargin
        height: parent.height * 3 / 5 - 2 * anchors.topMargin

        Row {
            id: row
            width: parent.width
            height: parent.height * 2 / 3

            property int buttonFontSize: 20
            Column {
                // 用来放切换模式的按钮
                id: column
                width: parent.width / 2
                height: parent.height
                spacing: 10

                Button {
                    id: button_auto
                    width: parent.width * 2 / 3
                    height: parent.height * 1 / 4
                    text: qsTr("自动模式")
                    font.pixelSize: row.buttonFontSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Button {
                    id: button_sleep
                    width: button_auto.width
                    height: button_auto.height
                    text: qsTr("睡眠模式")
                    font.pixelSize: row.buttonFontSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Button {
                    id: button_facialRecognition
                    width: button_auto.width
                    height: button_auto.height
                    text: qsTr("人脸识别")
                    font.pixelSize: row.buttonFontSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Button {
                    id: button_Manual
                    width: button_auto.width
                    height: button_auto.height
                    text: qsTr("手动模式")
                    font.pixelSize: row.buttonFontSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Column {
                // 用于播放预设动作的按钮
                id: column1
                width: parent.width / 2
                height: parent.height * 2 / 3
                spacing: 10
                Repeater {
                    model: MobileClient.getPresetActionNames()
                    Button {
                        text: modelData
                        onClicked: MobileClient.executeAction(modelData)
                    }
                }
            }
        }
    }

    Joystick {
        // 遥控器
        id: control
        width: parent.width * 0.5
        height: width
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 75
        anchors.horizontalCenterOffset: 0
    }

    Button {
        id: button_connect
        text: qsTr("连接")
        font.pixelSize: row.buttonFontSize
        z: 5
        width: parent.width * 0.2
        height: width / 2
        anchors.bottom: control.top
        anchors.topMargin: -3 * button_connect.icon.width
        anchors.horizontalCenter: control.horizontalCenter
    }
    DelayButton {
        id: button_disconnect
        text: qsTr("断开")
        font.pixelSize: row.buttonFontSize
        width: parent.width * 0.2
        height: width / 2
        opacity: 1
        anchors.bottom: control.top
        anchors.topMargin: -3 * button_connect.icon.width
        anchors.horizontalCenter: control.horizontalCenter
    }
}
