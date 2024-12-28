import QtQuick 2.15


ControlStickForm {
    id: joystick
    signal innerCircleMoved(point newCenter, real normalizedX, real normalizedY)

    onInnerCircleMoved: function(newCenter, normalizedX, normalizedY) {
        console.log("Inner Circle Center changed to: " + newCenter + ", Normalized X: " + normalizedX + ", Normalized Y: " + normalizedY);
        MobileClient.updateChannelValuesWithProportions(normalizedX, normalizedY);
    }

    function mapToNormalized(value, minInput, maxInput) {
        return (value - minInput) / (maxInput - minInput);
    }

    controlArea.onPressed: function(mouse){
        var dx = mouse.x - outerCircleCenter.x;
        var dy = mouse.y - outerCircleCenter.y;
        if (Math.sqrt(dx * dx + dy * dy) <= outerCircleRadius) {
            innerCircleCenter = Qt.point(mouse.x, mouse.y);
            var normalizedX = mapToNormalized(innerCircleCenter.x, outerCircleCenter.x - outerCircleRadius, outerCircleCenter.x + outerCircleRadius);
            var normalizedY = mapToNormalized(innerCircleCenter.y, outerCircleCenter.y - outerCircleRadius, outerCircleCenter.y + outerCircleRadius);

            joystick.innerCircleMoved(innerCircleCenter, normalizedX, normalizedY);
        }
    }

    controlArea.onPositionChanged: function(mouse){
        if (controlArea.pressed) {
            var dx = mouse.x - outerCircleCenter.x;
            var dy = mouse.y - outerCircleCenter.y;
            var distance = Math.sqrt(dx * dx + dy * dy);

            if (distance > outerCircleRadius) {
                dx = dx / distance * outerCircleRadius;
                dy = dy / distance * outerCircleRadius;
            }

            innerCircleCenter = Qt.point(outerCircleCenter.x + dx, outerCircleCenter.y + dy);

            var normalizedX = mapToNormalized(innerCircleCenter.x, outerCircleCenter.x - outerCircleRadius, outerCircleCenter.x + outerCircleRadius);
            var normalizedY = mapToNormalized(innerCircleCenter.y, outerCircleCenter.y - outerCircleRadius, outerCircleCenter.y + outerCircleRadius);

            joystick.innerCircleMoved(innerCircleCenter, normalizedX, normalizedY);
        }
    }

    controlArea.onReleased: {
        innerCircleCenter = outerCircleCenter;

        var normalizedX = mapToNormalized(innerCircleCenter.x, outerCircleCenter.x - outerCircleRadius, outerCircleCenter.x + outerCircleRadius);
        var normalizedY = mapToNormalized(innerCircleCenter.y, outerCircleCenter.y - outerCircleRadius, outerCircleCenter.y + outerCircleRadius);

        joystick.innerCircleMoved(innerCircleCenter, normalizedX, normalizedY);
    }
}
