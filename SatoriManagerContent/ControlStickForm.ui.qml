import QtQuick 2.15

Item {
    id: joystick
    width: 200
    height: 200

    property real outerCircleRadius: 90 // 外圈半径
    property real innerCircleRadius: 30 // 内圈半径
    property point outerCircleCenter: Qt.point(width / 2, height / 2) // 外圈圆心
    property point innerCircleCenter: Qt.point(width / 2, height / 2) // 内圈圆心

    property alias controlArea: joystickArea

    // 外圈
    Canvas {
        id: outerCircle
        anchors.centerIn: parent
        width: joystick.outerCircleRadius * 2
        height: joystick.outerCircleRadius * 2

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.beginPath();
            ctx.arc(width / 2, height / 2, joystick.outerCircleRadius, 0, 2 * Math.PI);
            ctx.fillStyle = "#d3d3d3";
            ctx.fill();
        }
    }

    // 内圈
    Rectangle {
        id: innerCircle
        width: joystick.innerCircleRadius * 2
        height: joystick.innerCircleRadius * 2
        radius: joystick.innerCircleRadius
        color: "#808080"
        x: joystick.innerCircleCenter.x - joystick.innerCircleRadius
        y: joystick.innerCircleCenter.y - joystick.innerCircleRadius
    }

    MouseArea {
        id: joystickArea
        anchors.fill: parent
        drag.target: innerCircle
    }
}
