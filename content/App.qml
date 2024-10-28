// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 6.2
import SatoriManager
import QtQuick.Controls 6.2

Window {
    id: window
    width: Constants.width
    height: Constants.height

    visible: true
    title: "SatoriManager"

    SwipeView {
        id: swipeView
        width: Window.width
        height: Window.height

        ScreenMain {
            id: mainScreen

            button_auto.onClicked: {
                mobileClient.setServerMode(MobileClient.EyeMode.Auto)
            }
            button_sleep.onClicked: {
                mobileClient.setServerMode(MobileClient.EyeMode.Sleep)
            }
            button_facialRecognition.onClicked: {
                mobileClient.setServerMode(MobileClient.EyeMode.FacialRecognition)
            }
            button_Manual.onClicked: {
                mobileClient.setServerMode(MobileClient.EyeMode.Manual)
            }
            button_connect.onClicked: {
                mobileClient.findServer()
            }
            control.button_up.onPressed: {
                mobileClient.lookUp()
            }
            control.button_down.onPressed: {
                mobileClient.lookDown()
            }
            control.button_left.onPressed: {
                mobileClient.lookLeft()
            }
            control.button_right.onPressed:{
                mobileClient.lookRight()
            }
            control.button_wink.onPressed:{
                mobileClient.wink()
            }
        }

    }

    PageIndicator {
        id: pageIndicator
        y: Window.height - 30
        anchors.horizontalCenterOffset: 0
        anchors.horizontalCenter: parent.horizontalCenter
        count: 1
    }

}

