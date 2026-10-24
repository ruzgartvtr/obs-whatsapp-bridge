#pragma once

#include <string>

namespace obs_whatsapp_bridge {

struct WhatsAppStatus {
	bool installed = false;
	bool virtual_cam_likely_enabled = false;
	std::string app_path;
	std::string message;
};

/** Locate WhatsApp.app and report whether virtual-camera entitlements look applied. */
WhatsAppStatus probe_whatsapp();

/**
 * Re-sign WhatsApp helpers with disable-library-validation so OBS / NDI virtual
 * cameras appear in the camera list. Requires admin (osascript password prompt).
 * Returns true if the script was launched successfully.
 */
bool enable_whatsapp_virtual_camera(std::string &error_out);

/** Path to the bundled enable-whatsapp.sh helper, if present next to the plugin. */
std::string bundled_enable_script_path();

} // namespace obs_whatsapp_bridge
