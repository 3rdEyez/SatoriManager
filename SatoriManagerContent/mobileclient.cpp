
#include "mobileclient.h"
#include "ProtocolMessages.h"
#include "ActionPresetLoader.h"
#include <QHostAddress>
#include <QDebug>
#include <QNetworkDatagram>
#include <QRandomGenerator>
const int MobileClient::MIN_PWM_VALUE;
const int MobileClient::MAX_PWM_VALUE;
// 常量定义
namespace {
const quint16 DISCOVERY_PORT = 8888;
const quint16 CLIENT_PORT = 8889;
const int HEARTBEAT_INTERVAL = 20000;
const int MAX_HEARTBEAT_TIMEOUT = 3;
const int RECONNECT_INTERVAL = 10000;
const int MAX_RECONNECT_ATTEMPTS = 5;
const int DEFAULT_SMOOTH_DURATION = 200;
const int DEFAULT_WAIT_PERIOD = 5000;
}

MobileClient::MobileClient(QObject *parent) : QObject(parent),
    actionLoader(new ActionPresetLoader(this)),
    udpSocket(new QUdpSocket(this)),
    m_mode(EyeMode::Unconnected),
    currentCH1(1500), currentCH2(1500), currentCH3(1500),
    randomEngine(QRandomGenerator::global()->generate()),
    autoModeInterval(DEFAULT_WAIT_PERIOD),
    autoModeChangeRange(250)
{
    setupNetwork();
    setupTimers();
    findServer();
}

// 网络相关初始化
void MobileClient::setupNetwork()
{
    udpSocket->bind(QHostAddress::Any, CLIENT_PORT);
    connect(udpSocket, &QUdpSocket::readyRead, this, &MobileClient::processPendingDatagrams);
}

// 定时器初始化
void MobileClient::setupTimers()
{
    heartbeatTimer = new QTimer(this);
    heartbeatTimer->setInterval(HEARTBEAT_INTERVAL);
    connect(heartbeatTimer, &QTimer::timeout, this, &MobileClient::checkConnection);
    heartbeatTimer->start();

    reconnectTimer = new QTimer(this);
    reconnectTimer->setInterval(RECONNECT_INTERVAL);
    connect(reconnectTimer, &QTimer::timeout, this, &MobileClient::attemptReconnect);

    autoModeTimer = new QTimer(this);
    connect(autoModeTimer, &QTimer::timeout, this, &MobileClient::generateAutoPWM);

    m_autoWinkTimer = new QTimer(this);
    m_autoWinkTimer->setSingleShot(true); // 单次触发模式
    connect(m_autoWinkTimer, &QTimer::timeout, this, &MobileClient::onAutoWinkTimeout);
}

// 处理接收数据报的主逻辑
void MobileClient::processPendingDatagrams()
{
    while (udpSocket->hasPendingDatagrams()) {
        QNetworkDatagram datagram = udpSocket->receiveDatagram();
        const QString message = QString::fromUtf8(datagram.data());

        if (message.startsWith(ProtocolMessages::DiscoveryResponse)) {
            handleDiscoveryResponse(datagram, message);
        } else if (message.startsWith(ProtocolMessages::HeartbeatResponse)) {
            handleHeartbeatResponse(message);
        } else if (message.startsWith(ProtocolMessages::SetModeSuccessPrefix)) {
            handleModeChangeResponse(message);
        }
    }
}

// 处理服务器发现响应
void MobileClient::handleDiscoveryResponse(const QNetworkDatagram& datagram, const QString& message)
{
    QStringList parts = message.split(',');
    robotIp = datagram.senderAddress().toString();
    robotPort = datagram.senderPort();

    qDebug() << "Discovered server at:" << robotIp << ":" << robotPort;

    if (parts.size() > 1) {
        processBatteryInfo(parts[1]);
    }

    setMode(EyeMode::Manual);
    scheduleNextWink();
    heartbeatTimeout = 0;
}

// 处理心跳响应
void MobileClient::handleHeartbeatResponse(const QString& message)
{
    heartbeatTimeout = 0;
    QStringList parts = message.split(',');
    if (parts.size() > 1) {
        processBatteryInfo(parts[1]);
    }
}

// 处理模式变更响应
void MobileClient::handleModeChangeResponse(const QString& message)
{
    const QString newModeString = message.section(':', 1, 1);
    const EyeMode newMode = parseModeString(newModeString);

    if (newMode != EyeMode::Unconnected) {
        setMode(newMode);
        qDebug() << "Mode changed to:" << newModeString;
    }
}

// 更新通道值（核心逻辑）
void MobileClient::updateChannelValues(int inCH1, int inCH2, int inCH3, bool smooth, int duration)
{
    currentCH1 = qBound(MIN_PWM_VALUE, inCH1, MAX_PWM_VALUE);
    currentCH2 = qBound(MIN_PWM_VALUE, inCH2, MAX_PWM_VALUE);
    currentCH3 = qBound(MIN_PWM_VALUE, inCH3, MAX_PWM_VALUE);

    sendCommand(generatePwmControlMessage(smooth, duration));
}

// 生成自动模式PWM值
void MobileClient::generateAutoPWM()
{
    constexpr int center = (MIN_PWM_VALUE + MAX_PWM_VALUE) / 2;
    std::normal_distribution<float> dist(0.0f, autoModeChangeRange);

    const int newCH1 = center + static_cast<int>(dist(randomEngine));
    const int newCH2 = center + static_cast<int>(dist(randomEngine));

    // 自动模式使用非平滑移动
    updateChannelValues(newCH1, newCH2, currentCH3, true, DEFAULT_SMOOTH_DURATION);
}

