#include "companion.hpp"
#include <obs-module.h>
#include <obs-frontend-api.h>
#include <QApplication>
#include <QPointer>
#include <QFileInfo>
#include <QVersionNumber>
#include <QtGlobal>

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("creatora-obs-companion", "en-US")
MODULE_EXPORT const char *obs_module_description(void) { return "Creatora secure OBS companion"; }

// The OBS_CURRENT_MODULE accessor is defined by OBS_DECLARE_MODULE in this
// translation unit. Other source files should not call obs_module_config_path.
char *creatoraModuleConfigPath(const char *file)
{
    return obs_module_get_config_path(obs_current_module(), file);
}

// OBS owns the dock widget after obs_frontend_add_dock_by_id().
// QPointer becomes null when OBS destroys the widget during shutdown.
static QPointer<CreatoraCompanion> companion;

bool obs_module_load(void)
{
    blog(LOG_INFO, "[Creatora] Loading companion: compiled Qt %s, runtime Qt %s", QT_VERSION_STR, qVersion());
    if (!QApplication::instance()) {
        blog(LOG_ERROR, "[Creatora] Could not initialize: QApplication instance not available");
        return false;
    }
    QApplication::addLibraryPath(QFileInfo(QString::fromUtf8(
        obs_get_module_binary_path(obs_current_module()))).absolutePath());
    companion = new CreatoraCompanion;
    if (!obs_frontend_add_dock_by_id("creatora-companion-dock", "Creatora Companion", companion)) {
        delete companion;
        companion = nullptr;
        blog(LOG_ERROR, "[Creatora] Failed to register dock creatora-companion-dock (duplicate dock ID or unsupported frontend)");
        return false;
    }
    // Save settings and close connections before OBS dismantles its UI.
    // QObject's receiver context ensures this runs only while the dock exists.
    QObject::connect(QApplication::instance(), &QCoreApplication::aboutToQuit,
                     companion.data(), [] {
                         if (companion) companion->shutdown();
                     });
    blog(LOG_INFO, "[Creatora] Companion loaded (manual connection default)");
    return true;
}

void obs_module_unload(void)
{
    // OBS calls module unload from obs_shutdown(), after frontend teardown.
    // Do NOT call obs_frontend_remove_dock() here: that accesses an OBS main
    // window which may already have been destroyed (shutdown crash).
    // OBS owns and destroys the dock widget with its main window.
    companion = nullptr;
}
