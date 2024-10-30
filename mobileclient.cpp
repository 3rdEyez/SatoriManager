#include "mobileclient.h"
#include <QHostAddress>
#include <QDebug>
#include <QNetworkDatagram>

MobileClient::MobileClient(QObject *parent) : QObject(parent)
{
    udpSocket = new QUdpSocket(this);
    setMode(MobileClient::EyeMode::Unconnected);

    currentCH1 = 1500;
    currentCH2 = 1500;
    currentCH3 = 1500;

    // 绑定 UDP 套接字
    udpSocket->bind(QHostAddress::Any, 8889);
    connect(udpSocket, &QUdpSocket::readyRead, this, &MobileClient::processPendingDatagrams);

    // 初始化心跳定时器
    heartbeatTimer = new QTimer(this);
    connect(heartbeatTimer, &QTimer::timeout, this, &MobileClient::checkConnection);
    heartbeatTimer->start(20000);

    // 寻找机器人服务器
    findServer();
}

MobileClient::EyeMode MobileClient::mode() const
{
    return m_mode;
}

void MobileClient::setMode(MobileClient::EyeMode newMode)
{
    if (m_mode != newMode)
    {
        m_mode = newMode;
        emit modeChanged();
    }
}

void MobileClient::checkConnection()
{
    if (!robotIp.isEmpty())
    {
        // 发送心跳包
        QByteArray heartbeatMessage = "SatoriEye_HEARTBEAT_REQUEST";
        udpSocket->writeDatagram(heartbeatMessage, QHostAddress(robotIp), robotPort);
        qDebug() << "Sent heartbeat request to:" << robotIp << ":" << robotPort;
        // 检查心跳超时
        heartbeatTimeout++;
        if (heartbeatTimeout > 3) // 如果连续3次未收到响应
        {
            qWarning() << "Connection lost, setting mode to Unconnected";
            setMode(MobileClient::EyeMode::Unconnected);
            robotIp.clear(); // 清除IP以避免重发心跳包
        }
    }
}

void MobileClient::sendCommand(const QString &command)
{
    if (robotIp.isEmpty())
    {
        qWarning() << "Robot server not found.";
        return;
    }

    QByteArray data = command.toUtf8();
    udpSocket->writeDatagram(data, QHostAddress(robotIp), robotPort);
}

void MobileClient::processPendingDatagrams()
{
    while (udpSocket->hasPendingDatagrams())
    {
        QNetworkDatagram datagram = udpSocket->receiveDatagram();
        QString message = QString::fromUtf8(datagram.data());

        // 处理消息
        if (message=="SatoriEye_DISCOVERY_RESPONSE")
        {
            robotIp = datagram.senderAddress().toString();                                 // 提取 IP
            robotPort = datagram.senderPort(); // 提取端口
            qDebug() << "Robot server found at:" << robotIp << ":" << robotPort;
            setMode(MobileClient::EyeMode::Auto);
            heartbeatTimeout = 0; // 重置心跳超时计数
        }
        else if (message == "SatoriEye_HEARTBEAT_RESPONSE")
        {
            // 收到心跳包响应，重置超时计数
            heartbeatTimeout = 0;
        }
        else if (message.startsWith("SET_MODE_SUCCESS:"))
        {
            // 解析服务器发送的新模式
            QString newModeString = message.section(':', 1, 1); // 提取模式部分
            MobileClient::EyeMode newMode = parseModeString(newModeString);

            if (newMode != MobileClient::EyeMode::Unconnected) // 确保有效的模式
            {
                setMode(newMode);
                qDebug() << "Mode successfully changed to:" << newModeString;
            }
        }
    }
}

void MobileClient::findServer()
{
    qDebug() << "Trying to find server...";
    QByteArray discoveryMessage = "SatoriEye_DISCOVERY_REQUEST";               // 特定的发现消息
    udpSocket->writeDatagram(discoveryMessage, QHostAddress::LocalHost, 8888); // 广播到特定端口
}

void MobileClient::setServerMode(MobileClient::EyeMode serverMode)
{
    if (robotIp.isEmpty())
    {
        qWarning() << "Robot server not found.";
        return;
    }
    if (serverMode == m_mode)
    {
        return;
    }
    QString modeCommand = generateModeCommand(serverMode);
    sendCommand(modeCommand);
    qDebug() << "Sent server mode command:" << modeCommand;
}

// 辅助函数：将模式字符串解析为 EyeMode
MobileClient::EyeMode MobileClient::parseModeString(const QString &modeString)
{
    if (modeString == "Unconnected")
        return MobileClient::EyeMode::Unconnected;
    else if (modeString == "Auto")
        return MobileClient::EyeMode::Auto;
    else if (modeString == "Manual")
        return MobileClient::EyeMode::Manual;
    else if (modeString == "Sleep")
        return MobileClient::EyeMode::Sleep;
    else if (modeString == "FacialRecognition")
        return MobileClient::EyeMode::FacialRecognition;
    else
    {
        qWarning() << "Unknown mode received:" << modeString;
        return MobileClient::EyeMode::Unconnected; // 默认返回 Unconnected
    }
}

// 辅助函数：生成设置模式的命令
QString MobileClient::generateModeCommand(MobileClient::EyeMode serverMode)
{
    switch (serverMode)
    {
    case MobileClient::EyeMode::Unconnected:
        return "SET_MODE:Unconnected";
    case MobileClient::EyeMode::Auto:
        return "SET_MODE:Auto";
    case MobileClient::EyeMode::Manual:
        return "SET_MODE:Manual";
    case MobileClient::EyeMode::Sleep:
        return "SET_MODE:Sleep";
    case MobileClient::EyeMode::FacialRecognition:
        return "SET_MODE:FacialRecognition";
    default:
        return ""; // 未知模式返回空字符串
    }
}

void MobileClient::lookUp()
{
    currentCH2 = qMin(2500, currentCH2 + Increment); // 向上增加角度
    QString message = generatePwmControlMessage(currentCH1, currentCH2, currentCH3);
    sendCommand(message);
    qDebug() << "Sent command to look up with message:" << message;
}

void MobileClient::lookDown()
{
    currentCH2 = qMax(500, currentCH2 - Increment); // 向下减少角度
    QString message = generatePwmControlMessage(currentCH1, currentCH2, currentCH3);
    sendCommand(message);
    qDebug() << "Sent command to look down with message:" << message;
}

void MobileClient::lookLeft()
{
    currentCH1 = qMax(500, currentCH1 - Increment); // 向左旋转
    QString message = generatePwmControlMessage(currentCH1, currentCH2, currentCH3);
    sendCommand(message);
    qDebug() << "Sent command to look left with message:" << message;
}

void MobileClient::lookRight()
{
    currentCH1 = qMin(2500, currentCH1 + Increment); // 向右旋转
    QString message = generatePwmControlMessage(currentCH1, currentCH2, currentCH3);
    sendCommand(message);
    qDebug() << "Sent command to look right with message:" << message;
}

QString MobileClient::generatePwmControlMessage(int ch1, int ch2, int ch3) {
    return QString("CH1:%1CH2:%2CH3:%3").arg(ch1).arg(ch2).arg(ch3);
}
