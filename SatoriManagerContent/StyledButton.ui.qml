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

    background: Rectangle {
        color: customButton.normalColor
        radius: 8
    }

    states: [
        State {
            name: "pressed"
            when: customButton.down
            PropertyChanges { customButton.scale: 0.95 }
        }
    ]

    transitions: [
        Transition {
            NumberAnimation { properties: "scale, opacity"; duration: 100 }
        }
    ]
}
