import QtQuick 6.2
import QtQuick.Controls 6.2
import QtQuick.Layouts 6.2

Rectangle {
    id: root
    property alias rangeSlider: rangeSlider
    property alias intervalSlider: intervalSlider
    property alias resetStick: resetStick
    property alias winkSwitch: winkSwitch
    Rectangle {
        id: header
        width: parent.width
        height: parent.height * 0.1
        color: "#a78bfa"
        radius: 10
        anchors.top: parent.top

        Text {
            anchors.centerIn: parent
            text: qsTr("设置")
            color: "white"
            font.pixelSize: header.height * 0.4
            font.bold: true
        }
    }
    Column{
        id: mainLayout
        anchors.left: parent.left
        anchors.top: header.bottom
        anchors.leftMargin: parent.width * 0.05
        anchors.topMargin: parent.height * 0.02
        spacing: parent.height * 0.02

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    text: qsTr("PWM变化范围:") + ` (${rangeSlider.value}±)`
                    color: "#4a5568"
                }

                Slider {
                        id: rangeSlider
                        Layout.fillWidth: true
                        from: 0
                        to: 500
                        stepSize: 50
                        value: (from + to) / 2

                        background: Rectangle {
                            implicitHeight: 6
                            color: "#e2e8f0"
                            radius: 3

                            Rectangle {
                                width: rangeSlider.visualPosition * parent.width
                                height: parent.height
                                color: "#a78bfa"
                                radius: 3
                                    }
                            }

                        handle: Rectangle {
                            x: rangeSlider.visualPosition * (rangeSlider.width - width)
                            y: (rangeSlider.height - height) / 2
                            width: 24
                            height: 24
                            radius: 12
                            color: rangeSlider.pressed ? "#8e73fa" : "#a78bfa"
                            border.color: "#7c6aea"
                                }
                            }
            }

            // 间隔设置
            ColumnLayout {
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: qsTr("更新间隔:") + ` (${intervalSlider.value}ms)`
                    color: "#4a5568"
                }

                Slider {
                    id: intervalSlider
                    Layout.fillWidth: true
                    from: 100
                    to: 5000
                    stepSize: 100
                    value: (from + to) / 2


                    background: Rectangle {
                        implicitHeight: 6
                        color: "#e2e8f0"
                        radius: 3

                        Rectangle {
                            width: intervalSlider.visualPosition * parent.width
                            height: parent.height
                            color: "#48bb78"
                            radius: 3
                        }
                    }

                    handle: Rectangle {
                        x: intervalSlider.visualPosition * (intervalSlider.width - width)
                        y: (intervalSlider.height - height) / 2
                        width: 24
                        height: 24
                        radius: 12
                        color: intervalSlider.pressed ? "#38a169" : "#48bb78"
                        border.color: "#2f855a"
                    }
                }
            }

            // 操作设置
            ColumnLayout {
                spacing: 12

                Label {
                    text: qsTr("动作设置")
                    color: "#2d3748"
                }

                Label {
                    text: qsTr("松开自动复位:")
                    color: "#4a5568"
                }

                Switch {
                    id: resetStick
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 48
                        implicitHeight: 28
                        radius: 14
                        color: resetStick.checked ? "#a78bfa" : "#e2e8f0"
                        border.color: resetStick.checked ? "#8e73fa" : "#cbd5e0"

                        Rectangle {
                            x: resetStick.checked ? parent.width - width - 4 : 4
                            y: 4
                            width: 20
                            height: 20
                            radius: 10
                            color: resetStick.down ? "#ffffff" : "#f8fafc"
                            border.color: Qt.darker(parent.color, 1.2)
                            Behavior on x { NumberAnimation { duration: 100 } }
                        }
                    }
                }

                Label {
                    text: qsTr("启用自动眨眼:")
                    color: "#4a5568"
                }

                Switch {
                    id: winkSwitch
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 48
                        implicitHeight: 28
                        radius: 14
                        color: winkSwitch.checked ? "#a78bfa" : "#e2e8f0"
                        border.color: winkSwitch.checked ? "#8e73fa" : "#cbd5e0"

                        Rectangle {
                            x: winkSwitch.checked ? parent.width - width - 4 : 4
                            y: 4
                            width: 20
                            height: 20
                            radius: 10
                            color: winkSwitch.down ? "#ffffff" : "#f8fafc"
                            border.color: Qt.darker(parent.color, 1.2)
                            Behavior on x { NumberAnimation { duration: 100 } }
                        }
                    }
                }
            }

            // 保存按钮
            Button {
                text: qsTr("保存配置")
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12

                background: Rectangle {
                    implicitWidth: 120
                    implicitHeight: 40
                    radius: 8
                    color: parent.down ? "#8e73fa" : "#a78bfa"
                    opacity: parent.hovered ? 0.9 : 1.0

                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                }

                onClicked: console.log("配置已保存")
            }
        }
}
