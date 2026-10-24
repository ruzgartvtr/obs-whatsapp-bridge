--[[
  OBS WhatsApp Bridge (Lua)
  OBS program / kaynak sesini BlackHole veya OBS Bridge Mic'e yönlendirir.

  Kurulum: Tools → Scripts → + → bu dosyayı seçin
  Repo: https://github.com/ruzgartvtr/obs-whatsapp-bridge
]]

local obs = obslua

local OPT_DEVICE = "monitor_device"
local OPT_AUTO = "auto_enable"
local bridge_on = false
local selected_id = ""
local selected_name = ""

-- Known loopback devices (name + typical CoreAudio / driver UID)
local KNOWN_MICS = {
	{ name = "BlackHole 2ch", id = "BlackHole2ch_UID", score = 2 },
	{ name = "BlackHole 16ch", id = "BlackHole16ch_UID", score = 1 },
	{ name = "OBS Bridge Mic", id = "OBSBridgeMic_UID", score = 3 },
	{ name = "OBSBridgeMic", id = "OBSBridgeMic_UID", score = 3 },
}

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
	if name == nil or name == "" then
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

local function sort_mics(found)
	table.sort(found, function(a, b)
		return (a.score or 0) > (b.score or 0)
	end)
	return found
end

-- Try SWIG binding (works on some OBS builds if arity is correct)
local function enum_via_swig()
	local found = {}
	if type(obs.obs_enum_audio_monitoring_devices) ~= "function" then
		return nil, "api missing"
	end
	local function cb(data, name, id)
		if type(data) == "string" then
			-- swapped / 1-arg style
			name, id, data = data, name, found
		end
		if type(data) ~= "table" then
			data = found
		end
		if name_is_virtual_mic(name) then
			table.insert(data, {
				name = tostring(name),
				id = tostring(id or ""),
				score = preferred_score(name),
			})
		end
		return true
	end
	local ok, err = pcall(obs.obs_enum_audio_monitoring_devices, cb, found)
	if not ok then
		return nil, err
	end
	return found, nil
end

-- LuaJIT FFI against already-loaded libobs (process symbols)
local function enum_via_ffi()
	local ok_ffi, ffi = pcall(require, "ffi")
	if not ok_ffi then
		return nil, "no ffi"
	end

	local ok_cdef = pcall(function()
		ffi.cdef[[
			typedef bool (*obs_enum_audio_device_cb)(void *data, const char *name, const char *id);
			void obs_enum_audio_monitoring_devices(obs_enum_audio_device_cb cb, void *data);
		]]
	end)
	-- cdef may fail if already defined; ignore

	local found = {}
	local function collector(data, name, id)
		if name == nil then
			return true
		end
		local n = ffi.string(name)
		local i = id ~= nil and ffi.string(id) or ""
		if name_is_virtual_mic(n) then
			table.insert(found, { name = n, id = i, score = preferred_score(n) })
		end
		return true
	end

	local cb = ffi.cast("obs_enum_audio_device_cb", collector)
	-- Prevent GC while calling
	local keep = cb

	local ok_call, err = pcall(function()
		-- Prefer symbols already mapped into the OBS process
		ffi.C.obs_enum_audio_monitoring_devices(cb, nil)
	end)
	if not ok_call then
		-- Try explicit lib names
		local libs = { "obs", "libobs.so.0", "libobs.0.dylib", "libobs.dylib" }
		local loaded = false
		for _, name in ipairs(libs) do
			local ok_load, lib = pcall(ffi.load, name)
			if ok_load and lib.obs_enum_audio_monitoring_devices then
				local ok2, err2 = pcall(function()
					lib.obs_enum_audio_monitoring_devices(cb, nil)
				end)
				if ok2 then
					loaded = true
					break
				end
				err = err2
			end
		end
		if not loaded then
			cb:free()
			return nil, tostring(err)
		end
	end

	cb:free()
	return found, nil
end

