import QtQuick 6.2

SettingForm {
    signal resetStateChanged(bool checked)

    rangeSlider.onMoved: MobileClient.setAutoModeParameters(rangeSlider.value, intervalSlider.value)
    intervalSlider.onMoved: MobileClient.setAutoModeParameters(rangeSlider.value, intervalSlider.value)
    resetStick.onCheckedChanged: globalState.resetStickState = resetStick.checked
}
