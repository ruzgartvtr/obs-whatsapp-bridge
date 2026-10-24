--[[
  OBS WhatsApp Bridge (Lua)
  OBS program / kaynak sesini BlackHole veya OBS Bridge Mic'e yönlendirir;
  böylece WhatsApp görüntülü aramada sahne sesi duyulur.

  Kurulum: Tools → Scripts → + → bu dosyayı seçin
  Repo: https://github.com/ruzgartvtr/obs-whatsapp-bridge
]]

local obs = obslua

local OPT_DEVICE = "monitor_device"
local OPT_AUTO = "auto_enable"
local bridge_on = false
local selected_id = ""
local selected_name = ""

local VIRTUAL_MIC_PATTERNS = {
	"OBS Bridge Mic",
	"OBSBridgeMic",
	"BlackHole 2ch",
	"BlackHole 16ch",
	"BlackHole",
}

local function log(msg)
	obs.script_log(obs.LOG_INFO, "[whatsapp-bridge] " .. tostring(msg))
end

local function name_is_virtual_mic(name)
	if name == nil then
		return false
	end
	for _, pat in ipairs(VIRTUAL_MIC_PATTERNS) do
		if string.find(name, pat, 1, true) then
			return true
		end
	end
	return false
end

local function preferred_score(name)
	if string.find(name, "OBS Bridge", 1, true) or string.find(name, "OBSBridge", 1, true) then
		return 3
	end
	if string.find(name, "BlackHole 2ch", 1, true) then
		return 2
	end
	if string.find(name, "BlackHole", 1, true) then
		return 1
	end
	return 0
end

-- Collect monitoring devices matching virtual-mic names.
-- Lua binding requires (callback, data); callback is (data, name, id).
local function find_virtual_mics()
	local found = {}
	local function cb(data, name, id)
		if name_is_virtual_mic(name) then
			table.insert(data, { name = name, id = id, score = preferred_score(name) })
		end
		return true
	end	obs.obs_enum_audio_monitoring_devices(cb, found)
	table.sort(found, function(a, b)
		return a.score > b.score
	end)
	return found
end

local function source_has_audio(source)
	local flags = obs.obs_source_get_output_flags(source)
	local audio = obs.OBS_SOURCE_AUDIO
	if bit32 and bit32.band then
		return bit32.band(flags, audio) ~= 0
	end
	if bit and bit.band then
		return bit.band(flags, audio) ~= 0
	end
	-- Fallback: try enabling; non-audio sources ignore monitoring
	return true
end

local function set_all_sources_monitoring(enable)
	local sources = obs.obs_enum_sources()
	if sources == nil then
		return
	end
	for _, source in ipairs(sources) do
		if source_has_audio(source) then
			if enable then
				obs.obs_source_set_monitoring_type(source, obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT)
			else
				obs.obs_source_set_monitoring_type(source, obs.OBS_MONITORING_TYPE_NONE)
			end
		end
	end	obs.source_list_release(sources)
end

local function start_bridge(device_name, device_id)
	if not obs.obs_audio_monitoring_available() then
		log("Bu OBS derlemesinde audio monitoring yok.")
		return false
	end
	if device_name == nil or device_id == nil or device_name == "" or device_id == "" then
		local mics = find_virtual_mics()
		if #mics == 0 then
			log("Sanal mikrofon bulunamadı. install.sh ile BlackHole kurun.")
			return false
		end
		device_name = mics[1].name
		device_id = mics[1].id
	end
	local ok = obs.obs_set_audio_monitoring_device(device_name, device_id)
	if not ok then
		log("Monitoring cihazı ayarlanamadı: " .. tostring(device_name))
		return false
	end
	set_all_sources_monitoring(true)
	bridge_on = true
	selected_name = device_name
	selected_id = device_id
	log("Ses köprüsü AÇIK → " .. device_name)
	return true
end

local function stop_bridge()
	set_all_sources_monitoring(false)
	bridge_on = false
	log("Ses köprüsü KAPALI")
end

------------------------------------------------------------
-- Script UI
------------------------------------------------------------

function script_description()
	return [[<h2>WhatsApp Bridge</h2>
<p>OBS sahne sesini <b>BlackHole</b> / <b>OBS Bridge Mic</b> sanal mikrofonuna yollar.
WhatsApp görüntülü aramada mikrofon olarak bu cihazı seçin; kamera olarak
<b>OBS Virtual Camera</b> kullanın.</p>
<p>Kurulum: <code>https://github.com/ruzgartvtr/obs-whatsapp-bridge</code></p>]]
end

function script_properties()
	local props = obs.obs_properties_create()

	local list = obs.obs_properties_add_list(
		props,
		OPT_DEVICE,
		"Sanal mikrofon (monitoring)",
		obs.OBS_COMBO_TYPE_LIST,
		obs.OBS_COMBO_FORMAT_STRING
	)

	local mics = find_virtual_mics()
	if #mics == 0 then
	obs.obs_property_list_add_string(list, "(Sanal mikrofon yok — install.sh çalıştırın)", "")
	else
		for _, m in ipairs(mics) do
			-- value = "name\tid" so we can restore both
			obs.obs_property_list_add_string(list, m.name, m.name .. "\t" .. m.id)
		end
	end

	obs.obs_properties_add_bool(props, OPT_AUTO, "OBS açılınca köprüyü otomatik aç")

	obs.obs_properties_add_button(props, "btn_start", "Ses köprüsünü aç", function()
		local settings = obs.obs_data_create()
		-- button callback receives (props, prop) in some versions; use selected globals
		local raw = selected_name ~= "" and (selected_name .. "\t" .. selected_id) or nil
		if raw == nil then
			local mics2 = find_virtual_mics()
			if #mics2 > 0 then
				start_bridge(mics2[1].name, mics2[1].id)
			else
				start_bridge(nil, nil)
			end
		else
			local name, id = raw:match("([^\t]+)\t(.+)")
			start_bridge(name, id)
		end
	obs.obs_data_release(settings)
		return true
	end)

	obs.obs_properties_add_button(props, "btn_stop", "Ses köprüsünü kapat", function()
		stop_bridge()
		return true
	end)

	obs.obs_properties_add_button(props, "btn_vcam", "Sanal kamerayı başlat", function()
		if not obs.obs_frontend_virtualcam_active() then
			obs.obs_frontend_start_virtualcam()
			log("Virtual Camera başlatıldı")
		else
			log("Virtual Camera zaten açık")
		end
		return true
	end)

	return props
end

function script_defaults(settings)
	obs.obs_data_set_default_bool(settings, OPT_AUTO, false)
end

function script_update(settings)
	local raw = obs.obs_data_get_string(settings, OPT_DEVICE)
	if raw and raw ~= "" then
		local name, id = raw:match("([^\t]+)\t(.+)")
		if name and id then
			selected_name = name
			selected_id = id
		end
	end
	if obs.obs_data_get_bool(settings, OPT_AUTO) and not bridge_on then
		if selected_name ~= "" then
			start_bridge(selected_name, selected_id)
		else
			start_bridge(nil, nil)
		end
	end
end

function script_load(settings)
	log("yüklendi — Tools → Scripts → WhatsApp Bridge")
	script_update(settings)
end

function script_unload()
	if bridge_on then
		stop_bridge()
	end
end
