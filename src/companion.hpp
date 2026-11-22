#pragma once
#include <QWidget>
#include <QNetworkAccessManager>
#include <QWebSocket>
#include <QTimer>
#include <QJsonObject>
#include <QSet>
#include <QQueue>

class QLineEdit;
class QLabel;
class QPushButton;
class QCheckBox;

class CreatoraCompanion final : public QWidget {
    Q_OBJECT
public:
    explicit CreatoraCompanion(QWidget *parent = nullptr);
    void shutdown();
private:
    QString baseUrl_ = "https://creatora.org";
    QString deviceId_, accessToken_, refreshToken_, pairingId_, verifier_;
    QLabel *status_ = nullptr, *pairingCode_ = nullptr;
    QLineEdit *urlInput_ = nullptr;
    QPushButton *pairButton_ = nullptr, *connectButton_ = nullptr, *disconnectButton_ = nullptr, *unpairButton_ = nullptr;
    QCheckBox *autoConnect_ = nullptr;
    QNetworkAccessManager network_;
    QWebSocket socket_;
    QTimer pairingPoll_, retryTimer_, tokenRefresh_;
    QSet<QString> seen_;
    QQueue<QString> seenOrder_;
    bool desiredConnected_ = false, shuttingDown_ = false, refreshing_ = false;
    int retryAttempt_ = 0;
    void setStatus(const QString &text);
    void startPairing();
    void pollPairing();
    void connectNow();
    void openSocket();
    void refreshCredentials(bool andConnect);
    void processCommand(const QJsonObject &command);
    void sendResult(const QString &id, bool ok, const QString &reason);
    void request(const QString &path, const QJsonObject &body,
                 const std::function<void(int, QJsonObject)> &done,
                 const QString &bearer = {});
    void loadSettings();
    void saveSettings();
    bool persistSecrets();
    bool loadSecrets();
    void forgetSecrets();
    bool isSecureEndpoint() const;
    static QString randomString();
};
