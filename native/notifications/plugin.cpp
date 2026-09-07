#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QImageReader>
#include <QSaveFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QSocketNotifier>
#include <QTimer>
#include <QUrl>
#include <QUuid>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QBuffer>
#include <QHash>
#include <QDateTime>
#include <wayland-client.h>
#include "lock-client.h"

// Files belong exclusively to this archive. Notification-supplied paths are
// never used as deletion targets, and image names contain no user input.
class ArchiveFiles : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString directory READ directory CONSTANT)
public:
    using QObject::QObject;
    QString directory() const {
        return QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + "/daevox/notifications";
    }
    bool prepare() {
        const auto dir = directory();
        if (!QDir().mkpath(dir + "/images")) return false;
        QFile::setPermissions(dir, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        QFile::setPermissions(dir + "/images", QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        return true;
    }
    Q_INVOKABLE QString load() {
        QFile file(directory() + "/history.json");
        if (!file.exists()) return "";
        if (!file.open(QIODevice::ReadOnly) || file.size() > 16 * 1024 * 1024) return "INVALID";
        const auto bytes = file.readAll();
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(bytes, &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()
            || document.object()["version"].toInt() != 1 || !document.object()["records"].isArray()) {
            file.copy(directory() + "/history.corrupt-" + QString::number(QDateTime::currentMSecsSinceEpoch()) + ".json");
            return "INVALID";
        }
        return QString::fromUtf8(bytes);
    }
    Q_INVOKABLE bool save(const QString &text) {
        if (!prepare()) return false;
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(text.toUtf8(), &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) return false;
        QSaveFile file(directory() + "/history.json");
        if (!file.open(QIODevice::WriteOnly)) return false;
        file.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
        auto bytes = text.toUtf8();
        if (file.write(bytes) != bytes.size() || !file.commit()) return false;
        // Only collect files after committing the snapshot which references them.
        QSet<QString> keep;
        for (const auto &row : document.object()["records"].toArray())
            keep.insert(QUrl(row.toObject()["image"].toString()).toLocalFile());
        const QDir images(directory() + "/images");
        for (const auto &name : images.entryList({"*.png"}, QDir::Files)) {
            const auto path = images.absoluteFilePath(name);
            if (!keep.contains(path)) QFile::remove(path);
        }
        return true;
    }
    Q_INVOKABLE QString cacheImage(const QString &source) {
        if (source.isEmpty() || !prepare()) return "";
        const QUrl url(source);
        QImage image;
        if (url.scheme() == "image") {
            auto *provider = qobject_cast<QQuickImageProvider *>(qmlEngine(this)->imageProvider(url.host()));
            if (!provider) return "";
            QSize size;
            const QString id = url.path().mid(1) + (url.hasQuery() ? "?" + url.query() : "");
            if (provider->imageType() == QQmlImageProviderBase::Image)
                image = provider->requestImage(id, &size, QSize(512, 512));
            else if (provider->imageType() == QQmlImageProviderBase::Pixmap)
                image = provider->requestPixmap(id, &size, QSize(512, 512)).toImage();
        } else if (url.isLocalFile() || url.scheme().isEmpty()) {
            QImageReader reader(url.isLocalFile() ? url.toLocalFile() : source);
            const auto size = reader.size();
            if (!size.isValid() || qint64(size.width()) * size.height() > 16000000) return "";
            reader.setScaledSize(size.scaled(512, 512, Qt::KeepAspectRatio));
            image = reader.read();
        }
        return storeImage(image);
    }
    QString storeImage(QImage image) {
        if (image.isNull() || !prepare()) return "";
        image = image.scaled(512, 512, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        qint64 used = 0;
        for (const auto &file : QDir(directory() + "/images").entryInfoList({"*.png"}, QDir::Files)) used += file.size();
        if (used > 63 * 1024 * 1024) return ""; // Reserve at most 1 MiB for this thumbnail.
        const QString path = directory() + "/images/" + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".png";
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly)) return "";
        file.setPermissions(QFile::ReadOwner | QFile::WriteOwner);
        if (!image.save(&file, "PNG") || !file.commit()) return "";
        return QUrl::fromLocalFile(path).toString();
    }
};

