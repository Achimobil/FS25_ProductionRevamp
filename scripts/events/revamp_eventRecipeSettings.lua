-- MP-Event für die vom Spieler geänderten Auswahlmodi einer Rezeptlinie (siehe revamp_recipeSettings.lua).
-- Aufbau nach Vanillas ProductionPointProductionStateEvent: der Client schickt die Änderung an den Server, der sie an alle übrigen Clients weiterverteilt.

Revamp_EventRecipeSettings = {}
local Revamp_EventRecipeSettings_mt = Class(Revamp_EventRecipeSettings, Event)
InitEventClass(Revamp_EventRecipeSettings, "Revamp_EventRecipeSettings")

---Erzeugt ein leeres Event für die Netzwerk-Deserialisierung (readStream befüllt die Felder danach).
---@return table self Neue, noch unbefüllte Revamp_EventRecipeSettings-Instanz
function Revamp_EventRecipeSettings.emptyNew()
	return Event.new(Revamp_EventRecipeSettings_mt)
end

---Erzeugt ein versandfertiges Event für eine Modus-Änderung.
---@param productionPoint table ProductionPoint-Instanz, zu der die Rezeptlinie gehört
---@param productionId string Id der Rezeptlinie
---@param mixMode? string Neuer Mix-Modus, nil wenn unverändert
---@param boostMode? string Neuer Booster-Modus, nil wenn unverändert
---@return table self Versandfertige Revamp_EventRecipeSettings-Instanz
function Revamp_EventRecipeSettings.new(productionPoint, productionId, mixMode, boostMode)
	local self = Revamp_EventRecipeSettings.emptyNew()
	self.productionPoint = productionPoint
	self.productionId = productionId
	self.mixMode = mixMode
	self.boostMode = boostMode
	return self
end

---Liest das Event vom Netzwerk-Stream und führt es sofort aus.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventRecipeSettings:readStream(streamId, connection)
	self.productionPoint = NetworkUtil.readNodeObject(streamId)
	self.productionId = streamReadString(streamId)
	-- Modus 0 steht für "unverändert": ein Umschalten betrifft immer nur eine der beiden Einstellungen.
	local mixIndex = streamReadUInt8(streamId)
	local boostIndex = streamReadUInt8(streamId)
	self.mixMode = Revamp.SELECTION_MODES[mixIndex]
	self.boostMode = Revamp.SELECTION_MODES[boostIndex]
	self:run(connection)
end

---Schreibt das Event auf den Netzwerk-Stream.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventRecipeSettings:writeStream(streamId, connection) ---@diagnostic disable-line: unused-local
	NetworkUtil.writeNodeObject(streamId, self.productionPoint)
	streamWriteString(streamId, self.productionId)
	streamWriteUInt8(streamId, self.mixMode ~= nil and Revamp.getSelectionModeIndex(self.mixMode) or 0)
	streamWriteUInt8(streamId, self.boostMode ~= nil and Revamp.getSelectionModeIndex(self.boostMode) or 0)
end

---Wendet die Änderung an und verteilt sie als Server an alle übrigen Clients weiter.
---@param connection table Netzwerkverbindung
function Revamp_EventRecipeSettings:run(connection)
	if not connection:getIsServer() then
		g_server:broadcastEvent(self, false, connection)
	end
	if self.productionPoint ~= nil then
		self.productionPoint:setRecipeSelectionModes(self.productionId, self.mixMode, self.boostMode, true)
	end
end

---Verschickt eine Modus-Änderung: als Server an alle Clients, als Client an den Server.
---@param productionPoint table ProductionPoint-Instanz, zu der die Rezeptlinie gehört
---@param productionId string Id der Rezeptlinie
---@param mixMode? string Neuer Mix-Modus, nil wenn unverändert
---@param boostMode? string Neuer Booster-Modus, nil wenn unverändert
---@param noEventSend? boolean true, wenn die Änderung selbst schon aus einem Event stammt
function Revamp_EventRecipeSettings.sendEvent(productionPoint, productionId, mixMode, boostMode, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(Revamp_EventRecipeSettings.new(productionPoint, productionId, mixMode, boostMode))
			return
		end
		g_client:getServerConnection():sendEvent(Revamp_EventRecipeSettings.new(productionPoint, productionId, mixMode, boostMode))
	end
end
