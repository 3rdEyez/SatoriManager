#include "mobileclient.h"
#include <QHostAddress>
#include <QDebug>
#include <QNetworkDatagram>
const int MobileClient::MIN_PWM_VALUE;
const int MobileClient::MAX_PWM_VALUE;

// 构造函数：初始化成员变量和UDP通信设置
MobileClient::MobileClient(QObject *parent) : QObject(parent),
                                              udpSocket(new QUdpSocket(this)),
                                              heartbeatTimer(new QTimer(this)),
                                              m_mode(EyeMode::Unconnected),
                                              currentCH1(1500), // 默认初始值
                                              currentCH2(1500), // 默认初始值
                                              currentCH3(1500)  // 默认初始值
{
    udpSocket->bind(QHostAddress::Any, 8889);
    connect(udpSocket, &QUdpSocket::readyRead, this, &MobileClient::processPendingDatagrams);

    // 初始化心跳定时器并设置定时任务
    connect(heartbeatTimer, &QTimer::timeout, this, &MobileClient::checkConnection);
    heartbeatTimer->start(20000);

    // 寻找觉之瞳服务器
    findServer();
}

// 获取当前模式
MobileClient::EyeMode MobileClient::mode() const
{
    return m_mode;
}

// 获取 MobileClient 的单例实例
MobileClient *MobileClient::instance()
{
    static MobileClient instance;
    return &instance;
}

// 设置模式并发出模式改变信号
void MobileClient::setMode(MobileClient::EyeMode newMode)
{
    if (m_mode != newMode)
    {
        m_mode = newMode;
        emit modeChanged();
    }
}

// 检查连接状态并发送心跳包
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
        if (heartbeatTimeout > 3)
        { // 如果连续3次未收到响应
            qWarning() << "Connection lost, setting mode to Unconnected";
            disconnectFromServer();
        }
    }
}

// 发送命令到服务器
void MobileClient::sendCommand(const QString &command)
{
    if (robotIp.isEmpty())
    {
        qWarning() << "Robot server not found.";
        return;
    }
    QByteArray data = command.toUtf8();
    udpSocket->writeDatagram(data, QHostAddress(robotIp), robotPort);
    qDebug() << "Sent message:" << command;
}

void MobileClient::processBatteryInfo(const QString& batteryLevel)
{
    int Percentage = batteryLevel.toInt();
    emit batteryInfoReceived(Percentage);
}
    void MobileClient::processPendingDatagrams()
{
    while (udpSocket->hasPendingDatagrams())
    {
        QNetworkDatagram datagram = udpSocket->receiveDatagram();
        QString message = QString::fromUtf8(datagram.data());

        if (message.startsWith("SatoriEye_DISCOVERY_RESPONSE"))
        {
            // 假设连接确认消息中包含电量信息
            QStringList messageParts = message.split(',');
            robotIp = datagram.senderAddress().toString();
            robotPort = datagram.senderPort();
            qDebug() << "Robot server found at:" << robotIp << ":" << robotPort;
            if (messageParts.size() > 1)
            {
                processBatteryInfo(messageParts[1]); // 处理电量信息
            }
            setMode(MobileClient::EyeMode::Auto);
            heartbeatTimeout = 0; // 重置心跳超时计数
        }
        else if (message.startsWith("SatoriEye_HEARTBEAT_RESPONSE"))
        {
            heartbeatTimeout = 0;
            QStringList messageParts = message.split(',');
            if (messageParts.size() > 1)
            {
                processBatteryInfo(messageParts[1]); // 处理电量信息
            }
        }
        else if (message.startsWith("SET_MODE_SUCCESS:"))
        {
            QString newModeString = message.section(':', 1, 1);
            MobileClient::EyeMode newMode = parseModeString(newModeString);
            if (newMode != MobileClient::EyeMode::Unconnected)
            {
                setMode(newMode);
                qDebug() << "Mode successfully changed to:" << newModeString;
            }
        }
    }
}

// 发现服务器的方法
void MobileClient::findServer()
{
    qDebug() << "Trying to find server...";
    QByteArray discoveryMessage = "SatoriEye_DISCOVERY_REQUEST";
    udpSocket->writeDatagram(discoveryMessage, QHostAddress::LocalHost, 8888);
}

// 发送设置模式的命令
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

void MobileClient::disconnectFromServer()
{
    if (!robotIp.isEmpty())
    {
        // 向服务器发送断开连接的通知
        QByteArray disconnectMessage = "SatoriEye_DISCONNECT";
        udpSocket->writeDatagram(disconnectMessage, QHostAddress(robotIp), robotPort);
        qDebug() << "Sent disconnect message to server.";
    }

    if (udpSocket->isOpen())
    {
        udpSocket->close();
        qDebug() << "Disconnected from server.";
    }
    if (heartbeatTimer->isActive())
    {
        heartbeatTimer->stop();
    }
    robotIp.clear();
    setMode(EyeMode::Unconnected);
    emit disconnected();
}

// 更新通道值并发送PWM控制消息
void MobileClient::updateChannelValue(int channel, int value)
{
    switch (channel)
    {
    case 1:
        currentCH1 = qBound(MIN_PWM_VALUE, currentCH1 + value, MAX_PWM_VALUE);
        break;
    case 2:
        currentCH2 = qBound(MIN_PWM_VALUE, currentCH2 + value, MAX_PWM_VALUE);
        break;
    case 3:
        currentCH3 = qBound(MIN_PWM_VALUE, currentCH3 + value, MAX_PWM_VALUE);
        break;
    }
    sendCommand(generatePwmControlMessage());
}

// 将模式字符串解析为 EyeMode 枚举值
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
        return MobileClient::EyeMode::Unconnected;
    }
}

// 生成设置模式的命令字符串
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
        return "";
    }
}

// 控制眼球向上的方法
void MobileClient::lookUp()
{
    updateChannelValue(2, Increment);
}

// 控制眼球向下的方法
void MobileClient::lookDown()
{
    updateChannelValue(2, -Increment);
}

// 控制眼球向左的方法
void MobileClient::lookLeft()
{
    updateChannelValue(1, -Increment);
}

// 控制眼球向右的方法
void MobileClient::lookRight()
{
    updateChannelValue(1, Increment);
}

// 发送眨眼命令的方法
void MobileClient::wink()
{
    sendCommand("WINK");
    qDebug() << "Sent command to wink";
}

// 生成PWM控制消息字符串
QString MobileClient::generatePwmControlMessage()
{
    return QString("CH1:%1CH2:%2CH3:%3").arg(currentCH1).arg(currentCH2).arg(currentCH3);
}
