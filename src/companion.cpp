#include "companion.hpp"
#include <obs.h>
#include <obs-frontend-api.h>
#include <QCheckBox>
#include <QClipboard>
#include <QGuiApplication>
#include <QCloseEvent>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPushButton>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSettings>
#include <QUrl>
#include <QVBoxLayout>
#include <QPointer>
#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <wincrypt.h>
#endif
#include <algorithm>
#include <functional>

namespace {
constexpr auto kSettingsGroup = "CreatoraObsCompanion";
constexpr int kMaxReplyBytes = 32768;
constexpr int kMaxCommandBytes = 8192;
constexpr int kMaxClockSkewMs = 5000;

// Per-OS-user credential encryption. Windows only for this initial release.
QByteArray protect(QByteArray data)
{
#ifdef Q_OS_WIN
    DATA_BLOB in{DWORD(data.size()), reinterpret_cast<BYTE *>(data.data())};
    DATA_BLOB out{};
    if (!CryptProtectData(&in, L"Creatora OBS Companion", nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &out)) return {};
    QByteArray encrypted(reinterpret_cast<char *>(out.pbData), int(out.cbData));
    LocalFree(out.pbData);
    return encrypted;
#else
    Q_UNUSED(data);
    return {};
#endif
}
QByteArray unprotect(QByteArray data)
{
#ifdef Q_OS_WIN
    DATA_BLOB in{DWORD(data.size()), reinterpret_cast<BYTE *>(data.data())};
    DATA_BLOB out{};
    if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr,
                            CRYPTPROTECT_UI_FORBIDDEN, &out)) return {};
    QByteArray plain(reinterpret_cast<char *>(out.pbData), int(out.cbData));
    LocalFree(out.pbData);
    return plain;
#else
    Q_UNUSED(data);
    return {};
#endif
}
}

