import QtQuick 6.2
import QtQuick.Controls 6.2

Button {
    id: customButton
    property color normalColor: "#F17EB7"
    property color pressedColor: Qt.darker(normalColor, 1.2)
    property color hoverColor: Qt.lighter(normalColor, 1.2)
    font.pixelSize: 18
    width: 120
    height: 50
    font.bold: true
    font.family: "Arial" // 使用更现代的字体

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: customButton.down ? Qt.darker(normalColor, 1.1) : customButton.hovered ? Qt.lighter(normalColor, 1.1) : normalColor }
            GradientStop { position: 1.0; color: customButton.down ? Qt.darker(normalColor, 1.3) : customButton.hovered ? Qt.lighter(normalColor, 1.3) : Qt.darker(normalColor, 1.1) }
        }
        radius: customButton.height / 3 // 稍微调整圆角半径，使其更柔和
        border.color: Qt.darker(normalColor, 1.5)
        border.width: 1
    }

    contentItem: Text {
        text: customButton.text
        font: customButton.font
        color: "white"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: customButton.down ? 0.8 : 1.0 // 按下时文字稍微变暗
    }

    states: [
        State {
            name: "pressed"
            when: customButton.down
            PropertyChanges { customButton.scale: 0.95 }
        },
        State {
            name: "hovered"
            when: customButton.hovered
            PropertyChanges { customButton.scale: 1.05 }
        }
    ]

    transitions: [
        Transition {
            from: "*"; to: "*"
            NumberAnimation { properties: "scale, opacity"; duration: 100; easing.type: Easing.InOutQuad }
        }
    ]
}
