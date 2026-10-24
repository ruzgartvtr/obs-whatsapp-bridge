#include "audio-bridge.hpp"

#include <obs-frontend-api.h>

#include <cstring>
#include <string>
#include <vector>

namespace obs_whatsapp_bridge {
namespace {

struct DeviceMatch {
	std::string name;
	std::string id;
	bool preferred = false;
};

bool name_matches_virtual_mic(const char *name)
{
	if (!name)
		return false;
	static const char *candidates[] = {
		"OBS Bridge Mic",
		"OBSBridgeMic",
		"BlackHole 2ch",
		"BlackHole 16ch",
		"BlackHole",
		"VB-Cable",
		nullptr,
	};
	for (int i = 0; candidates[i]; ++i) {
		if (strstr(name, candidates[i]))
			return true;
	}
	return false;
}

bool is_preferred_name(const char *name)
{
	return name && (strstr(name, "OBS Bridge") || strstr(name, "OBSBridge"));
}

bool enum_monitor_cb(void *data, const char *name, const char *id)
{
	auto *matches = static_cast<std::vector<DeviceMatch> *>(data);
	if (!name_matches_virtual_mic(name))
		return true;
	DeviceMatch m;
	m.name = name ? name : "";
	m.id = id ? id : "";
	m.preferred = is_preferred_name(name);
	matches->push_back(std::move(m));
	return true;
}

} // namespace

AudioBridge &AudioBridge::instance()
{
	static AudioBridge bridge;
	return bridge;
}

const char *AudioBridge::virtual_mic_name()
{
	return OBS_BRIDGE_MIC_NAME;
}

bool AudioBridge::find_virtual_mic(std::string &device_id, std::string &device_name) const
{
	std::vector<DeviceMatch> matches;
	obs_enum_audio_monitoring_devices(enum_monitor_cb, &matches);
	if (matches.empty())
		return false;

	for (const auto &m : matches) {
		if (m.preferred) {
			device_id = m.id;
			device_name = m.name;
			return true;
		}
	}
	device_id = matches.front().id;
	device_name = matches.front().name;
	return true;
}

bool AudioBridge::virtual_mic_available() const
{
	std::string id, name;
	return find_virtual_mic(id, name);
}

void AudioBridge::apply_monitoring_to_sources(bool enable)
{
	obs_enum_sources(
		[](void *param, obs_source_t *source) {
			bool on = *static_cast<bool *>(param);
			uint32_t flags = obs_source_get_output_flags(source);
			if ((flags & OBS_SOURCE_AUDIO) == 0)
				return true;

			obs_monitoring_type type = on ? OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT
						      : OBS_MONITORING_TYPE_NONE;
			obs_source_set_monitoring_type(source, type);
			return true;
		},
		&enable);
}

bool AudioBridge::start()
{
	if (running_)
		return true;

	if (!obs_audio_monitoring_available()) {
		blog(LOG_WARNING, "[whatsapp-bridge] Audio monitoring not available on this build");
		return false;
	}

	std::string device_id;
	std::string device_name;
	if (!find_virtual_mic(device_id, device_name)) {
		blog(LOG_WARNING,
		     "[whatsapp-bridge] Virtual mic not found. Install OBS Bridge Mic "
		     "(scripts/install-audio-driver.sh) or: brew install blackhole-2ch");
		return false;
	}

	if (!obs_set_audio_monitoring_device(device_name.c_str(), device_id.c_str())) {
		blog(LOG_ERROR, "[whatsapp-bridge] obs_set_audio_monitoring_device failed for %s",
		     device_name.c_str());
		return false;
	}

	monitoring_device_id_ = device_id;
	apply_monitoring_to_sources(true);
	running_ = true;

	blog(LOG_INFO,
	     "[whatsapp-bridge] Audio bridge ON → \"%s\" (id=%s). "
	     "WhatsApp microphone: %s",
	     device_name.c_str(), device_id.c_str(), device_name.c_str());
	return true;
}

void AudioBridge::stop()
{
	if (!running_)
		return;
	apply_monitoring_to_sources(false);
	running_ = false;
	blog(LOG_INFO, "[whatsapp-bridge] Audio bridge OFF");
}

std::string AudioBridge::status_text() const
{
	std::string id, name;
	if (!find_virtual_mic(id, name)) {
		return "Sanal mikrofon yok — scripts/install-audio-driver.sh çalıştırın "
		       "(veya brew install blackhole-2ch).";
	}
	if (running_) {
		return std::string("Köprü açık → ses \"") + name +
		       "\" cihazına gidiyor. WhatsApp mikrofonu: " + name;
	}
	return std::string("Hazır: \"") + name +
	       "\". Köprüyü açın, sonra WhatsApp’ta bu mikrofonu seçin.";
}

} // namespace obs_whatsapp_bridge