QString CreatoraCompanion::randomString()
{
    quint32 words[8]{};
    // QRandomGenerator::system is backed by the OS entropy source.
    QRandomGenerator::system()->fillRange(words, 8);
    QByteArray bytes(reinterpret_cast<const char *>(words), sizeof(words));
    return QString::fromLatin1(bytes.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

CreatoraCompanion::CreatoraCompanion(QWidget *parent) : QWidget(parent)
{
    setObjectName("CreatoraCompanion");
    auto *layout = new QVBoxLayout(this);
    layout->addWidget(new QLabel("Creatora OBS Companion — limited remote control", this));
    status_ = new QLabel("Disconnected", this);
    status_->setWordWrap(true);
    layout->addWidget(status_);
    urlInput_ = new QLineEdit(this);
    urlInput_->setPlaceholderText("https://creatora.example.com");
    auto *form = new QFormLayout;
    form->addRow("Server URL", urlInput_);
    layout->addLayout(form);
    pairingCode_ = new QLabel("", this);
    pairingCode_->setTextInteractionFlags(Qt::TextSelectableByMouse);
    pairingCode_->setWordWrap(true);
    layout->addWidget(pairingCode_);
    auto *copyCodeButton = new QPushButton("Copy pairing code", this);
    copyCodeButton->setObjectName("copyPairingCodeButton");
    copyCodeButton->hide();
    layout->addWidget(copyCodeButton);
    connect(copyCodeButton, &QPushButton::clicked, this, [this] {
        const QString code = pairingCode_->property("pairing_code").toString();
        if (code.isEmpty()) return;
        QGuiApplication::clipboard()->setText(code);
        setStatus("Pairing code copied to clipboard. Waiting for account approval…");
    });
    auto *buttons = new QHBoxLayout;
    pairButton_ = new QPushButton("Pair this OBS", this);
    connectButton_ = new QPushButton("Connect", this);
    disconnectButton_ = new QPushButton("Disconnect", this);
    unpairButton_ = new QPushButton("Unpair local device", this);
    buttons->addWidget(pairButton_);
    buttons->addWidget(connectButton_);
    buttons->addWidget(disconnectButton_);
    buttons->addWidget(unpairButton_);
    layout->addLayout(buttons);
    autoConnect_ = new QCheckBox("Connect automatically when OBS starts (security risk)", this);
    autoConnect_->setChecked(false);
    layout->addWidget(autoConnect_);
    auto *notice = new QLabel("Automatic connection gives Creatora permission to execute the enabled OBS actions whenever OBS is open. Only enable it on a trusted PC and account. Disconnect to stop remote control.", this);
    notice->setWordWrap(true);
    layout->addWidget(notice);
    layout->addStretch();
    loadSettings();
    urlInput_->setText(baseUrl_);
    connect(pairButton_, &QPushButton::clicked, this, &CreatoraCompanion::startPairing);
    connect(connectButton_, &QPushButton::clicked, this, &CreatoraCompanion::connectNow);
    connect(disconnectButton_, &QPushButton::clicked, this, [this] {
        desiredConnected_ = false;
        retryTimer_.stop();
        socket_.close();
        setStatus("Disconnected manually; remote commands disabled");
    });
    connect(unpairButton_, &QPushButton::clicked, this, [this] {
        const auto reply = QMessageBox::warning(this, "Unpair OBS companion",
            "Remove local credentials? You must ALSO revoke this device in Creatora → Account → OBS Companion to invalidate it on the server.",
            QMessageBox::Yes | QMessageBox::No, QMessageBox::No);
        if (reply != QMessageBox::Yes) return;
        desiredConnected_ = false;
        retryTimer_.stop(); pairingPoll_.stop(); tokenRefresh_.stop();
        socket_.close();
        forgetSecrets();
        pairingCode_->clear();
        pairingCode_->setProperty("pairing_code", QString());
        findChild<QPushButton *>("copyPairingCodeButton")->hide();
        autoConnect_->setChecked(false);
        saveSettings();
        setStatus("Local pairing removed. Revoke device in Creatora dashboard.");
    });
    connect(autoConnect_, &QCheckBox::toggled, this, [this](bool checked) {
        if (checked) {
            const auto answer = QMessageBox::warning(this, "Auto-connect security warning",
                "With auto-connect enabled, Creatora may control permitted OBS functions every time OBS launches. "
                "A compromised Creatora account or device session could trigger actions while you are away. "
                "Enable only on a trusted computer. Continue?",
                QMessageBox::Yes | QMessageBox::No, QMessageBox::No);
            if (answer != QMessageBox::Yes) {
                autoConnect_->setChecked(false);
                return;
            }
        }
        saveSettings();
    });
    connect(urlInput_, &QLineEdit::editingFinished, this, [this] {
        const QString next = urlInput_->text().trimmed().remove(QRegularExpression("/+$"));
        if (next != baseUrl_ && (!deviceId_.isEmpty() || !refreshToken_.isEmpty())) {
            QMessageBox::information(this, "Server is paired", "Disconnect and unpair before changing the server URL.");
            urlInput_->setText(baseUrl_);
            return;
        }
        if (!next.startsWith("https://")) {
            QMessageBox::warning(this, "HTTPS required", "Only HTTPS server URLs are accepted.");
            urlInput_->setText(baseUrl_);
            return;
        }
        baseUrl_ = next;
        saveSettings();
    });
    connect(&pairingPoll_, &QTimer::timeout, this, &CreatoraCompanion::pollPairing);
    pairingPoll_.setInterval(3000);
    connect(&retryTimer_, &QTimer::timeout, this, [this] {
        retryTimer_.stop();
        if (desiredConnected_) refreshCredentials(true);
    });
    retryTimer_.setSingleShot(true);
    connect(&tokenRefresh_, &QTimer::timeout, this, [this] {
        if (desiredConnected_ && !refreshing_) refreshCredentials(false);
    });
    tokenRefresh_.setInterval(8 * 60 * 1000);
    connect(&socket_, &QWebSocket::connected, this, [this] {
        retryAttempt_ = 0;
        tokenRefresh_.start();
        setStatus("Connected (remote control enabled)");
        QJsonObject hello{{"type", "hello"}, {"protocol", 1}, {"device_id", deviceId_},
                          {"capabilities", QJsonArray{"scene.switch", "sceneitem.visibility", "input.mute"}}};
        socket_.sendTextMessage(QString::fromUtf8(QJsonDocument(hello).toJson(QJsonDocument::Compact)));
    });
    connect(&socket_, &QWebSocket::disconnected, this, [this] {
        tokenRefresh_.stop();
        if (!desiredConnected_ || shuttingDown_) return;
        setStatus("Connection lost; retrying with bounded backoff");
        const int delay = std::min(60000, 2000 * (1 << std::min(retryAttempt_++, 5)));
        retryTimer_.start(delay);
    });
    connect(&socket_, &QWebSocket::textMessageReceived, this, [this](const QString &message) {
        if (message.toUtf8().size() > kMaxCommandBytes) { socket_.close(); return; }
        const auto doc = QJsonDocument::fromJson(message.toUtf8());
        if (!doc.isObject()) return;
        const auto payload = doc.object();
        if (payload.value("type").toString() == "command") processCommand(payload);
        else if (payload.value("type").toString() == "ping")
            socket_.sendTextMessage(QStringLiteral("{\"type\":\"pong\"}"));
    });
    if (autoConnect_->isChecked() && !refreshToken_.isEmpty()) {
        QTimer::singleShot(1500, this, &CreatoraCompanion::connectNow);
    }
}

void CreatoraCompanion::shutdown()
{
    shuttingDown_ = true;
    desiredConnected_ = false;
    pairingPoll_.stop();
    retryTimer_.stop();
    tokenRefresh_.stop();
    socket_.close();
    saveSettings();
}
void CreatoraCompanion::setStatus(const QString &text) { status_->setText(text); }
bool CreatoraCompanion::isSecureEndpoint() const
{
    const QUrl url(baseUrl_);
    return url.isValid() && url.scheme() == "https" && !url.host().isEmpty() &&
           url.userInfo().isEmpty() && !url.hasQuery() && !url.hasFragment();
}
void CreatoraCompanion::request(const QString &path, const QJsonObject &body,
                                const std::function<void(int, QJsonObject)> &done,
                                const QString &bearer)
{
    if (!isSecureEndpoint()) { done(0, {{"error", "invalid_https_url"}}); return; }
    const QUrl url(baseUrl_ + path);
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("Cache-Control", "no-store");
    if (!bearer.isEmpty()) req.setRawHeader("Authorization", "Bearer " + bearer.toUtf8());
    auto *reply = network_.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    auto *timeout = new QTimer(reply);
    timeout->setSingleShot(true);
    QObject::connect(timeout, &QTimer::timeout, reply, &QNetworkReply::abort);
    timeout->start(12000);
    QObject::connect(reply, &QNetworkReply::finished, this, [reply, done] {
        const QByteArray bytes = reply->readAll();
        int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        // Preserve HTTP response codes even if Qt reports an HTTP error.
        // For transport/TLS failures, surface the actual Qt error to the user.
        if (bytes.size() > kMaxReplyBytes) {
            done(0, {{"error", "response_too_large"},
                     {"message", "Server response exceeds 32 KiB"}});
        } else if (status == 0) {
            done(0, {{"error", "transport_error"},
                     {"message", reply->errorString().left(240)},
                     {"qt_network_error", static_cast<int>(reply->error())}});
        } else {
            const auto parsed = QJsonDocument::fromJson(bytes);
            done(status, parsed.isObject() ? parsed.object() : QJsonObject{});
        }
        reply->deleteLater();
    });
}
void CreatoraCompanion::startPairing()
{
    if (!isSecureEndpoint()) { setStatus("HTTPS URL required"); return; }
    if (!deviceId_.isEmpty()) {
        const auto answer = QMessageBox::question(this, "Replace pairing?",
            "This OBS instance is already paired. Pairing again replaces its saved credentials. Proceed?");
        if (answer != QMessageBox::Yes) return;
    }
    pairingCode_->clear();
    pairingCode_->setProperty("pairing_code", QString());
    findChild<QPushButton *>("copyPairingCodeButton")->hide();
    verifier_ = randomString();
    const QString challenge = QString::fromLatin1(QCryptographicHash::hash(
        verifier_.toUtf8(), QCryptographicHash::Sha256).toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
    pairingPoll_.stop();
    pairButton_->setEnabled(false);
    request("/api/companion/pair/start", {{"protocol", 1}, {"challenge", challenge}, {"device_name", "OBS Studio"}},
        [this](int status, QJsonObject data) {
            pairButton_->setEnabled(true);
            if (status != 201) {
                const QString errorCode = data.value("error").toString();
                const QString details = errorCode.isEmpty() ? QString() : " (" + errorCode.left(64) + ")";
                if (status == 0) {
                    const QString transportCode = data.value("error").toString();
                    const QString reason = data.value("message").toString().left(240);
                    const int qtCode = data.value("qt_network_error").toInt(-1);
                    setStatus("Pairing failed: " + transportCode +
                              " (Qt network error " + QString::number(qtCode) + ")" +
                              (reason.isEmpty() ? QString() : " — " + reason));
                } else {
                    setStatus("Pairing failed: HTTP " + QString::number(status) + details);
                }
                verifier_.clear();
                return;
            }
            pairingId_ = data.value("pairing_id").toString();
            const QString code = data.value("user_code").toString();
            if (pairingId_.isEmpty() || code.isEmpty()) { setStatus("Invalid pairing response"); return; }
            pairingCode_->setProperty("pairing_code", code);
            findChild<QPushButton *>("copyPairingCodeButton")->show();
            pairingCode_->setText("Open Creatora → Account → OBS Companion and enter code: " + code +
                                  "\nExpires in 5 minutes. Never share this code.");
            setStatus("Waiting for account approval…");
            pairingPoll_.start();
            QTimer::singleShot(5 * 60 * 1000, this, [this, id = pairingId_] {
                if (pairingId_ == id) { pairingPoll_.stop(); pairingId_.clear(); verifier_.clear();
                    pairingCode_->setProperty("pairing_code", QString());
                    findChild<QPushButton *>("copyPairingCodeButton")->hide();
                    setStatus("Pairing expired"); }
            });
        });
}
void CreatoraCompanion::pollPairing()
{
    if (pairingId_.isEmpty() || verifier_.isEmpty()) { pairingPoll_.stop(); return; }
    request("/api/obs-companion/v1/pairing/poll", {{"pairing_id", pairingId_}, {"verifier", verifier_}},
        [this](int status, QJsonObject data) {
            if (status == 202 || status == 429 || status == 0) return;
            if (status != 200) { pairingPoll_.stop(); pairingId_.clear(); verifier_.clear();
                pairingCode_->setProperty("pairing_code", QString());
                findChild<QPushButton *>("copyPairingCodeButton")->hide();
                setStatus("Pairing failed or expired"); return; }
            const auto device = data.value("device_id").toString();
            const auto token = data.value("access_token").toString();
            const auto refresh = data.value("refresh_token").toString();
            if (device.isEmpty() || token.isEmpty() || refresh.isEmpty()) { setStatus("Invalid credentials"); return; }
            pairingPoll_.stop();
            pairingId_.clear(); verifier_.clear();
            deviceId_ = device; accessToken_ = token; refreshToken_ = refresh;
            if (!persistSecrets()) {
                deviceId_.clear(); accessToken_.clear(); refreshToken_.clear();
                setStatus("Secure credential storage unavailable. Pairing refused.");
                return;
            }
            pairingCode_->setProperty("pairing_code", QString());
            findChild<QPushButton *>("copyPairingCodeButton")->hide();
            pairingCode_->setText("Paired; click Connect to enable remote control.");
            setStatus("Paired (disconnected)");
        });
}
void CreatoraCompanion::connectNow()
{
    if (refreshToken_.isEmpty() || deviceId_.isEmpty()) { setStatus("Pair OBS first"); return; }
    if (!isSecureEndpoint()) { setStatus("HTTPS URL required"); return; }
    desiredConnected_ = true;
    retryTimer_.stop();
    refreshCredentials(true);
}
void CreatoraCompanion::refreshCredentials(bool andConnect)
{
    if (refreshing_ || refreshToken_.isEmpty()) return;
    refreshing_ = true;
    request("/api/obs-companion/v1/device/refresh", {{"device_id", deviceId_}, {"refresh_token", refreshToken_}},
        [this, andConnect](int status, QJsonObject data) {
            refreshing_ = false;
            if (status == 401 || status == 403) {
                desiredConnected_ = false;
                socket_.close();
                forgetSecrets();
                setStatus("Device revoked or credentials expired; pair again");
                return;
            }
            if (!desiredConnected_) return;
            if (status != 200) {
                setStatus("Secure token refresh failed; remote control unavailable");
                if (desiredConnected_) retryTimer_.start(10000);
                return;
            }
            const QString access = data.value("access_token").toString();
            const QString refresh = data.value("refresh_token").toString();
            if (access.isEmpty() || refresh.isEmpty()) { setStatus("Invalid token response"); return; }
            accessToken_ = access; refreshToken_ = refresh;
            if (!persistSecrets()) {
                desiredConnected_ = false;
                socket_.close();
                setStatus("Could not store rotated credentials securely");
                return;
            }
            if (andConnect && desiredConnected_) openSocket();
            else if (desiredConnected_ && socket_.state() == QAbstractSocket::ConnectedState) {
                // Never continue a live session under credentials that may have been revoked.
                socket_.close();
            }
        });
}
void CreatoraCompanion::openSocket()
{
    if (!desiredConnected_ || accessToken_.isEmpty()) return;
    if (socket_.state() != QAbstractSocket::UnconnectedState) return;
    QUrl url(baseUrl_);
    url.setScheme("wss");
    url.setPath("/api/obs-companion/v1/connect");
    QNetworkRequest req(url);
    req.setRawHeader("Authorization", "Bearer " + accessToken_.toUtf8());
    req.setRawHeader("Cache-Control", "no-store");
    socket_.open(req);
    setStatus("Connecting to Creatora…");
}
void CreatoraCompanion::sendResult(const QString &id, bool ok, const QString &reason)
{
    QJsonObject value{{"type", "result"}, {"id", id}, {"ok", ok}, {"reason", reason}};
    if (socket_.state() == QAbstractSocket::ConnectedState)
        socket_.sendTextMessage(QString::fromUtf8(QJsonDocument(value).toJson(QJsonDocument::Compact)));
}
void CreatoraCompanion::processCommand(const QJsonObject &message)
{
    const QString id = message.value("id").toString();
    const QString action = message.value("action").toString();
    const qint64 expiry = qint64(message.value("expires_at_ms").toDouble());
    if (id.size() < 16 || id.size() > 128 || !message.value("args").isObject()) return;
    if (seen_.contains(id)) { sendResult(id, false, "duplicate"); return; }
    seen_.insert(id); seenOrder_.enqueue(id);
    while (seenOrder_.size() > 512) seen_.remove(seenOrder_.dequeue());
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (expiry < now - kMaxClockSkewMs || expiry > now + 30000) { sendResult(id, false, "expired_or_invalid_ttl"); return; }
    const QJsonObject args = message.value("args").toObject();
    bool ok = false;
    QString reason = "unsupported_action";
    if (action == "scene.switch") {
        const QString name = args.value("scene").toString();
        if (!name.isEmpty() && name.size() <= 256) {
            QByteArray utf8 = name.toUtf8();
            obs_source_t *source = obs_get_source_by_name(utf8.constData());
            if (source) {
                if (obs_source_get_type(source) == OBS_SOURCE_TYPE_SCENE) {
                    obs_frontend_set_current_scene(source);
                    ok = true; reason = "ok";
                } else reason = "not_a_scene";
                obs_source_release(source);
            } else reason = "scene_not_found";
        } else reason = "invalid_scene";
    } else if (action == "input.mute") {
        const QString name = args.value("input").toString();
        if (!name.isEmpty() && name.size() <= 256 && args.value("muted").isBool()) {
            const QByteArray utf8 = name.toUtf8();
            obs_source_t *source = obs_get_source_by_name(utf8.constData());
            if (source) {
                if (obs_source_get_output_flags(source) & OBS_SOURCE_AUDIO) {
                    obs_source_set_muted(source, args.value("muted").toBool());
                    ok = true; reason = "ok";
                } else reason = "not_audio_input";
                obs_source_release(source);
            } else reason = "input_not_found";
        } else reason = "invalid_arguments";
    } else if (action == "sceneitem.visibility") {
        const QString sceneName = args.value("scene").toString();
        const QString sourceName = args.value("source").toString();
        if (sceneName.size() <= 256 && sourceName.size() <= 256 && !sceneName.isEmpty() && !sourceName.isEmpty() && args.value("visible").isBool()) {
            const auto s = sceneName.toUtf8(), i = sourceName.toUtf8();
            obs_source_t *source = obs_get_source_by_name(s.constData());
            if (source) {
                obs_scene_t *scene = obs_scene_from_source(source);
                if (scene) {
                    obs_sceneitem_t *item = obs_scene_find_source(scene, i.constData());
                    if (item) { obs_sceneitem_set_visible(item, args.value("visible").toBool()); ok = true; reason = "ok"; }
                    else reason = "scene_item_not_found";
                } else reason = "not_a_scene";
                obs_source_release(source);
            } else reason = "scene_not_found";
        } else reason = "invalid_arguments";
    }
    sendResult(id, ok, reason);
}
void CreatoraCompanion::loadSettings()
{
    QSettings settings("Creatora", kSettingsGroup);
    baseUrl_ = settings.value("url", baseUrl_).toString();
    // Security by default: missing setting means auto-connect off.
    autoConnect_->setChecked(settings.value("auto_connect", false).toBool());
    loadSecrets();
}
void CreatoraCompanion::saveSettings()
{
    QSettings settings("Creatora", kSettingsGroup);
    settings.setValue("url", baseUrl_);
    settings.setValue("auto_connect", autoConnect_->isChecked());
}
bool CreatoraCompanion::persistSecrets()
{
    QJsonObject data{{"device_id", deviceId_}, {"access_token", accessToken_}, {"refresh_token", refreshToken_}};
    QByteArray cipher = protect(QJsonDocument(data).toJson(QJsonDocument::Compact));
    if (cipher.isEmpty()) return false;
    QSettings settings("Creatora", kSettingsGroup);
    settings.setValue("encrypted_credentials", cipher.toBase64());
    settings.sync();
    return settings.status() == QSettings::NoError;
}
bool CreatoraCompanion::loadSecrets()
{
    QSettings settings("Creatora", kSettingsGroup);
    const QByteArray encoded = settings.value("encrypted_credentials").toByteArray();
    if (encoded.isEmpty()) return false;
    const QByteArray plaintext = unprotect(QByteArray::fromBase64(encoded));
    const QJsonDocument doc = QJsonDocument::fromJson(plaintext);
    if (!doc.isObject()) return false;
    const auto data = doc.object();
    deviceId_ = data.value("device_id").toString();
    accessToken_ = data.value("access_token").toString();
    refreshToken_ = data.value("refresh_token").toString();
    return !deviceId_.isEmpty() && !refreshToken_.isEmpty();
}
void CreatoraCompanion::forgetSecrets()
{
    deviceId_.clear(); accessToken_.clear(); refreshToken_.clear();
    QSettings settings("Creatora", kSettingsGroup);
    settings.remove("encrypted_credentials");
    settings.sync();
}
