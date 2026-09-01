--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- MP-Event fürs Auslagern (siehe revamp_spawner.lua), byte-nah portiert aus PSCs
-- productionStorageControl_event_spawn.lua.

Revamp_EventSpawn = {}
local Revamp_EventSpawn_mt = Class(Revamp_EventSpawn, Event)
InitEventClass(Revamp_EventSpawn, "Revamp_EventSpawn")

---Erzeugt ein leeres Event für die Netzwerk-Deserialisierung (readStream befüllt die Felder danach).
---@return table self Neue, noch unbefüllte Revamp_EventSpawn-Instanz
function Revamp_EventSpawn.emptyNew()
	return Event.new(Revamp_EventSpawn_mt)
end

---Erzeugt ein versandfertiges Spawn-Event mit allen zum Spawnen nötigen Angaben.
---@param productionPoint table ProductionPoint-Instanz, die das Objekt spawnen soll
---@param ownerFarmId number Farm, der das gespawnte Objekt gehören soll
---@param fillTypeIndex number FillType-Index
---@param pendingLiters number Noch aus dem Lager abzuziehende Literzahl
---@param width number Breite des zu spawnenden Objekts
---@param height number Höhe des zu spawnenden Objekts
---@param length number Länge des zu spawnenden Objekts
---@param capacity number Kapazität einer Verpackungseinheit
---@param type number Verpackungstyp (siehe ProductionPoint:ReceiveSpawnEvent)
---@param customEnvironment? string Custom-Environment-Name der Verpackung, falls modeigen
---@param treeId? number Baumtyp-Index bei Baumsetzlings-Paletten
---@param amount number Anzahl zu spawnender Objekte
---@param color1 number Foliencolor-Komponente 1
---@param color2 number Foliencolor-Komponente 2
---@param color3 number Foliencolor-Komponente 3
---@return table self Versandfertige Revamp_EventSpawn-Instanz
function Revamp_EventSpawn.new(productionPoint, ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type, customEnvironment, treeId, amount, color1, color2, color3)
	local self = Revamp_EventSpawn.emptyNew()
	self.productionPoint = productionPoint
	self.ownerFarmId = ownerFarmId
	self.fillTypeIndex = fillTypeIndex
	self.pendingLiters = pendingLiters
	self.width = width
	self.height = height
	self.length = length
	self.capacity = capacity
	self.type = type
	self.customEnvironment = customEnvironment
	self.treeId = treeId
	self.amount = amount
	self.color1 = color1
	self.color2 = color2
	self.color3 = color3
	return self
end

---Liest das Event vom Netzwerk-Stream und führt es sofort aus.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventSpawn:readStream(streamId, connection)
	self.productionPoint = NetworkUtil.readNodeObject(streamId)
	self.ownerFarmId = streamReadInt32(streamId)
	self.fillTypeIndex = streamReadInt32(streamId)
	self.pendingLiters = streamReadInt32(streamId)
	self.width = streamReadFloat32(streamId)
	self.height = streamReadFloat32(streamId)
	self.length = streamReadFloat32(streamId)
	self.capacity = streamReadFloat32(streamId)
	self.type = streamReadFloat32(streamId)
	if streamReadBool(streamId) then
		self.customEnvironment = streamReadString(streamId)
	end
	if streamReadBool(streamId) then
		self.treeId = streamReadInt32(streamId)
	end
	self.amount = streamReadFloat32(streamId)
	self.color1 = streamReadFloat32(streamId)
	self.color2 = streamReadFloat32(streamId)
	self.color3 = streamReadFloat32(streamId)
	self:run(connection)
end

---Schreibt das Event auf den Netzwerk-Stream. customEnvironment/treeId sind optional und bekommen
---deshalb je ein vorangestelltes Bool-Flag, ob überhaupt ein Wert folgt.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventSpawn:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.productionPoint)
	streamWriteInt32(streamId, self.ownerFarmId)
	streamWriteInt32(streamId, self.fillTypeIndex)
	streamWriteInt32(streamId, self.pendingLiters)
	streamWriteFloat32(streamId, self.width)
	streamWriteFloat32(streamId, self.height)
	streamWriteFloat32(streamId, self.length)
	streamWriteFloat32(streamId, self.capacity)
	streamWriteFloat32(streamId, self.type)
	if streamWriteBool(streamId, self.customEnvironment ~= nil) then
		streamWriteString(streamId, self.customEnvironment)
	end
	if streamWriteBool(streamId, self.treeId ~= nil) then
		streamWriteInt32(streamId, self.treeId)
	end
	streamWriteFloat32(streamId, self.amount)
	streamWriteFloat32(streamId, self.color1)
	streamWriteFloat32(streamId, self.color2)
	streamWriteFloat32(streamId, self.color3)
end

---Führt den eigentlichen Spawn serverseitig aus.
---@param connection table Netzwerkverbindung
---@diagnostic disable-line: unused-local
function Revamp_EventSpawn:run(connection)
	self.productionPoint:ReceiveSpawnEvent(self.ownerFarmId, self.fillTypeIndex, self.pendingLiters, self.width, self.height, self.length, self.capacity, self.type, self.customEnvironment, self.treeId, self.amount, self.color1, self.color2, self.color3)
end

---Baut ein Spawn-Event und schickt es an den Server.
---@param productionPoint table ProductionPoint-Instanz, die das Objekt spawnen soll
---@param ownerFarmId number Farm, der das gespawnte Objekt gehören soll
---@param fillTypeIndex number FillType-Index
---@param pendingLiters number Noch aus dem Lager abzuziehende Literzahl
---@param width number Breite des zu spawnenden Objekts
---@param height number Höhe des zu spawnenden Objekts
---@param length number Länge des zu spawnenden Objekts
---@param capacity number Kapazität einer Verpackungseinheit
---@param type number Verpackungstyp (siehe ProductionPoint:ReceiveSpawnEvent)
---@param customEnvironment? string Custom-Environment-Name der Verpackung, falls modeigen
---@param treeId? number Baumtyp-Index bei Baumsetzlings-Paletten
---@param amount number Anzahl zu spawnender Objekte
---@param color1 number Foliencolor-Komponente 1
---@param color2 number Foliencolor-Komponente 2
---@param color3 number Foliencolor-Komponente 3
function Revamp_EventSpawn.sendEvent(productionPoint, ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type, customEnvironment, treeId, amount, color1, color2, color3)
	g_client:getServerConnection():sendEvent(Revamp_EventSpawn.new(productionPoint, ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type, customEnvironment, treeId, amount, color1, color2, color3))
end
