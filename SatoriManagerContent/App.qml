import QtQuick 6.2
import QtQuick.Controls 6.2
import SatoriManager

Window {
    id: window
    width: Constants.width
    height: Constants.height

    visible: true
    title: "SatoriManager"
    QtObject {
            id: globalState
            property bool resetStickState: true  // 定义全局属性
        }
    AppForm{
        width: parent.width
        height: parent.height
    }
}