// 播放动作关键帧
void MobileClient::playFrames(const QVariantList &frames)
{
    for (const auto& frame : frames) {
        const auto frameData = frame.toMap();
        float ch1 = frameData["CH1"].toDouble();
        float ch2 = frameData["CH2"].toDouble();
        float ch3 = frameData["CH3"].toDouble();
        const int duration = frameData["duration"].toInt();
        // 使用平滑移动并指定持续时间
        updateChannelValuesWithProportions(ch1, ch2, ch3, true, DEFAULT_SMOOTH_DURATION);

        // 等待当前帧的持续时间
        QThread::msleep(duration);
    }
}

void MobileClient::setAutoWinkEnabled(bool enabled)
{
    if (m_autoWinkEnabled != enabled) {
        m_autoWinkEnabled = enabled;

        if (enabled) {
            // 启用时启动第一次眨眼
            scheduleNextWink();
        } else {
            // 禁用时停止定时器
            m_autoWinkTimer->stop();
        }
        emit autoWinkEnabled();
    }
}

void MobileClient::onAutoWinkTimeout()
{
    if (!m_autoWinkEnabled) return;

    // 执行眨眼动作
    wink();

    // 安排下一次眨眼
    scheduleNextWink();
}

void MobileClient::scheduleNextWink()
{
    if(mode() == EyeMode::Unconnected){
        return;
    }
    // 生成带随机波动的间隔（4500-5500ms）
    int interval = m_baseWinkInterval
                   + QRandomGenerator::global()->bounded(-m_winkIntervalJitter, m_winkIntervalJitter);

    m_autoWinkTimer->start(interval);
    qDebug() << "Next wink scheduled in" << interval << "ms";
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
        // 先停止之前的模式相关操作
        if (m_mode == EyeMode::Auto) {
            stopAutoMode();
        }

        m_mode = newMode;

        // 启动新模式相关操作
        if (newMode == EyeMode::Auto) {
            startAutoMode();
        }

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

void MobileClient::updateChannelValuesWithProportions(float inCH1, float inCH2, float inCH3, bool smooth, int duration)
{
    if (inCH1 >= 0)
    {
        currentCH1 = MIN_PWM_VALUE + (MAX_PWM_VALUE - MIN_PWM_VALUE) * inCH1;
    }
    if (inCH2 >= 0)
    {
        currentCH2 = MIN_PWM_VALUE + (MAX_PWM_VALUE - MIN_PWM_VALUE) * inCH2;
    }
    if (inCH3 >= 0)
    {
        currentCH3 = MIN_PWM_VALUE + (MAX_PWM_VALUE - MIN_PWM_VALUE) * inCH3;
    }
    sendCommand(generatePwmControlMessage(smooth, duration));
}

// 发送命令到服务器
void MobileClient::sendCommand(const QString &command)
{
    qDebug() << "Trying to send message:" << command;
    if (robotIp.isEmpty())
    {
        qWarning() << "Robot server not found.";
        return;
    }
    QByteArray data = command.toUtf8();
    udpSocket->writeDatagram(data, QHostAddress(robotIp), robotPort);
    qDebug() << "Message sent.";
}

void MobileClient::processBatteryInfo(const QString &batteryLevel)
{
    int Percentage = batteryLevel.toInt();
    emit batteryInfoReceived(Percentage);
}

// 发现服务器的方法
void MobileClient::findServer()
{
    qDebug() << "Trying to find server...";
    udpSocket->writeDatagram(ProtocolMessages::DiscoveryRequest, QHostAddress::Broadcast, 8888);
    udpSocket->writeDatagram(ProtocolMessages::DiscoveryRequest, QHostAddress::LocalHost, 8888);
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
    if(serverMode == EyeMode::Auto || serverMode == EyeMode::Manual){
        setMode(serverMode);
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

    // 停止自动模式
    if (autoModeTimer->isActive()) {
        autoModeTimer->stop();
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
    bool chooseFirst = QRandomGenerator::global()->bounded(2);

    if(chooseFirst) {
        executePresetAction("wink");
    } else {
        executePresetAction("wink2");
    }
}

// 生成PWM控制消息字符串
QString MobileClient::generatePwmControlMessage(bool bShouldSmooth, int MS)
{
    if(bShouldSmooth){
        return QString(ProtocolMessages::SmoothPwmControlPrefix).arg(currentCH1).arg(currentCH2).arg(currentCH3).arg(MS);
    }
    else{
        return QString(ProtocolMessages::PwmControlPrefix).arg(currentCH1).arg(currentCH2).arg(currentCH3);
    }
}

void MobileClient::startAutoMode()
{
    autoModeTimer->start(autoModeInterval);
    qDebug() << "Auto mode started with parameters:"
             << "Change range:" << autoModeChangeRange
             << "Interval:" << autoModeInterval;
}

void MobileClient::stopAutoMode()
{
    autoModeTimer->stop();
    qDebug() << "Auto mode stopped";
}

void MobileClient::setAutoModeParameters(int changeRange, int interval)
{
    autoModeChangeRange = qBound(0, changeRange, 1000); // 限制变化范围0-500
    autoModeInterval = qBound(10, interval, 5000);     // 限制间隔10-5000ms
    qDebug() << "Updated auto mode parameters:"
             << "Change range:" << autoModeChangeRange
             << "Interval:" << autoModeInterval;

    // 如果当前处于自动模式，立即应用新间隔
    if (m_mode == EyeMode::Auto) {
        autoModeTimer->setInterval(autoModeInterval);
    }
}
