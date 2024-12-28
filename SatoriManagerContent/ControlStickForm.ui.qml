import QtQuick 2.15

Item {
    id: joystick
    width: 200
    height: 200

    property real outerCircleRadius: joystick.width / 2 // 外圈半径
    property real innerCircleRadius: joystick.outerCircleRadius / 3 // 内圈半径
    property point outerCircleCenter: Qt.point(width / 2, height / 2) // 外圈圆心
    property point innerCircleCenter: Qt.point(width / 2, height / 2) // 内圈圆心
    property real batteryLevel: 0 // 进度值，范围从0到1
    property real progressBarWidth: 10 // 进度条宽度，可以通过此变量控制

    property alias controlArea: joystickArea

    // 呼吸效果属性
    property real breathOpacity: 1 // 透明度
    property bool breathing: false // 是否启用呼吸效果

    // 呼吸效果动画
    SequentialAnimation {
        id: breathAnimation
        running: joystick.breathing // 是否运行
        loops: Animation.Infinite // 无限循环
        NumberAnimation {
            target: joystick
            property: "breathOpacity"
            from: 0.1 // 最小透明度
            to: 1 // 最大透明度
            duration: 1000 // 动画时长
            easing.type: Easing.InOutQuad // 缓动效果
        }
        NumberAnimation {
            target: joystick
            property: "breathOpacity"
            from: 1 // 最大透明度
            to: 0.1 // 最小透明度
            duration: 2000 // 动画时长
            easing.type: Easing.InOutQuad // 缓动效果
        }
    }

    // 外圈
    Canvas {
        id: outerCircle
        anchors.fill:parent
        antialiasing: true // 启用抗锯齿

        onPaint: {
            var ctx = getContext("2d");
            var centerX = width / 2;
            var centerY = height / 2;
            var outerRadius = joystick.outerCircleRadius - joystick.progressBarWidth / 3;
            var progressRadius = outerRadius; // 进度条半径，确保内接
            var startAngle = Math.PI / 2; // 从最下方开始
            var endAngleOffset = Math.PI * joystick.batteryLevel; // 根据进度计算角度偏移量

            // 清除画布
            ctx.clearRect(0, 0, width, height);

            // 绘制外圈背景
            ctx.beginPath();
            ctx.arc(centerX, centerY, outerRadius, 0, 2 * Math.PI);
            ctx.lineWidth = joystick.progressBarWidth;
            ctx.strokeStyle = "#e0e0e0"; // 外圈背景颜色
            ctx.stroke();

            // 绘制进度圆环（向两侧对称增加）
            ctx.beginPath();
            ctx.arc(centerX, centerY, progressRadius, startAngle - endAngleOffset, startAngle + endAngleOffset);
            ctx.lineWidth = joystick.progressBarWidth;
            ctx.strokeStyle = Qt.rgba(0.49, 0.94, 0.85, joystick.breathOpacity); // 进度颜色，带透明度
            ctx.stroke();
        }
    }

    // 内圈
    Rectangle {
        id: innerCircle
        width: joystick.innerCircleRadius * 2
        height: joystick.innerCircleRadius * 2
        radius: joystick.innerCircleRadius
        color: "#9C57A5"
        //border.color: "white"
        //border.width: 2 // 边框宽度
        x: joystick.innerCircleCenter.x - joystick.innerCircleRadius
        y: joystick.innerCircleCenter.y - joystick.innerCircleRadius
        antialiasing: true // 启用抗锯齿
    }

    // 交互区域
    MouseArea {
        id: joystickArea
        anchors.fill: parent
        drag.target: innerCircle
    }

    // 监听 breathOpacity 变化，重绘 Canvas
    onBreathOpacityChanged: {
        outerCircle.requestPaint();
    }
}
