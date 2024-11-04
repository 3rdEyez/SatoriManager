import QtQuick 6.2

JoystickForm {

    property int batteryLevel: 0 // 定义电量属性

    // 定义用于定时调用的 Timer
    Timer {
        id: repeatTimer
        interval: 100 // 调用间隔，单位为毫秒
        repeat: true // 设置为重复调用
        running: false // 初始状态为不运行

        onTriggered: {
            // 执行相应的移动操作
            if (parent.button_up.pressed) {
                MobileClient.lookUp()
            } else if (parent.button_down.pressed) {
                MobileClient.lookDown()
            } else if (parent.button_left.pressed) {
                MobileClient.lookLeft()
            } else if (parent.button_right.pressed) {
                MobileClient.lookRight()
            } else if (parent.button_wink.pressed) {
                MobileClient.wink()
            }
        }
    }

    button_up.onPressed: {
        repeatTimer.start()
    }
    button_down.onPressed: {
        repeatTimer.start()
    }
    button_left.onPressed: {
        repeatTimer.start()
    }
    button_right.onPressed: {
        repeatTimer.start()
    }
    button_wink.onPressed: {
        repeatTimer.start()
    }

    button_up.onReleased: {
        repeatTimer.stop()
    }
    button_down.onReleased: {
        repeatTimer.stop()
    }
    button_left.onReleased: {
        repeatTimer.stop()
    }
    button_right.onReleased: {
        repeatTimer.stop()
    }
    button_wink.onReleased: {
        repeatTimer.stop()
    }

}
