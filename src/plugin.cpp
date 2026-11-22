#include "companion.hpp"
#include <obs-module.h>
#include <obs-frontend-api.h>
#include <QApplication>
#include <QFileInfo>

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("creatora-obs-companion", "en-US")
MODULE_EXPORT const char *obs_module_description(void) { return "Creatora secure OBS companion"; }

static CreatoraCompanion *companion = nullptr;

bool obs_module_load(void)
{
    if (!QApplication::instance()) return false;
    QApplication::addLibraryPath(QFileInfo(QString::fromUtf8(
        obs_get_module_binary_path(obs_current_module()))).absolutePath());
    companion = new CreatoraCompanion;
    if (!obs_frontend_add_dock_by_id("creatora-companion-dock", "Creatora Companion", companion)) {
        delete companion;
        companion = nullptr;
        return false;
    }
    blog(LOG_INFO, "[Creatora] Companion loaded (manual connection default)");
    return true;
}

void obs_module_unload(void)
{
    if (companion) {
        companion->shutdown();
        obs_frontend_remove_dock("creatora-companion-dock");
        companion = nullptr;
    }
}
