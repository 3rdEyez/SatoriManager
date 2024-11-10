#include "ActionPresetLoader.h"
#include <QDebug>

// Define the file path constant
const QString ActionPresetLoader::PRESET_FILE_PATH = ":/PresetActions.json";

ActionPresetLoader::ActionPresetLoader(QObject *parent) : QObject(parent) {
    loadPresetActions(PRESET_FILE_PATH);
}

bool ActionPresetLoader::loadPresetActions(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
    {
        qWarning() << "Could not open JSON file:" << filePath;
        return false;
    }

    QByteArray data = file.readAll();
    file.close();

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject())
    {
        qWarning() << "Invalid JSON format in file:" << filePath;
        return false;
    }

    actionsMap.clear();
    QJsonObject rootObj = doc.object();
    for (const QString &key : rootObj.keys())
    {
        QJsonObject actionObject = rootObj.value(key).toObject();
        actionsMap.insert(key, parseAction(actionObject));
    }

    qDebug() << "Loaded actions:" << actionsMap.keys();
    return true;
}

QStringList ActionPresetLoader::getActionNames() const
{
    return actionsMap.keys();
}

QVariantList ActionPresetLoader::getActionFrames(const QString &actionName) const
{
    return actionsMap.value(actionName).value("frames").toList();
}

QVariantMap ActionPresetLoader::parseAction(const QJsonObject &actionObject)
{
    QVariantList framesList;

    QJsonArray framesArray = actionObject["frames"].toArray();
    for (const QJsonValue &frameValue : framesArray)
    {
        QJsonObject frameObj = frameValue.toObject();
        QVariantMap frameData;
        frameData.insert("CH1", frameObj["CH1"].toInt());
        frameData.insert("CH2", frameObj["CH2"].toInt());
        frameData.insert("CH3", frameObj["CH3"].toInt());
        frameData.insert("duration", frameObj["duration"].toInt());
        framesList.append(frameData);
    }

    QVariantMap actionData;
    actionData.insert("frames", framesList);
    return actionData;
}
