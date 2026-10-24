#!/usr/bin/env luajit
--[[
  Mock OBS Lua API and load whatsapp-bridge.lua to verify script_properties
  does not throw on obs_enum_audio_monitoring_devices arity.
]]

local script_path = arg[1] or "./whatsapp-bridge.lua"

-- Minimal OBS mock matching Lua bindings
local devices = {
	{ name = "MacBook Pro Microphone", id = "BuiltInMic" },
	{ name = "BlackHole 2ch", id = "BlackHole2ch_UID" },
	{ name = "OBS Bridge Mic", id = "OBSBridgeMic_UID" },
}

package.preload["obslua"] = function()
	local M = {}
	M.LOG_INFO = 300
	M.OBS_COMBO_TYPE_LIST = 1
	M.OBS_COMBO_FORMAT_STRING = 0
	M.OBS_SOURCE_AUDIO = 2
	M.OBS_MONITORING_TYPE_NONE = 0
	M.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT = 2

	function M.script_log(level, msg)
		print("[log]", msg)
	end

	-- Real binding: (cb, data) — cb(data, name, id)
	function M.obs_enum_audio_monitoring_devices(cb, data)
		assert(cb ~= nil and data ~= nil, "expected 2..2 args, got " .. tostring((cb and 1 or 0) + (data and 1 or 0)))
		for _, d in ipairs(devices) do
			if not cb(data, d.name, d.id) then
				break
			end
		end
	end

	function M.obs_audio_monitoring_available()
		return true
	end

	function M.obs_set_audio_monitoring_device(name, id)
		print("[set_monitor]", name, id)
		return true
	end

	function M.obs_enum_sources()
		return {}
	end

	function M.source_list_release() end

	function M.obs_properties_create()
		return { props = {} }
	end

	function M.obs_properties_add_list(props, id, label, a, b)
		local list = { items = {} }
		table.insert(props.props, { id = id, list = list })
		return list
	end

	function M.obs_property_list_add_string(list, label, value)
		table.insert(list.items, { label = label, value = value })
		print("[list+]", label, "=>", value)
	end

	function M.obs_properties_add_bool(props, id, label)
		table.insert(props.props, { id = id, type = "bool", label = label })
	end

	function M.obs_properties_add_button(props, id, label, cb)
		table.insert(props.props, { id = id, type = "button", label = label, cb = cb })
	end

	function M.obs_data_set_default_bool() end
	function M.obs_data_get_string()
		return ""
	end
	function M.obs_data_get_bool()
		return false
	end

	function M.obs_frontend_virtualcam_active()
		return false
	end
	function M.obs_frontend_start_virtualcam()
		print("[vcam] start")
	end

	return M
end

obslua = require("obslua")

-- Load script as chunk in global env (OBS style)
local chunk, err = loadfile(script_path)
if not chunk then
	io.stderr:write("loadfile failed: " .. tostring(err) .. "\n")
	os.exit(1)
end
chunk()

print("--- script_description ---")
print(script_description())

print("--- script_properties ---")
local props = script_properties()
assert(props, "script_properties returned nil")

-- Find device list
local list
for _, p in ipairs(props.props) do
	if p.list then
		list = p.list
		break
	end
end
assert(list, "no device list")
assert(#list.items >= 1, "expected at least one device entry")

local has_bh = false
for _, it in ipairs(list.items) do
	if it.label:find("BlackHole", 1, true) or it.label:find("OBS Bridge", 1, true) then
		has_bh = true
	end
end
assert(has_bh, "expected BlackHole or OBS Bridge in list")

print("--- click Ses köprüsünü aç ---")
for _, p in ipairs(props.props) do
	if p.id == "btn_start" then
		p.cb()
	end
end

print("OK: mock test passed")
