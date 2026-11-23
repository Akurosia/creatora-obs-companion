#pragma once
#include <QWidget>
#include <QNetworkAccessManager>
#include <QWebSocket>
#include <QTimer>
#include <QJsonObject>
#include <QJsonArray>
#include <QSet>
#include <QQueue>
#include <QHash>
#include <QFileSystemWatcher>

class QLineEdit;
class QLabel;
class QPushButton;
class QCheckBox;
class QListWidget;

class CreatoraCompanion final : public QWidget {
    Q_OBJECT
public:
    explicit CreatoraCompanion(QWidget *parent = nullptr);
    void shutdown();
private:
    QString baseUrl_ = "https://creatora.org";
    QString deviceId_, accessToken_, refreshToken_, pairingId_, verifier_;
    QLabel *status_ = nullptr, *pairingCode_ = nullptr, *updateInfo_ = nullptr;
    QLineEdit *urlInput_ = nullptr;
    QListWidget *allowedFilesList_ = nullptr;
    QPushButton *pairButton_ = nullptr, *connectButton_ = nullptr, *disconnectButton_ = nullptr, *unpairButton_ = nullptr;
    QCheckBox *autoConnect_ = nullptr;
    QNetworkAccessManager network_;
    QWebSocket socket_;
    QTimer pairingPoll_, retryTimer_, tokenRefresh_, fileSyncTimer_;
    QFileSystemWatcher fileWatcher_;
    QSet<QString> seen_;
    QQueue<QString> seenOrder_;
    QHash<QString, qint64> recentScreenshots_;
    QHash<QString, QByteArray> lastFileHashes_;
    bool desiredConnected_ = false, shuttingDown_ = false, refreshing_ = false, helloAccepted_ = false;
    int retryAttempt_ = 0;
    void setStatus(const QString &text);
    void checkForUpdates();
    void startPairing();
    void pollPairing();
    void connectNow();
    void openSocket();
    void refreshCredentials(bool andConnect);
    void processCommand(const QJsonObject &command);
    void captureScreenshot(const QString &id, qint64 expiry, const QJsonObject &args);
    void sendResult(const QString &id, bool ok, const QString &reason);
    void request(const QString &path, const QJsonObject &body,
                 const std::function<void(int, QJsonObject)> &done,
                 const QString &bearer = {});
    void loadSettings();
    void saveSettings();
    bool persistSecrets();
    bool loadSecrets();
    void forgetSecrets();
    QJsonArray allowedFileInventory() const;
    void refreshAllowedFileWatcher();
    void sendAllowedFileValues();
    bool isSecureEndpoint() const;
    static QString randomString();
};