// A small complete protocol endpoint avoids the installed Quickshell 0.3.1
// replacement bugs (action labels, reply removal and identical Notify calls).
// This object lives in the launcher process and is enabled only at cutover.
class NotificationEndpoint : public ArchiveFiles, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
public:
    explicit NotificationEndpoint(QObject *parent = nullptr) : ArchiveFiles(parent), senders(this) {
        senders.setConnection(QDBusConnection::sessionBus());
        senders.setWatchMode(QDBusServiceWatcher::WatchForUnregistration);
        connect(&senders, &QDBusServiceWatcher::serviceUnregistered, this, [this](const QString &sender) {
            for (auto it = entries.begin(); it != entries.end(); ++it) {
                if (it->sender != sender) continue;
                it->actions.clear();
                emit actionsUnavailable(it.key());
            }
            senders.removeWatchedService(sender);
        });
        QTimer::singleShot(0, this, [this] {
            auto bus = QDBusConnection::sessionBus();
            // Do not wait to steal an occupied name later.
            online = bus.registerObject("/org/freedesktop/Notifications", this, QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableSignals)
                && bus.registerService("org.freedesktop.Notifications");
            emit readyChanged();
            if (!online) emit unavailable("Имя сервера уведомлений уже занято или D-Bus недоступен");
        });
    }
    ~NotificationEndpoint() override {
        auto bus = QDBusConnection::sessionBus();
        if (online) bus.unregisterService("org.freedesktop.Notifications");
        bus.unregisterObject("/org/freedesktop/Notifications");
    }
    bool ready() const { return online; }
    Q_INVOKABLE void close(quint32 id, quint32 reason) {
        if (!entries.contains(id)) return;
        const auto sender = entries.take(id).sender;
        pruneSenders();
        send(sender, "NotificationClosed", {id, reason});
        emit closed(id, reason);
    }
    Q_INVOKABLE bool invoke(quint32 id, const QString &action) {
        if (!entries.contains(id) || !entries[id].actions.contains(action) || action == "inline-reply") return false;
        const auto entry = entries[id];
        send(entry.sender, "ActionInvoked", {id, action});
        if (!entry.resident) close(id, 2);
        return true;
    }
    Q_INVOKABLE bool reply(quint32 id, const QString &text) {
        if (!entries.contains(id) || !entries[id].actions.contains("inline-reply") || text.trimmed().isEmpty()) return false;
        const auto entry = entries[id];
        send(entry.sender, "NotificationReplied", {id, text});
        if (!entry.resident) close(id, 2);
        return true;
    }
