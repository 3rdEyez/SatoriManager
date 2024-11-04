#ifndef MOBILECLIENT_H
#define MOBILECLIENT_H

#include <QObject>
#include <QUdpSocket>
#include <QTimer>
#include <QTQml>

class MobileClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(EyeMode mode READ mode WRITE setMode NOTIFY modeChanged)

public:
    explicit MobileClient(QObject *parent = nullptr);

    // 获取 MobileClient 的单例实例
    static MobileClient* instance();

    // 枚举类：定义客户端的连接模式
    enum class EyeMode : int
    {
        Unconnected,      // 未连接状态
        Auto,             // 自动模式
        Manual,           // 手动模式
        Sleep,            // 休眠模式
        FacialRecognition // 人脸识别模式
    };
    Q_ENUM(EyeMode)

    static const int MIN_PWM_VALUE = 500;    // 最小PWM值
    static const int MAX_PWM_VALUE = 2500;   // 最大PWM值
    // 获取当前客户端模式
    MobileClient::EyeMode mode() const;

public slots:
    Q_INVOKABLE void findServer();                        // 启动服务器发现过程
    void setServerMode(MobileClient::EyeMode serverMode); // 远程更改服务器的模式
    void disconnectFromServer();                          // 断开与服务器的连接
    void updateChannelValue(int channel, int value);
    // 遥控器操作函数，用于控制眼睛的移动和眨眼动作
    void lookUp();
    void lookDown();
    void lookLeft();
    void lookRight();
    void wink();

signals:
    void modeChanged(); // 模式更改时发出信号
    void disconnected(); // 发出断开连接信号
    void batteryInfoReceived(int batteryPercentage); // 收到来自觉之瞳的电量信息

private slots:
    void processPendingDatagrams();              // 处理接收到的 UDP 消息
    void checkConnection();                      // 通过发送心跳包检查连接状态
    void setMode(MobileClient::EyeMode newMode); // 更新本地模式状态
    void sendCommand(const QString &command);    // 向觉之瞳发送指令

private:
    MobileClient::EyeMode parseModeString(const QString &modeString); // 将字符串解析为 EyeMode 枚举
    QString generateModeCommand(MobileClient::EyeMode serverMode);    // 生成模式切换的命令字符串
    QString generatePwmControlMessage();

    MobileClient::EyeMode m_mode; // 当前客户端模式
    QUdpSocket *udpSocket;        // 用于通信的 UDP 套接字
    QString robotIp;              // 连接的觉之瞳的 IP 地址
    quint16 robotPort;            // 觉之瞳的端口号

    QTimer *heartbeatTimer; // 用于周期性发送心跳消息的计时器
    int heartbeatTimeout;   // 记录连续心跳超时的次数

    int currentCH1; // 眼球左右位置
    int currentCH2; // 眼球上下位置
    int currentCH3; // 上眼皮上下位置
    const int Increment = 100; // 每次旋转的角度增量

};

#endif // MOBILECLIENT_H
