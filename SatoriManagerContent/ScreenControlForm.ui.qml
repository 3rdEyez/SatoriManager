/*
This is a UI file (.ui.qml) that is intended to be edited in Qt Design Studio only.
It is supposed to be strictly declarative and only uses a subset of QML. If you edit
this file manually, you might introduce QML code that is not supported by Qt Design Studio.
Check out https://doc.qt.io/qtcreator/creator-quick-ui-forms.html for details on .ui.qml files.
*/
import QtQuick 6.2
import QtQuick.Controls 6.2

Rectangle {
    id: mainRectangle
    width: 640
    height: 480
    color: "#f3f4f6"
    radius: 10
    border.color: "#d1d5db"
    border.width: 1

    Rectangle {
        id: header
        width: parent.width
        height: 50
        color: "#a78bfa"
        radius: 10
        anchors.top: parent.top
        Text {
            anchors.centerIn: parent
            text: qsTr("细节控制面板")
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
        spacing: 20
        width: parent.width - 2 * anchors.leftMargin
        height: parent.height - header.height - 30

        // 眼皮控制部分
        Rectangle {
            id: eyeLidControl
            width: parent.width
            height: parent.height * 0.45
            radius: 10
            color: "#ffffff"
            border.color: "#e5e7eb"
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 5

                Dial {
                    id: eyeLidDial
                    width: parent.width
                    height: width
                    value: 0.5
                    onValueChanged: MobileClient.updateChannelValue(3, value)
                }

                Text {
                    text: qsTr("眼皮角度")
                    font.pixelSize: 20
                }
            }
        }

        // 瞳孔控制部分
        Rectangle {
            id: pupilControl
            width: parent.width
            height: parent.height * 0.4
            radius: 10
            color: "#ffffff"
            border.color: "#e5e7eb"
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 10

                Dial {
                    id: pupilDial
                    width: eyeLidDial.width
                    height: eyeLidDial.height
                }

                Text {
                    text: qsTr("瞳孔大小")
                    font.pixelSize: 20
                }
            }
        }
    }
}
