#pragma once

#include <obs-module.h>
#include <string>

namespace obs_whatsapp_bridge {

/** Routes OBS program / monitored audio into the virtual mic device. */
class AudioBridge {
public:
	static AudioBridge &instance();

	bool start();
	void stop();
	bool is_running() const { return running_; }

	/** Core Audio device name WhatsApp should select as microphone. */
	static const char *virtual_mic_name();

	/** True if OBS Bridge Mic (or a known fallback) is present. */
	bool virtual_mic_available() const;

	std::string status_text() const;

private:
	AudioBridge() = default;
	bool running_ = false;
	std::string monitoring_device_id_;

	bool find_virtual_mic(std::string &device_id, std::string &device_name) const;
	void apply_monitoring_to_sources(bool enable);
};

} // namespace obs_whatsapp_bridge
