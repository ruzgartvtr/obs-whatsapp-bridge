#include "audio-bridge.hpp"
#include "bridge-ui.hpp"

#include <obs-module.h>
#include <obs-frontend-api.h>

OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("obs-whatsapp-bridge", "en-US")

MODULE_EXPORT const char *obs_module_description(void)
{
	return "Routes OBS audio to a virtual mic and helps WhatsApp use OBS Virtual Camera.";
}

MODULE_EXPORT const char *obs_module_name(void)
{
	return "WhatsApp Bridge";
}

static void on_frontend_event(enum obs_frontend_event event, void *)
{
	if (event == OBS_FRONTEND_EVENT_EXIT)
		obs_whatsapp_bridge::unregister_frontend_tools();
}

bool obs_module_load(void)
{
	blog(LOG_INFO, "[whatsapp-bridge] loaded v%s — Tools → WhatsApp Bridge", PLUGIN_VERSION);
	obs_whatsapp_bridge::register_frontend_tools();
	obs_frontend_add_event_callback(on_frontend_event, nullptr);
	return true;
}

void obs_module_unload(void)
{
	obs_frontend_remove_event_callback(on_frontend_event, nullptr);
	obs_whatsapp_bridge::unregister_frontend_tools();
	blog(LOG_INFO, "[whatsapp-bridge] unloaded");
}
