--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- MP-Event fürs Abgeben von Tieren an einem Tier-Trigger (siehe revamp_animals.lua).
--
-- Über die Leitung gehen nur die Nummer des Triggers und die Id der Tiergruppe: die Node-Id des Triggers ist auf jedem Rechner
-- eine andere, und Gesundheit, Alter und Mastbonus nimmt der Server aus seiner eigenen Tiergruppe statt aus dem Event.

Revamp_EventMoveAnimals = {}
local Revamp_EventMoveAnimals_mt = Class(Revamp_EventMoveAnimals, Event)
InitEventClass(Revamp_EventMoveAnimals, "Revamp_EventMoveAnimals")

---Erzeugt ein leeres Event für die Netzwerk-Deserialisierung (readStream befüllt die Felder danach).
---@return table self Neue, noch unbefüllte Revamp_EventMoveAnimals-Instanz
function Revamp_EventMoveAnimals.emptyNew()
	return Event.new(Revamp_EventMoveAnimals_mt)
end

---Erzeugt ein versandfertiges Abgabe-Event.
---@param productionPoint table ProductionPoint-Instanz, an der abgegeben wird
---@param triggerIndex number Nummer des Triggers innerhalb der Produktionsstätte
---@param clusterId number Id der Tiergruppe im Transporter
---@param numAnimals number Anzahl abgegebener Tiere
---@return table self Versandfertige Revamp_EventMoveAnimals-Instanz
function Revamp_EventMoveAnimals.new(productionPoint, triggerIndex, clusterId, numAnimals)
	local self = Revamp_EventMoveAnimals.emptyNew()
	self.productionPoint = productionPoint
	self.triggerIndex = triggerIndex
	self.clusterId = clusterId
	self.numAnimals = numAnimals
	return self
end

---Liest das Event vom Netzwerk-Stream und führt es sofort aus.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventMoveAnimals:readStream(streamId, connection)
	self.productionPoint = NetworkUtil.readNodeObject(streamId)
	self.triggerIndex = streamReadUInt8(streamId)
	self.clusterId = streamReadInt32(streamId)
	self.numAnimals = streamReadUIntN(streamId, AnimalCluster.NUM_BITS_NUM_ANIMALS)
	self:run(connection)
end

---Schreibt das Event auf den Netzwerk-Stream.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventMoveAnimals:writeStream(streamId, connection) ---@diagnostic disable-line: unused-local
	NetworkUtil.writeNodeObject(streamId, self.productionPoint)
	streamWriteUInt8(streamId, self.triggerIndex)
	streamWriteInt32(streamId, self.clusterId)
	streamWriteUIntN(streamId, self.numAnimals, AnimalCluster.NUM_BITS_NUM_ANIMALS)
end

---Führt die Abgabe serverseitig aus.
---@param connection table Netzwerkverbindung
function Revamp_EventMoveAnimals:run(connection)
	self.productionPoint:ReceiveMoveAnimalsEvent(self.triggerIndex, self.clusterId, self.numAnimals, connection)
end

---Baut ein Abgabe-Event und schickt es an den Server.
---@param productionPoint table ProductionPoint-Instanz, an der abgegeben wird
---@param triggerIndex number Nummer des Triggers innerhalb der Produktionsstätte
---@param clusterId number Id der Tiergruppe im Transporter
---@param numAnimals number Anzahl abgegebener Tiere
function Revamp_EventMoveAnimals.sendEvent(productionPoint, triggerIndex, clusterId, numAnimals)
	g_client:getServerConnection():sendEvent(Revamp_EventMoveAnimals.new(productionPoint, triggerIndex, clusterId, numAnimals))
end