local function find_virtual_mics()
	-- 1) SWIG
	local found, err = enum_via_swig()
	if found and #found > 0 then
		log("cihaz listesi: SWIG (" .. #found .. ")")
		return sort_mics(found)
	end
	if err then
		log("SWIG enum: " .. tostring(err))
	end

	-- 2) FFI
	found, err = enum_via_ffi()
	if found and #found > 0 then
		log("cihaz listesi: FFI (" .. #found .. ")")
		return sort_mics(found)
	end
	if err then
		log("FFI enum: " .. tostring(err))
	end

	-- 3) Hardcoded known loopbacks (always works for UI)
	log("cihaz listesi: bilinen varsayılanlar (BlackHole / OBS Bridge Mic)")
	local copy = {}
	for _, m in ipairs(KNOWN_MICS) do
		copy[#copy + 1] = { name = m.name, id = m.id, score = m.score }
	end
	return sort_mics(copy)
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
	end
	obs.source_list_release(sources)
end

local function start_bridge(device_name, device_id)
	if obs.obs_audio_monitoring_available and not obs.obs_audio_monitoring_available() then
		log("Bu OBS derlemesinde audio monitoring yok.")
		return false
	end
	if device_name == nil or device_name == "" then
		local mics = find_virtual_mics()
		if #mics == 0 then
			log("Sanal mikrofon yok.")
			return false
		end
		device_name = mics[1].name
		device_id = mics[1].id
	end
	if device_id == nil or device_id == "" then
		device_id = device_name
	end

	local ok = obs.obs_set_audio_monitoring_device(device_name, device_id)
	if not ok then
		-- Retry with name as id (some builds accept that)
		ok = obs.obs_set_audio_monitoring_device(device_name, device_name)
	end
	if not ok then
		log("Monitoring ayarlanamadı: " .. tostring(device_name) .. " / " .. tostring(device_id))
		log("OBS → Settings → Audio → Advanced → Monitoring Device ile BlackHole seçip tekrar deneyin.")
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
<p><a href="https://github.com/ruzgartvtr/obs-whatsapp-bridge">github.com/ruzgartvtr/obs-whatsapp-bridge</a></p>]]
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

	local ok, mics = pcall(find_virtual_mics)
	if not ok then
		log("find_virtual_mics hata: " .. tostring(mics))
		mics = {}
		for _, m in ipairs(KNOWN_MICS) do
			mics[#mics + 1] = m
		end
	end

	for _, m in ipairs(mics) do
		obs.obs_property_list_add_string(list, m.name, m.name .. "\t" .. m.id)
	end

	obs.obs_properties_add_bool(props, OPT_AUTO, "OBS açılınca köprüyü otomatik aç")

	obs.obs_properties_add_button(props, "btn_start", "Ses köprüsünü aç", function()
		if selected_name ~= "" then
			start_bridge(selected_name, selected_id)
		else
			start_bridge(nil, nil)
		end
		return true
	end)

	obs.obs_properties_add_button(props, "btn_stop", "Ses köprüsünü kapat", function()
		stop_bridge()
		return true
	end)

	obs.obs_properties_add_button(props, "btn_vcam", "Sanal kamerayı başlat", function()
		if obs.obs_frontend_virtualcam_active and obs.obs_frontend_start_virtualcam then
			if not obs.obs_frontend_virtualcam_active() then
				obs.obs_frontend_start_virtualcam()
				log("Virtual Camera başlatıldı")
			else
				log("Virtual Camera zaten açık")
			end
		else
			log("Virtual Camera API yok — OBS Controls’tan Start Virtual Camera kullanın")
		end
		return true
	end)

	return props
end

function script_defaults(settings)
	obs.obs_data_set_default_bool(settings, OPT_AUTO, false)
	-- Default to BlackHole 2ch
	obs.obs_data_set_default_string(settings, OPT_DEVICE, "BlackHole 2ch\tBlackHole2ch_UID")
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
		start_bridge(selected_name ~= "" and selected_name or nil, selected_id)
	end
end

function script_load(settings)
	log("yüklendi — Tools → Scripts → WhatsApp Bridge")
	local ok, mics = pcall(find_virtual_mics)
	if ok then
		log("self-test OK — aday cihaz: " .. tostring(#mics))
		for i, m in ipairs(mics) do
			if i <= 5 then
				log("  • " .. m.name .. " [" .. m.id .. "]")
			end
		end
	else
		log("self-test FAIL: " .. tostring(mics))
	end
	-- Exercise the same path OBS uses when Scripts panel opens
	local ok_props, props_or_err = pcall(script_properties)
	if ok_props then
		log("script_properties OK")
	else
		log("script_properties FAIL: " .. tostring(props_or_err))
	end
	script_update(settings)
end

function script_unload()
	if bridge_on then
		stop_bridge()
	end
end
