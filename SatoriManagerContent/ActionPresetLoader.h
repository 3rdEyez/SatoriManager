#ifndef ACTIONPRESETLOADER_H
#define ACTIONPRESETLOADER_H

#include <QObject>
#include <QVariantMap>
#include <QJsonObject>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>

class ActionPresetLoader : public QObject
{
    Q_OBJECT

public:
    explicit ActionPresetLoader(QObject *parent = nullptr);

    // 从指定路径加载预设动作
    bool loadPresetActions(const QString &filePath);

    // 获取所有动作的名称
    QStringList getActionNames() const;

    // 获取指定动作的关键帧数据
    QVariantList getActionFrames(const QString &actionName) const;

private:
    static const QString PRESET_FILE_PATH;

    // 存储动作名称和对应的关键帧数据
    QMap<QString, QVariantMap> actionsMap;
    // 解析单个动作的关键帧数据
    QVariantMap parseAction(const QJsonArray &actionArray);
};

#endif // ACTIONPRESETLOADER_H
