--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- MP-Event für ein vom Spieler geändertes Verteilziel (siehe revamp_distribution.lua).
-- Aufbau nach Vanillas ProductionPointProductionStateEvent: der Client schickt die Änderung an den Server, der sie an alle übrigen Clients weiterverteilt.
--
-- Das Ziel geht als Placeable-Objekt über die Leitung und nicht als uniqueId: die Id vergibt jeder Rechner für sich, Server und Client führen dasselbe Gebäude unter verschiedenen Ids.
-- Der Empfänger übersetzt das Objekt deshalb in seine eigene Id zurück, bevor er es ablegt.

Revamp_EventDistribution = {}
local Revamp_EventDistribution_mt = Class(Revamp_EventDistribution, Event)
InitEventClass(Revamp_EventDistribution, "Revamp_EventDistribution")

---Erzeugt ein leeres Event für die Netzwerk-Deserialisierung (readStream befüllt die Felder danach).
---@return table self Neue, noch unbefüllte Revamp_EventDistribution-Instanz
function Revamp_EventDistribution.emptyNew()
	return Event.new(Revamp_EventDistribution_mt)
end

---Erzeugt ein versandfertiges Event für eine geänderte Ziel-Einstellung.
---@param productionPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@param targetPlaceable table Placeable der Produktionsstätte, die beliefert werden soll
---@param level string Verteilstufe aus Revamp.DISTRIBUTION_LEVELS
---@param limit? number Obergrenze in Litern, nil für unbegrenzt
---@return table self Versandfertige Revamp_EventDistribution-Instanz
function Revamp_EventDistribution.new(productionPoint, fillTypeIndex, targetPlaceable, level, limit)
	local self = Revamp_EventDistribution.emptyNew()
	self.productionPoint = productionPoint
	self.fillTypeIndex = fillTypeIndex
	self.targetPlaceable = targetPlaceable
	self.level = level
	self.limit = limit
	return self
end

---Liest das Event vom Netzwerk-Stream und führt es sofort aus.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventDistribution:readStream(streamId, connection)
	self.productionPoint = NetworkUtil.readNodeObject(streamId)
	-- Nicht Vanillas feste 8 Bit: revamp_changeLimits.lua hebt FillTypeManager.SEND_NUM_BITS an, damit über 255 Fülltypen überhaupt möglich sind.
	self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
	self.targetPlaceable = NetworkUtil.readNodeObject(streamId)
	self.level = Revamp.DISTRIBUTION_LEVELS[streamReadUInt8(streamId)]
	if streamReadBool(streamId) then
		self.limit = streamReadInt32(streamId)
	end
	self:run(connection)
end

---Schreibt das Event auf den Netzwerk-Stream.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventDistribution:writeStream(streamId, connection) ---@diagnostic disable-line: unused-local
	NetworkUtil.writeNodeObject(streamId, self.productionPoint)
	streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
	NetworkUtil.writeNodeObject(streamId, self.targetPlaceable)
	streamWriteUInt8(streamId, Revamp.getDistributionLevelIndex(self.level))
	if streamWriteBool(streamId, self.limit ~= nil) then
		streamWriteInt32(streamId, self.limit)
	end
end

---Wendet die Änderung an und verteilt sie als Server an alle übrigen Clients weiter.
---@param connection table Netzwerkverbindung
function Revamp_EventDistribution:run(connection)
	if not connection:getIsServer() then
		g_server:broadcastEvent(self, false, connection)
	end

	-- Beides kann fehlen, wenn das betroffene Gebäude auf diesem Rechner in der Zwischenzeit verschwunden ist.
	if self.productionPoint == nil or self.targetPlaceable == nil then
		return
	end

	Revamp.DebugText("Revamp_EventDistribution: %s -> %s level=%s limit=%s empfangen", g_fillTypeManager:getFillTypeNameByIndex(self.fillTypeIndex), self.targetPlaceable:getName(), tostring(self.level), tostring(self.limit))

	-- Die eigene Ablage-Funktion statt ProductionPoint:setDistributionTarget, weil hier das Placeable vorliegt und nichts erneut verschickt werden soll.
	Revamp.storeDistributionTarget(self.productionPoint, self.fillTypeIndex, self.targetPlaceable:getUniqueId(), self.level, self.limit)
end

---Verschickt eine geänderte Ziel-Einstellung: als Server an alle Clients, als Client an den Server.
---@param productionPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@param targetPlaceable table Placeable der Produktionsstätte, die beliefert werden soll
---@param level string Verteilstufe aus Revamp.DISTRIBUTION_LEVELS
---@param limit? number Obergrenze in Litern, nil für unbegrenzt
---@param noEventSend? boolean true, wenn die Änderung selbst schon aus einem Event stammt
function Revamp_EventDistribution.sendEvent(productionPoint, fillTypeIndex, targetPlaceable, level, limit, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(Revamp_EventDistribution.new(productionPoint, fillTypeIndex, targetPlaceable, level, limit))
			return
		end
		g_client:getServerConnection():sendEvent(Revamp_EventDistribution.new(productionPoint, fillTypeIndex, targetPlaceable, level, limit))
	end
end
