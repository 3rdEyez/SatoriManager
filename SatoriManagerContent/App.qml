import QtQuick 6.2
import QtQuick.Controls 6.2
import SatoriManager

Window {
    id: window
    width: Constants.width
    height: Constants.height

    visible: true
    title: "SatoriManager"

    AppForm{
        width: parent.width
        height: parent.height
    }
}
