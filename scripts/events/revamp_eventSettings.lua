--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- MP-Event für den kompletten Stand der globalen Einstellungen (siehe revamp_settings.lua), immer vom Server an die Clients.
-- Es geht an einen beitretenden Spieler und nach jeder Änderung an alle - genauso wie Vanilla seine eigenen Spielstand-Einstellungen mit SavegameSettingsEvent verteilt.
--
-- Übertragen wird nicht der Wert selbst, sondern der Zustand seines Bedienelements: damit reicht für jede Einstellung ein Byte, egal ob dahinter eine Auswahl oder ein Faktor steht.

Revamp_EventSettings = {}
local Revamp_EventSettings_mt = Class(Revamp_EventSettings, Event)
InitEventClass(Revamp_EventSettings, "Revamp_EventSettings")

---Erzeugt ein leeres Event für die Netzwerk-Deserialisierung (readStream befüllt die Felder danach).
---@return table self Neue, noch unbefüllte Revamp_EventSettings-Instanz
function Revamp_EventSettings.emptyNew()
	return Event.new(Revamp_EventSettings_mt)
end

---Erzeugt ein versandfertiges Event.
---Die Werte holt es sich beim Schreiben selbst aus den aktuellen Einstellungen, es gibt hier deshalb nichts mitzugeben.
---@return table self Versandfertige Revamp_EventSettings-Instanz
function Revamp_EventSettings.new()
	return Revamp_EventSettings.emptyNew()
end

---Liest das Event vom Netzwerk-Stream und führt es sofort aus.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventSettings:readStream(streamId, connection)
	self.states = {}
	for _, definition in ipairs(Revamp.SETTINGS) do
		self.states[definition.id] = streamReadUInt8(streamId)
	end
	self:run(connection)
end

---Schreibt das Event auf den Netzwerk-Stream.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventSettings:writeStream(streamId, connection) ---@diagnostic disable-line: unused-local
	for _, definition in ipairs(Revamp.SETTINGS) do
		streamWriteUInt8(streamId, Revamp.getSettingState(definition, Revamp.settings[definition.id]))
	end
end

---Übernimmt den empfangenen Stand auf dem Client.
---@param connection table Netzwerkverbindung
function Revamp_EventSettings:run(connection) ---@diagnostic disable-line: unused-local
	for id, state in pairs(self.states) do
		Revamp.setSetting(id, Revamp.getSettingValueFromState(Revamp.settingsById[id], state))
	end
end

---Schickt den aktuellen Stand an alle verbundenen Clients.
function Revamp_EventSettings.sendToClients()
	if g_server ~= nil then
		g_server:broadcastEvent(Revamp_EventSettings.new(), false)
	end
end