public slots:
    Q_SCRIPTABLE QStringList GetCapabilities() const { return {"body", "actions", "icon-static", "inline-reply"}; }
    Q_SCRIPTABLE QString GetServerInformation(QString &vendor, QString &version, QString &spec) const {
        vendor = "Daevox"; version = "1.0"; spec = "1.2"; return "Daevox";
    }
    Q_SCRIPTABLE quint32 Notify(const QString &app, quint32 replaces, const QString &icon,
        const QString &summary, const QString &body, const QStringList &actions,
        const QVariantMap &hints, int timeout) {
        const QString sender = calledFromDBus() ? message().service() : "";
        const quint32 id = entries.contains(replaces) ? replaces : nextId();
        Entry entry; entry.sender = sender; entry.resident = hints.value("resident").toBool();
        QVariantList buttons;
        QString placeholder;
        for (int index = 0; index + 1 < actions.size() && index < 128; index += 2) {
            const auto &action = actions[index];
            if (entry.actions.contains(action)) continue;
            entry.actions.append(action);
            if (action == "inline-reply") placeholder = actions[index + 1];
            else buttons.append(QVariantMap{{"id",action},{"text",actions[index+1].left(512)}});
        }
        entries[id] = entry;
        if (!sender.isEmpty() && !entry.actions.isEmpty()) senders.addWatchedService(sender);
        pruneSenders();
        const bool transient = hints.value("transient").toBool();
        QImage raw;
        for (const auto &name : {"image-data", "image_data", "icon_data"}) {
            if (!hints.contains(name)) continue;
            const auto value = hints[name].value<QDBusArgument>();
            if (value.currentSignature() != "(iiibiiay)") break;
            int width = 0, height = 0, stride = 0, bits = 0, channels = 0;
            bool alpha = false; QByteArray bytes;
            value.beginStructure(); value >> width >> height >> stride >> alpha >> bits >> channels >> bytes; value.endStructure();
            const int expected = alpha ? 4 : 3;
            if (width > 0 && height > 0 && qint64(width)*height <= 16000000 && bits == 8 && channels == expected
                && stride >= qint64(width)*expected && qint64(stride)*height <= bytes.size()) {
                raw = QImage(reinterpret_cast<const uchar *>(bytes.constData()), width, height, stride,
                    alpha ? QImage::Format_RGBA8888 : QImage::Format_RGB888).copy();
            }
            break;
        }
        QString image;
        if (!raw.isNull()) {
            if (transient) {
                QByteArray png; QBuffer buffer(&png); buffer.open(QIODevice::WriteOnly);
                raw.scaled(512, 512, Qt::KeepAspectRatio, Qt::SmoothTransformation).save(&buffer, "PNG");
                image = "data:image/png;base64," + QString::fromLatin1(png.toBase64());
            } else image = storeImage(raw);
        } else {
            QString path = hints.value("image-path", hints.value("image_path")).toString();
            if (!path.isEmpty()) {
                if (QUrl(path).scheme().isEmpty() && !path.startsWith('/')) path = "image://icon/" + path;
                if (transient) image = path; else image = cacheImage(path);
            }
        }
        auto desktop = hints.value("desktop-entry").toString().left(512);
        if (desktop.endsWith(".desktop")) desktop.chop(8);
        int urgency = hints.value("urgency", 1).toInt();
        if (urgency < 0 || urgency > 2) urgency = 1;
        QVariantMap data{{"app",app.isEmpty() ? QString("Неизвестное приложение") : app.left(512)},
            {"group", desktop.isEmpty() ? "name:" + (app.isEmpty() ? QString("unknown") : app.left(512)) : "desktop:" + desktop},
            {"summary",summary.left(4096)},{"body",body.left(16384)},{"icon",icon.left(4096)},
            {"urgency",urgency},{"timeout",timeout},{"transient",transient},{"actions",buttons},
            {"reply",entry.actions.contains("inline-reply")},{"replyPlaceholder",placeholder}, {"image",image}};
        emit notified(id, data);
        return id;
    }
    Q_SCRIPTABLE void CloseNotification(quint32 id) {
        if (!entries.contains(id)) {
            if (calledFromDBus()) sendErrorReply("org.freedesktop.Notifications.InvalidId", "Unknown notification ID");
            return;
        }
        close(id, 3);
    }
signals:
    Q_SCRIPTABLE void NotificationClosed(quint32 id, quint32 reason);
    Q_SCRIPTABLE void ActionInvoked(quint32 id, const QString &action);
    Q_SCRIPTABLE void NotificationReplied(quint32 id, const QString &text);
    void readyChanged();
    void unavailable(const QString &reason);
    void notified(quint32 id, const QVariantMap &data);
    void closed(quint32 id, quint32 reason);
    void actionsUnavailable(quint32 id);
private:
    struct Entry { QString sender; QStringList actions; bool resident = false; };
    QHash<quint32, Entry> entries;
    QDBusServiceWatcher senders;
    void pruneSenders() {
        for (const auto &sender : senders.watchedServices()) {
            bool used = false;
            for (const auto &entry : entries) if (entry.sender == sender && !entry.actions.isEmpty()) { used = true; break; }
            if (!used) senders.removeWatchedService(sender);
        }
    }
    quint32 serial = 0;
    bool online = false;
    quint32 nextId() { do { ++serial; } while (!serial || entries.contains(serial)); return serial; }
    void send(const QString &destination, const QString &name, const QVariantList &args) {
        auto signal = QDBusMessage::createTargetedSignal(destination, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", name);
        signal.setArguments(args); QDBusConnection::sessionBus().send(signal);
    }
};

