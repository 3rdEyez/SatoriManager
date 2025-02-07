import QtQuick
import SatoriManager 1.0

ScreenMainForm {
    readonly property color highlightColor: "#FAD8E9"  // 高亮颜色
    readonly property color defaultColor: "#F17EB7" // 默认颜色
    button_auto.onClicked: ()=>{
        MobileClient.setServerMode(MobileClient.EyeMode.Auto)
    }
    button_sleep.onClicked: {
        MobileClient.setServerMode(MobileClient.EyeMode.Sleep)
    }
    button_facialRecognition.onClicked: {
        MobileClient.setServerMode(
                    MobileClient.EyeMode.FacialRecognition)
    }
    button_Manual.onClicked: {
        MobileClient.setServerMode(MobileClient.EyeMode.Manual)
    }
    button_connect.onClicked: {
        MobileClient.findServer()
    }
    button_disconnect.onActivated:{
        MobileClient.disconnectFromServer()
    }

    Component.onCompleted: {
        // 监听 modeChanged 信号
        MobileClient.modeChanged.connect(onModeChanged)
        function onModeChanged() {
            button_auto.background.color = MobileClient.mode
                    === MobileClient.EyeMode.Auto ? highlightColor : defaultColor
            button_sleep.background.color = MobileClient.mode
                    === MobileClient.EyeMode.Sleep ? highlightColor : defaultColor
            button_facialRecognition.background.color = MobileClient.mode
                    === MobileClient.EyeMode.FacialRecognition ? highlightColor : defaultColor
            button_Manual.background.color = MobileClient.mode
                    === MobileClient.EyeMode.Manual ? highlightColor : defaultColor

            if(MobileClient.mode === MobileClient.EyeMode.Unconnected){
                button_connect.visible = true
                button_disconnect.visible = false

                button_connect.z = 5
                button_disconnect.z = 0
            }
            else{
                button_connect.visible = false
                button_disconnect.visible = true

                button_connect.z = 0
                button_disconnect.z = 5
            }
        }
    }

}
