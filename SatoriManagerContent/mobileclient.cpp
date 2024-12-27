#include "mobileclient.h"
#include "ProtocolMessages.h"
#include "ActionPresetLoader.h"
#include <QHostAddress>
#include <QDebug>
#include <QNetworkDatagram>

const int MobileClient::MIN_PWM_VALUE;
const int MobileClient::MAX_PWM_VALUE;

// 构造函数：初始化成员变量和UDP通信设置
MobileClient::MobileClient(QObject *parent) : QObject(parent),
                                              actionLoader(new ActionPresetLoader(this)),
                                              udpSocket(new QUdpSocket(this)),
                                              heartbeatTimer(new QTimer(this)),
                                              reconnectTimer(new QTimer(this)),
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

    // 初始化重连定时器
    reconnectTimer->setInterval(10000); // 设置重连间隔为5秒
    connect(reconnectTimer, &QTimer::timeout, this, &MobileClient::attemptReconnect);

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
        udpSocket->writeDatagram(ProtocolMessages::HeartbeatRequest, QHostAddress(robotIp), robotPort);
        qDebug() << "Sent heartbeat request to:" << robotIp << ":" << robotPort;

        if (heartbeatTimeout > 3)
        {
            qWarning() << "Connection lost, setting mode to Unconnected and starting reconnect attempts";
            disconnectFromServer();
            attemptReconnect();
        }
    }
}

// 自动重连逻辑
void MobileClient::attemptReconnect()
{
    if (reconnectAttempts < maxReconnectAttempts)
    {
        reconnectAttempts++;
        qDebug() << "Attempting to reconnect... Attempt" << reconnectAttempts;
        findServer();            // 重新执行服务器发现操作
        reconnectTimer->start(); // 启动重连计时器
    }
    else
    {
        qWarning() << "Max reconnect attempts reached. Stopping further attempts.";
        reconnectTimer->stop();
        emit disconnected(); // 发出已断开连接的信号
    }
}

void MobileClient::updateChannelValues(float inCH1, float inCH2, float inCH3)
{
    if(inCH1<0){
        currentCH1 = MIN_PWM_VALUE + (MAX_PWM_VALUE - MIN_PWM_VALUE) * inCH1;
    }
    if(inCH2<0){
        currentCH2 = MIN_PWM_VALUE + (MAX_PWM_VALUE - MIN_PWM_VALUE) * inCH2;
    }
    if(inCH3<0){
        currentCH3 = MIN_PWM_VALUE + (MAX_PWM_VALUE - MIN_PWM_VALUE) * inCH3;
    }
    sendCommand(generatePwmControlMessage());
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

void MobileClient::processBatteryInfo(const QString &batteryLevel)
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

        if (message.startsWith(ProtocolMessages::DiscoveryResponse))
        {
            QStringList messageParts = message.split(',');
            robotIp = datagram.senderAddress().toString();
            robotPort = datagram.senderPort();
            qDebug() << "Robot server found at:" << robotIp << ":" << robotPort;
            if (messageParts.size() > 1)
            {
                processBatteryInfo(messageParts[1]);
            }
            setMode(MobileClient::EyeMode::Auto);
            heartbeatTimeout = 0;
        }
        else if (message.startsWith(ProtocolMessages::HeartbeatResponse))
        {
            heartbeatTimeout = 0;
            QStringList messageParts = message.split(',');
            if (messageParts.size() > 1)
            {
                processBatteryInfo(messageParts[1]);
            }
        }
        else if (message.startsWith(ProtocolMessages::SetModeSuccessPrefix))
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
    udpSocket->writeDatagram(ProtocolMessages::DiscoveryRequest, QHostAddress::Broadcast, 8888);
}

// 加载预设动作 JSON 文件
bool MobileClient::loadPresetActions(const QString &filePath)
{
    return actionLoader->loadPresetActions(filePath);
}

// 获取所有预设动作的名称
QStringList MobileClient::getPresetActionNames()
{
    return actionLoader->getActionNames();
}

// 执行指定名称的预设动作
void MobileClient::executePresetAction(const QString &actionName)
{
    QVariantList frames = actionLoader->getActionFrames(actionName);
    if (frames.isEmpty())
    {
        qWarning() << "No frames found for action:" << actionName;
        return;
    }

    // 调用播放关键帧的辅助函数
    playFrames(frames);
}

// 播放关键帧数据
void MobileClient::playFrames(const QVariantList &frames)
{
    for (const QVariant &frame : frames)
    {
        QVariantMap frameData = frame.toMap();
        int ch1Value = frameData["CH1"].toInt();
        int ch2Value = frameData["CH2"].toInt();
        int ch3Value = frameData["CH3"].toInt();
        int duration = frameData["duration"].toInt();

        // 使用当前帧的数据更新通道值
        updateChannelValues(ch1Value, ch2Value, ch3Value);

        // 等待当前帧的持续时间
        QThread::msleep(duration);
    }
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
    QString modeCommand = QString(ProtocolMessages::SetModePrefix) + modeToString(serverMode);
    sendCommand(modeCommand);
    qDebug() << "Sent server mode command:" << modeCommand;
}

void MobileClient::disconnectFromServer()
{
    if (!robotIp.isEmpty())
    {
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
    reconnectAttempts = 0; // 重置重连尝试计数
    emit disconnected();
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

// 将模式枚举转换为字符串
QString MobileClient::modeToString(MobileClient::EyeMode mode)
{
    switch (mode)
    {
    case MobileClient::EyeMode::Unconnected:
        return "Unconnected";
    case MobileClient::EyeMode::Auto:
        return "Auto";
    case MobileClient::EyeMode::Manual:
        return "Manual";
    case MobileClient::EyeMode::Sleep:
        return "Sleep";
    case MobileClient::EyeMode::FacialRecognition:
        return "FacialRecognition";
    default:
        return "";
    }
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
    return QString(ProtocolMessages::PwmControlPrefix).arg(currentCH1).arg(currentCH2).arg(currentCH3);
}
