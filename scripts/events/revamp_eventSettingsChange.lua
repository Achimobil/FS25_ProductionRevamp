-- MP-Event für eine einzelne, von einem Admin im Einstellungsmenü geänderte Einstellung (siehe revamp_settings.lua), immer vom Client an den Server.
-- Der Server prüft die Adminrechte, übernimmt die Änderung und schickt danach den kompletten Stand an alle zurück (Revamp_EventSettings) -
-- so steht auf jedem Rechner das, was der Server tatsächlich übernommen hat, und nicht das, was ein Client gerne hätte.

Revamp_EventSettingsChange = {}
local Revamp_EventSettingsChange_mt = Class(Revamp_EventSettingsChange, Event)
InitEventClass(Revamp_EventSettingsChange, "Revamp_EventSettingsChange")

---Erzeugt ein leeres Event für die Netzwerk-Deserialisierung (readStream befüllt die Felder danach).
---@return table self Neue, noch unbefüllte Revamp_EventSettingsChange-Instanz
function Revamp_EventSettingsChange.emptyNew()
	return Event.new(Revamp_EventSettingsChange_mt)
end

---Erzeugt ein versandfertiges Event für eine geänderte Einstellung.
---@param settingId string Id der Einstellung
---@param state number Neuer Zustand ihres Bedienelements
---@return table self Versandfertige Revamp_EventSettingsChange-Instanz
function Revamp_EventSettingsChange.new(settingId, state)
	local self = Revamp_EventSettingsChange.emptyNew()
	self.settingId = settingId
	self.state = state
	return self
end

---Liest das Event vom Netzwerk-Stream und führt es sofort aus.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventSettingsChange:readStream(streamId, connection)
	self.settingId = streamReadString(streamId)
	self.state = streamReadUInt8(streamId)
	self:run(connection)
end

---Schreibt das Event auf den Netzwerk-Stream.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventSettingsChange:writeStream(streamId, connection) ---@diagnostic disable-line: unused-local
	streamWriteString(streamId, self.settingId)
	streamWriteUInt8(streamId, self.state)
end

---Übernimmt die Änderung serverseitig und verteilt den neuen Stand an alle Clients.
---@param connection table Netzwerkverbindung des Clients, der die Änderung ausgelöst hat
function Revamp_EventSettingsChange:run(connection)
	-- Die eigentliche Sperre, nicht nur das ausgeblendete Menü auf dem Client: ohne Adminrechte könnte sonst jeder die Einstellungen des Servers umstellen.
	if not g_currentMission.userManager:getIsConnectionMasterUser(connection) then
		Revamp.DebugText("Revamp_EventSettingsChange:run(): Änderung an %s ohne Adminrechte abgelehnt", tostring(self.settingId))
		return
	end

	local definition = Revamp.settingsById[self.settingId]
	if definition == nil then
		return
	end

	Revamp.setSetting(self.settingId, Revamp.getSettingValueFromState(definition, self.state))
	Revamp_EventSettings.sendToClients()
end
