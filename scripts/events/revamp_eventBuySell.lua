-- MP-Event fürs Kaufen/Verkaufen (siehe revamp_buySell.lua/revamp_buyGoodsDialog.lua), byte-nah portiert aus
-- dem bereits veröffentlichten FS25_ProductionSupplyTrader (productionSupplyTrader_event_buySell.lua).

Revamp_EventBuySell = {}
local Revamp_EventBuySell_mt = Class(Revamp_EventBuySell, Event)
InitEventClass(Revamp_EventBuySell, "Revamp_EventBuySell")

---Erzeugt ein leeres Event für die Netzwerk-Deserialisierung (readStream befüllt die Felder danach).
---@return table self Neue, noch unbefüllte Revamp_EventBuySell-Instanz
function Revamp_EventBuySell.emptyNew()
	return Event.new(Revamp_EventBuySell_mt)
end

---Erzeugt ein versandfertiges Kauf/Verkauf-Event.
---@param productionPoint table ProductionPoint-Instanz, an der gekauft/verkauft wird
---@param fillTypeIndex number FillType-Index
---@param amount number Angeforderte Menge in Litern
---@param buySell boolean true = kaufen, false = verkaufen
---@return table self Versandfertige Revamp_EventBuySell-Instanz
function Revamp_EventBuySell.new(productionPoint, fillTypeIndex, amount, buySell)
	local self = Revamp_EventBuySell.emptyNew()
	self.productionPoint = productionPoint
	self.fillTypeIndex = fillTypeIndex
	self.amount = amount
	self.buySell = buySell
	return self
end

---Liest das Event vom Netzwerk-Stream und führt es sofort aus.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp_EventBuySell:readStream(streamId, connection)
	self.productionPoint = NetworkUtil.readNodeObject(streamId)
	self.fillTypeIndex = streamReadInt32(streamId)
	self.amount = streamReadInt32(streamId)
	self.buySell = streamReadBool(streamId)
	self:run(connection)
end

---Schreibt das Event auf den Netzwerk-Stream.
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
---@diagnostic disable-line: unused-local
function Revamp_EventBuySell:writeStream(streamId, connection)
	NetworkUtil.writeNodeObject(streamId, self.productionPoint)
	streamWriteInt32(streamId, self.fillTypeIndex)
	streamWriteInt32(streamId, self.amount)
	streamWriteBool(streamId, self.buySell)
end

---Führt den eigentlichen Kauf/Verkauf serverseitig aus.
---@param connection table Netzwerkverbindung
function Revamp_EventBuySell:run(connection)
	self.productionPoint:ReceiveBuySellEvent(self.fillTypeIndex, self.amount, self.buySell, connection)
end

---Baut ein Kauf/Verkauf-Event und schickt es an den Server.
---@param productionPoint table ProductionPoint-Instanz, an der gekauft/verkauft wird
---@param fillTypeIndex number FillType-Index
---@param amount number Angeforderte Menge in Litern
---@param buySell boolean true = kaufen, false = verkaufen
function Revamp_EventBuySell.sendEvent(productionPoint, fillTypeIndex, amount, buySell)
	g_client:getServerConnection():sendEvent(Revamp_EventBuySell.new(productionPoint, fillTypeIndex, amount, buySell))
end
