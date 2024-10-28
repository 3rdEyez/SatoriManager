import QtQuick 6.2
import QtQuick.Controls 6.2
import SatoriManager 1.0

Rectangle {
    id: rectangle
    width: Constants.width
    height: Constants.height
    property alias button_Manual: button_Manual
    property alias control: control
    property alias button_connect: button_connect
    property alias button_facialRecognition: button_facialRecognition
    property alias button_sleep: button_sleep
    property alias button_auto: button_auto

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
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Button {
                    id: button_sleep
                    width: button_auto.width
                    height: button_auto.height
                    text: qsTr("睡眠模式")
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Button {
                    id: button_facialRecognition
                    width: button_auto.width
                    height: button_auto.height
                    text: qsTr("人脸识别")
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Button {
                    id: button_Manual
                    width: button_auto.width
                    height: button_auto.height
                    text: qsTr("手动模式")
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // 监听 modeChanged 信号
                Connections {
                    target: mobileClient
                    // 初始化颜色变量
                    readonly property color highlightColor: "yellow" // 高亮颜色
                    readonly property color defaultColor: "lightgrey" // 默认颜色

                    onModeChanged: {
                        button_auto.background.color = mobileClient.mode === EyeMode.Auto ? highlightColor : defaultColor;
                        button_sleep.background.color = mobileClient.mode === EyeMode.Sleep ? highlightColor : defaultColor;
                        button_facialRecognition.background.color = mobileClient.mode === EyeMode.FacialRecognition ? highlightColor : defaultColor;
                        button_Manual.background.color = mobileClient.mode === EyeMode.Manual ? highlightColor : defaultColor;
                    }
                }
            }

            Column {
                // 用于播放预设动作的按钮
                id: column1
                width: parent.width / 2
                height: parent.height * 2 / 3
                spacing: 10
            }
        }
    }

    JoyStick {
        // 遥控器
        id: control
        width: parent.width * 0.5
        height: width
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 75
    }

    Button {
        id: button_connect
        text: qsTr("连接")
        width: parent.width * 0.2
        height: width / 2
        anchors.bottom: control.top
        anchors.topMargin: -3 * button_connect.icon.width
        anchors.horizontalCenter: control.horizontalCenter
    }
}
