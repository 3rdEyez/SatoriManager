import QtQuick 6.2
import QtQuick.Controls 6.2

Control {
    id: control
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 75
    width: column.width * 0.4
    height: width
    opacity: 1

    // 暴露组件给qml
    property alias button_down: button_down
    property alias button_right: button_right
    property alias button_left: button_left
    property alias button_wink: button_wink
    property alias button_up: button_up

    //设置排列相关参数
    property int buttonSpacing: 10
    property int imageSize: width * 0.1

    Rectangle {
        id: ringBackground
        anchors.fill: parent // 背景填充整个父项
        color: "transparent"

        BorderImage {
            id: borderImage
            opacity: 0.4
            source: "images/circle.png"
            z: -1
            verticalTileMode: BorderImage.Stretch
            horizontalTileMode: BorderImage.Stretch
            anchors.fill: ringBackground
            border.left: 20
            border.right: 20
            border.top: 20
            border.bottom: 20
        }

        RoundButton {
            id: button_up
            anchors.horizontalCenter: button_wink.horizontalCenter
            anchors.bottom: button_wink.top
            anchors.bottomMargin: buttonSpacing
            width: control.width * 0.25
            height: control.width * 0.25

            Image {
                width: control.imageSize
                height: control.imageSize
                anchors.centerIn: parent
                source: "images/right.png"
                rotation: -90
                fillMode: Image.PreserveAspectFit
            }
        }

        RoundButton {
            id: button_left
            anchors.verticalCenter: button_wink.verticalCenter
            anchors.right: button_wink.left
            anchors.rightMargin: buttonSpacing
            width: button_up.width
            height: button_up.height

            Image {
                width: control.imageSize
                height: control.imageSize
                anchors.centerIn: parent
                source: "images/right.png"
                rotation: 180
                fillMode: Image.PreserveAspectFit
            }
        }

        RoundButton {
            id: button_wink
            width: control.width * 0.3
            height: control.width * 0.3
            radius: button_wink.width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            checkable: true
            display: AbstractButton.IconOnly
            flat: false
            highlighted: true
        }

        RoundButton {
            id: button_right
            anchors.verticalCenter: button_wink.verticalCenter
            anchors.left: button_wink.right
            anchors.leftMargin: buttonSpacing
            width: button_up.width
            height: button_up.height

            Image {
                width: control.imageSize
                height: control.imageSize
                anchors.centerIn: parent
                source: "images/right.png"
                rotation: 0
                fillMode: Image.PreserveAspectFit
            }
        }

        RoundButton {
            id: button_down
            anchors.horizontalCenter: button_wink.horizontalCenter
            anchors.top: button_wink.bottom
            anchors.topMargin: buttonSpacing
            width: button_up.width
            height: button_up.height

            Image {
                width: control.imageSize
                height: control.imageSize
                anchors.centerIn: parent
                source: "images/right.png"
                rotation: 90
                fillMode: Image.PreserveAspectFit
            }
        }
    }
}
