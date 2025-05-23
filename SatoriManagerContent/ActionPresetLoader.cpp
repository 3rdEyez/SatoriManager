#include "ActionPresetLoader.h"
#include <QDebug>
#include <qfileinfo.h>
#include <qresource.h>
#include <qstandardpaths.h>

// Define the file path constant
const QString ActionPresetLoader::PRESET_FILE_PATH = "://SatoriManagerContent/PresetActions.json";

ActionPresetLoader::ActionPresetLoader(QObject *parent) : QObject(parent) {
    loadPresetActions(PRESET_FILE_PATH);
}

bool ActionPresetLoader::loadPresetActions(const QString &filePath)
{
    QFile file(filePath);

    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "Could not open JSON file:" << filePath;
        return false;
    }

    QByteArray data = file.readAll();
    file.close();

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        qWarning() << "Invalid JSON format in file:" << filePath;
        return false;
    }

    actionsMap.clear();
    QJsonObject rootObj = doc.object();
    for (const QString &key : rootObj.keys()) {
        QJsonArray actionArray = rootObj.value(key).toArray();
        actionsMap.insert(key, parseAction(actionArray));
    }

    qDebug() << "Loaded actions:" << actionsMap.keys();
    return true;
}

QVariantMap ActionPresetLoader::parseAction(const QJsonArray &actionArray)
{
    QVariantList framesList;

    for (const QJsonValue &frameValue : actionArray)
    {
        QJsonObject frameObj = frameValue.toObject();
        QVariantMap frameData;

        // 读取浮点数值（支持int/float类型）
        frameData.insert("CH1", frameObj["CH1"].toDouble());
        frameData.insert("CH2", frameObj["CH2"].toDouble());
        frameData.insert("CH3", frameObj["CH3"].toDouble());

        // 保持duration为整数
        frameData.insert("duration", frameObj["duration"].toInt());
        framesList.append(frameData);
    }

    QVariantMap actionData;
    actionData.insert("frames", framesList);
    return actionData;
}

QStringList ActionPresetLoader::getActionNames() const
{
    return actionsMap.keys();
}

QVariantList ActionPresetLoader::getActionFrames(const QString &actionName) const
{
    return actionsMap.value(actionName).value("frames").toList();
}
