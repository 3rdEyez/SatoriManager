import QtQuick 6.2
import QtQuick.Controls 6.2

Rectangle {
    id: mainRectangle
    color: "#f3f4f6"
    radius: 10
    border.color: "#d1d5db"
    border.width: 1

    Rectangle {
        id: header
        width: parent.width
        height: parent.height * 0.1
        color: "#a78bfa"
        radius: 10
        anchors.top: parent.top

        Text {
            anchors.centerIn: parent
            text: qsTr("细节控制面板")
            color: "white"
            font.pixelSize: header.height * 0.4
            font.bold: true
            font.family: "Arial"
        }
    }

    Column {
        id: mainLayout
        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.leftMargin: parent.width * 0.05
        anchors.topMargin: parent.height * 0.02
        spacing: parent.height * 0.03
        width: parent.width - 2 * anchors.leftMargin
        height: parent.height - header.height - parent.height * 0.05

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
                spacing: parent.height * 0.02
                width: parent.width * 0.6

                Dial {
                    id: eyeLidDial
                    width: parent.width
                    height: width
                    value: 0.5
                    onValueChanged: MobileClient.updateChannelValuesWithProportions(-1, -1, value)
                    anchors.horizontalCenter: parent.horizontalCenter

                    background: Rectangle {
                        radius: eyeLidDial.width / 2
                        color: "#e0e7ff"
                        border.color: "#a78bfa"
                        border.width: 2
                    }

                    handle: Rectangle {
                        width: parent.width * 0.1
                        height: width
                        radius: width / 2
                        color: "#a78bfa"
                        border.color: "#7c3aed"
                        border.width: 2

                        // 动态计算手柄位置，修正角度偏移
                        property real correctedAngle: eyeLidDial.angle - 90 // 减去 90 度以修正起始位置
                        x: (parent.width / 2) + (parent.width / 2 - width / 2) * Math.cos(correctedAngle * Math.PI / 180) - width / 2
                        y: (parent.height / 2) + (parent.height / 2 - height / 2) * Math.sin(correctedAngle * Math.PI / 180) - height / 2
                    }
                }

                Text {
                    text: qsTr("眼皮角度")
                    font.pixelSize: parent.width * 0.06
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: "Arial"
                    color: "#4b5563"
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
                spacing: parent.height * 0.02

                Dial {
                    id: pupilDial
                    width: eyeLidDial.width
                    height: eyeLidDial.height
                    anchors.horizontalCenter: parent.horizontalCenter

                    background: Rectangle {
                        radius: pupilDial.width / 2
                        color: "#e0e7ff"
                        border.color: "#a78bfa"
                        border.width: 2
                    }

                    handle: Rectangle {
                        width: parent.width * 0.1
                        height: width
                        radius: width / 2
                        color: "#a78bfa"
                        border.color: "#7c3aed"
                        border.width: 2

                        // 动态计算手柄位置，修正角度偏移
                        property real correctedAngle: pupilDial.angle - 90 // 减去 90 度以修正起始位置
                        x: (parent.width / 2) + (parent.width / 2 - width / 2) * Math.cos(correctedAngle * Math.PI / 180) - width / 2
                        y: (parent.height / 2) + (parent.height / 2 - height / 2) * Math.sin(correctedAngle * Math.PI / 180) - height / 2
                    }
                }

                Text {
                    text: qsTr("瞳孔大小")
                    font.pixelSize: parent.width * 0.06
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: "Arial"
                    color: "#4b5563"
                }
            }
        }
    }
}