// Separate Wayland connection, integrated into Qt's event loop. No shell
// commands, polling of process names, or separate daemon are involved.
class LockObserver : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
public:
    explicit LockObserver(QObject *parent = nullptr) : QObject(parent) {
        retry.setInterval(2000);
        connect(&retry, &QTimer::timeout, this, &LockObserver::start);
        retry.start();
        QTimer::singleShot(0, this, &LockObserver::start);
    }
    ~LockObserver() override { stop(); }
    QString state() const { return current; }
    void setState(const QString &value) { if (current != value) { current = value; emit stateChanged(); } }
    void stop() {
        delete input; input = nullptr;
        delete output; output = nullptr;
        if (sync) wl_callback_destroy(sync);
        if (notification) hyprland_lock_notification_v1_destroy(notification);
        if (manager) hyprland_lock_notifier_v1_destroy(manager);
        if (registry) wl_registry_destroy(registry);
        if (display) wl_display_disconnect(display);
        sync = nullptr; notification = nullptr; manager = nullptr; registry = nullptr; display = nullptr;
        setState("unknown");
    }
    void flush() {
        if (wl_display_flush(display) < 0) {
            if (errno == EAGAIN) output->setEnabled(true);
            else stop();
        } else output->setEnabled(false);
    }
    void start() {
        if (display) return;
        display = wl_display_connect(nullptr);
        if (!display) return;
        const int fd = wl_display_get_fd(display);
        input = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        output = new QSocketNotifier(fd, QSocketNotifier::Write, this);
        output->setEnabled(false);
        connect(output, &QSocketNotifier::activated, this, [this] { flush(); });
        connect(input, &QSocketNotifier::activated, this, [this] {
            if (wl_display_dispatch(display) < 0) stop();
            else flush();
        });
        registry = wl_display_get_registry(display);
        static const wl_registry_listener listener = {
            [](void *data, wl_registry *reg, uint32_t name, const char *interface, uint32_t) {
                auto *self = static_cast<LockObserver *>(data);
                if (QString::fromUtf8(interface) != "hyprland_lock_notifier_v1" || self->manager) return;
                self->global = name;
                self->manager = static_cast<hyprland_lock_notifier_v1 *>(wl_registry_bind(reg, name, &hyprland_lock_notifier_v1_interface, 1));
                self->notification = hyprland_lock_notifier_v1_get_lock_notification(self->manager);
                static const hyprland_lock_notification_v1_listener events = {
                    [](void *d, hyprland_lock_notification_v1 *) { static_cast<LockObserver *>(d)->setState("locked"); },
                    [](void *d, hyprland_lock_notification_v1 *) { static_cast<LockObserver *>(d)->setState("unlocked"); }
                };
                hyprland_lock_notification_v1_add_listener(self->notification, &events, self);
                // The protocol sends locked immediately for an already locked
                // session. A sync after the subscription establishes the initial
                // unlocked state only after that event has had a chance to arrive.
                self->sync = wl_display_sync(self->display);
                static const wl_callback_listener done = {
                    [](void *d, wl_callback *callback, uint32_t) {
                        auto *s = static_cast<LockObserver *>(d);
                        wl_callback_destroy(callback); s->sync = nullptr;
                        if (s->current == "unknown") s->setState("unlocked");
                    }
                };
                wl_callback_add_listener(self->sync, &done, self);
            },
            [](void *data, wl_registry *, uint32_t name) {
                auto *self = static_cast<LockObserver *>(data);
                if (name == self->global) QTimer::singleShot(0, self, &LockObserver::stop);
            }
        };
        wl_registry_add_listener(registry, &listener, this);
        flush();
    }
signals:
    void stateChanged();
private:
    QString current = "unknown";
    wl_display *display = nullptr;
    wl_registry *registry = nullptr;
    hyprland_lock_notifier_v1 *manager = nullptr;
    hyprland_lock_notification_v1 *notification = nullptr;
    wl_callback *sync = nullptr;
    QSocketNotifier *input = nullptr, *output = nullptr;
    QTimer retry;
    uint32_t global = 0;
};

class NotificationPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        qmlRegisterType<ArchiveFiles>(uri, 1, 0, "ArchiveFiles");
        qmlRegisterType<NotificationEndpoint>(uri, 1, 0, "NotificationEndpoint");
        qmlRegisterType<LockObserver>(uri, 1, 0, "LockObserver");
    }
};
#include "plugin.moc"
