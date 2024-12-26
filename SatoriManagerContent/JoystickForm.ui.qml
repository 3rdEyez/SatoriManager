
/*
This is a UI file (.ui.qml) that is intended to be edited in Qt Design Studio only.
It is supposed to be strictly declarative and only uses a subset of QML. If you edit
this file manually, you might introduce QML code that is not supported by Qt Design Studio.
Check out https://doc.qt.io/qtcreator/creator-quick-ui-forms.html for details on .ui.qml files.
*/
import QtQuick 6.2
import QtQuick.Controls 6.2

Control {
    id: control
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 75

    height: width
    opacity: 1

    // 暴露组件给qml
    property alias statusText: statusText

    //设置排列相关参数
    property int buttonSpacing: 10
    property int imageSize: width * 0.1

    Rectangle {
        id: ringBackground
        anchors.fill: parent // 背景填充整个父项
        color: "transparent"

        Text {
            id: statusText
            font.pixelSize: 15
            z: 1
            anchors.horizontalCenterOffset: 0
            anchors.horizontalCenter: borderImage.horizontalCenter
            anchors.margins: 20
            anchors.top: parent.bottom
            color: MobileClient.mode !== MobileClient.EyeMode.Unconnected ? "green" : "red" // 初始颜色
            text: "未连接"
            // 闪烁动画
            SequentialAnimation on color {
                running: MobileClient.mode !== MobileClient.EyeMode.Unconnected // 仅在连接时运行动画
                loops: Animation.Infinite
                ColorAnimation {
                    to: "transparent"
                    duration: 1000
                }
                ColorAnimation {
                    to: "green"
                    duration: 1000
                }
            }

            Connections {
                    target: MobileClient
                    onBatteryInfoReceived: (batteryPercentage)=>{
                        statusText.text = "已连接，剩余电量为 " + batteryPercentage + "%" // 更新状态文本
                    }
                    onDisconnected: ()=>{
                                        statusText.text = "未连接"
                    }
            }
        }
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
        ControlStick{
            anchors.fill: ringBackground
        }
    }
}
