
/*
This is a UI file (.ui.qml) that is intended to be edited in Qt Design Studio only.
It is supposed to be strictly declarative and only uses a subset of QML. If you edit
this file manually, you might introduce QML code that is not supported by Qt Design Studio.
Check out https://doc.qt.io/qtcreator/creator-quick-ui-forms.html for details on .ui.qml files.
*/
import QtQuick
import QtQuick.Controls

Item {
    id: _item

    Column {
        id: column
        width: parent.width
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0 // 设置控件之间的间距
        Item {
            id: _item1
            width: 75
            height: 75
        }
        Column {
            id: eyeLidColumn
            width: parent.width
            height: parent.height / 2
            anchors.horizontalCenterOffset: 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 15
            Dial {
                // 控制眼皮开合角度
                id: eyeLidDial
                width: parent.width * 0.5
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: qsTr("眼皮角度")
                font.pixelSize: 20
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        Column {
            id: pupilColumn
            width: parent.width
            height: parent.height / 2
            anchors.horizontalCenter: parent.horizontalCenter

            Dial {
                // 控制瞳孔大小
                id: pupilDial
                width: eyeLidDial.width
                height: eyeLidDial.height
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: qsTr("瞳孔大小")
                font.pixelSize: 20
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
