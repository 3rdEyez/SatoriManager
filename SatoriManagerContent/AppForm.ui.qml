// Copyright (C) 2021 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only
import QtQuick 6.2
import QtQuick.Controls 6.2
import SatoriManager

Rectangle {
    id: window

    visible: true

    SwipeView {
        id: view
        anchors.fill: parent
        currentIndex: 0
        ScreenMain {
            id: mainScreen
        }

        ScreenControl {
            id: controlScreen
        }
    }

    PageIndicator {
        id: indicator

        count: view.count
        currentIndex: view.currentIndex

        anchors.bottom: view.bottom
        anchors.horizontalCenter: parent.horizontalCenter
    }
}
