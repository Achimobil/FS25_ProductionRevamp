-- STORE ist ein vierter Ausgangsmodus (neben Vanillas KEEP/DIRECT_SELL/AUTO_DELIVER), der den automatischen Paletten-/Ballenspawn für einen FillType komplett unterdrückt.
-- Ohne ihn würde Revamp.updateProduction (revamp_production.lua) weiterhin sofort eine Palette spawnen, sobald die Kapazität erreicht ist -
-- der manuelle Auslagern-Button wäre damit kaum nutzbar, weil der Bestand nie über eine Palette hinaus anwächst.
--
-- Wird als weitere Utils.overwrittenFunction-Schicht auf ProductionPoint.load/updateProduction gestapelt statt in Revamp.loadProductionPoint/Revamp.updateProduction eingewoben:
-- beide besitzen bereits einen funktionierenden Unterdrückungs-Mechanismus (waitingForPalletToSpawn),
-- über den sich eine zusätzliche Schicht sicher aufsetzen lässt, exakt wie PSC es selbst auf Vanilla tut -
-- ohne die bestehende Mix-Gruppen-/Booster-Logik anzufassen.

ProductionPoint.OUTPUT_MODE.STORE = 3

---Registriert das Savegame-XML-Schema für die pro Produktionspunkt gespeicherte STORE-FillType-Liste.
---@param schema XMLSchema Schema, in das der neue Pfad eingetragen wird
---@param basePath string XML-Basispfad des ProductionPoint-Elements
function Revamp.registerStorageSavegameXMLPaths(schema, basePath)
	schema:register(XMLValueType.STRING, basePath .. ".storageFillType(?)", "FillType, das aktuell auf Einlagern steht")
end

ProductionPoint.registerSavegameXMLPaths = Utils.prependedFunction(ProductionPoint.registerSavegameXMLPaths, Revamp.registerStorageSavegameXMLPaths)

---Initialisiert outputFillTypeIdsStorage direkt nach dem eigentlichen ProductionPoint-Laden - standardmäßig alle Outputs auf STORE,
---damit ein frisch platziertes Placeable nichts automatisch spawnt, bevor Revamp.loadProductionStorageFromXMLFile die tatsächlich aktiven Modi aus dem Savegame zurückgeschaltet hat.
---@param self table ProductionPoint-Instanz
---@param superFunc function Ursprüngliches ProductionPoint.load
---@param components table i3d-Komponenten des Placeables
---@param xmlFile table XMLFile der Placeable-XML
---@param key string XML-Basispfad des ProductionPoint-Elements
---@param customEnv string Custom-Environment-Name des ladenden Mods
---@param i3dMappings table i3d-Mapping-Tabelle des Placeables
---@return boolean success true, wenn das ursprüngliche Laden erfolgreich war
function Revamp.loadProductionStorage(self, superFunc, components, xmlFile, key, customEnv, i3dMappings)
	local success = superFunc(self, components, xmlFile, key, customEnv, i3dMappings)

	self.outputFillTypeIdsStorage = {}
	if self.palletSpawner ~= nil then
		self.palletSpawner.pendingLiters = {}
		self.palletSpawner.pendingItem = {}
	end

	-- Standardmäßig alles auf STORE - Revamp.loadProductionStorageFromXMLFile schaltet die tatsächlich aktiven Modi direkt danach aus dem Savegame wieder um.
	for outputFillTypeIndex in pairs(self.outputFillTypeIds) do
		self.outputFillTypeIdsStorage[outputFillTypeIndex] = true
	end

	return success
end

ProductionPoint.load = Utils.overwrittenFunction(ProductionPoint.load, Revamp.loadProductionStorage)

---Speichert die aktuell auf STORE stehenden FillTypes eines Produktionspunkts ins Savegame.
---@param self table ProductionPoint-Instanz
---@param xmlFile table XMLFile, in das geschrieben wird
---@param key string XML-Basispfad des ProductionPoint-Elements
---@param usedModNames table Von Vanilla durchgereichte Liste verwendeter Mod-Namen
---@diagnostic disable-line: unused-local
function Revamp.saveProductionStorageToXMLFile(self, xmlFile, key, usedModNames)
	xmlFile:setTable(key .. ".storageFillType", self.outputFillTypeIdsStorage, function(fillTypeKey, _, fillTypeId)
		xmlFile:setValue(fillTypeKey, g_fillTypeManager:getFillTypeNameByIndex(fillTypeId))
	end)
end

ProductionPoint.saveToXMLFile = Utils.prependedFunction(ProductionPoint.saveToXMLFile, Revamp.saveProductionStorageToXMLFile)

---Sendet die STORE-FillTypes eines Produktionspunkts beim Erstverbinden an einen Client (MP-Sync).
---@param self table ProductionPoint-Instanz
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp.writeProductionStorageStream(self, streamId, connection)
	if not connection:getIsServer() then
		streamWriteUInt8(streamId, table.size(self.outputFillTypeIdsStorage))
		for storageFillTypeId in pairs(self.outputFillTypeIdsStorage) do
			streamWriteUIntN(streamId, storageFillTypeId, FillTypeManager.SEND_NUM_BITS)
		end
	end
end

ProductionPoint.writeStream = Utils.prependedFunction(ProductionPoint.writeStream, Revamp.writeProductionStorageStream)

---Empfängt die STORE-FillTypes eines Produktionspunkts vom Server (MP-Sync) und wendet sie an.
---@param self table ProductionPoint-Instanz
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp.readProductionStorageStream(self, streamId, connection)
	if connection:getIsServer() then
		-- Alles zuerst auf KEEP zurücksetzen, damit anschließend nur die vom Server tatsächlich gemeldeten STORE-FillTypes (unten) wieder umgeschaltet werden.
		for fillType in pairs(self.outputFillTypeIds) do
			if self.outputFillTypeIdsAutoDeliver[fillType] == nil then
				self:setOutputDistributionMode(fillType, ProductionPoint.OUTPUT_MODE.KEEP, true)
			end
		end
		for _ = 1, streamReadUInt8(streamId) do
			self:setOutputDistributionMode(streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS), ProductionPoint.OUTPUT_MODE.STORE, true)
		end
	end
end

ProductionPoint.readStream = Utils.prependedFunction(ProductionPoint.readStream, Revamp.readProductionStorageStream)

---Liest die im Savegame gespeicherten STORE-FillTypes eines Produktionspunkts und schaltet sie um.
---@param self table ProductionPoint-Instanz
---@param superFunc function Ursprüngliches ProductionPoint.loadFromXMLFile
---@param xmlFile table XMLFile des Savegames
---@param key string XML-Basispfad des ProductionPoint-Elements
---@return boolean success true, wenn das ursprüngliche Laden erfolgreich war
function Revamp.loadProductionStorageFromXMLFile(self, superFunc, xmlFile, key)
	for fillType in pairs(self.outputFillTypeIds) do
		if not self.mission.missionInfo.isNewSPCareer then
			self:setOutputDistributionMode(fillType, ProductionPoint.OUTPUT_MODE.KEEP)
		end
	end

	local success = superFunc(self, xmlFile, key)

	xmlFile:iterate(key .. ".storageFillType", function(_, storageKey)
		local fillType = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getValue(storageKey))
		if fillType then
			self:setOutputDistributionMode(fillType, ProductionPoint.OUTPUT_MODE.STORE)
		end
	end)

	return success
end

ProductionPoint.loadFromXMLFile = Utils.overwrittenFunction(ProductionPoint.loadFromXMLFile, Revamp.loadProductionStorageFromXMLFile)

---Liefert STORE als Ausgangsmodus, sobald ein FillType in outputFillTypeIdsStorage steht - sonst Vanillas eigene Ermittlung (KEEP/DIRECT_SELL/AUTO_DELIVER).
---@param self table ProductionPoint-Instanz
---@param superFunc function Ursprüngliche ProductionPoint.getOutputDistributionMode
---@param outputFillTypeId number FillType-Index
---@return number mode Einer der ProductionPoint.OUTPUT_MODE-Werte
function Revamp.getOutputDistributionMode(self, superFunc, outputFillTypeId)
	if self.outputFillTypeIdsStorage ~= nil and self.outputFillTypeIdsStorage[outputFillTypeId] ~= nil then
		return ProductionPoint.OUTPUT_MODE.STORE
	end

	return superFunc(self, outputFillTypeId)
end

ProductionPoint.getOutputDistributionMode = Utils.overwrittenFunction(ProductionPoint.getOutputDistributionMode, Revamp.getOutputDistributionMode)

---Schaltet den Ausgangsmodus eines FillTypes um - bei STORE wird nur der eigene Zustand gesetzt und per Event synchronisiert, alle anderen Modi laufen weiter über Vanillas eigene Umschaltlogik.
---@param self table ProductionPoint-Instanz
---@param superFunc function Ursprüngliche ProductionPoint.setOutputDistributionMode
---@param outputFillTypeId number FillType-Index
---@param mode any Einer der ProductionPoint.OUTPUT_MODE-Werte (kommt bei Netzwerk-Events als String an, deshalb die tonumber()-Absicherung unten)
---@param noEventSend? boolean Unterdrückt das Senden des Netzwerk-Events (z.B. beim Anwenden eines empfangenen Events)
function Revamp.setOutputDistributionMode(self, superFunc, outputFillTypeId, mode, noEventSend)
	if self.outputFillTypeIds[outputFillTypeId] == nil then
		Logging.error("Production Revamp: setOutputDistributionMode(): '%s' is not an output fillType", g_fillTypeManager:getFillTypeNameByIndex(outputFillTypeId))
		return
	end

	mode = tonumber(mode)
	-- Cooldown fürs Palettenspawnen, damit nicht versehentlich sofort eine Palette spawnt, während gerade erst umgeschaltet wird.
	self.palletSpawnCooldown = g_time + 4000

	self.outputFillTypeIdsStorage[outputFillTypeId] = nil
	self.outputFillTypeIdsDirectSell[outputFillTypeId] = nil
	self.outputFillTypeIdsAutoDeliver[outputFillTypeId] = nil

	if mode == ProductionPoint.OUTPUT_MODE.STORE then
		self.outputFillTypeIdsStorage[outputFillTypeId] = true
		ProductionPointOutputModeEvent.sendEvent(self, outputFillTypeId, mode, noEventSend)
	else
		superFunc(self, outputFillTypeId, mode, noEventSend)
	end
end

ProductionPoint.setOutputDistributionMode = Utils.overwrittenFunction(ProductionPoint.setOutputDistributionMode, Revamp.setOutputDistributionMode)

---Ersetzt Revamp.updateProduction()s eigenen Auto-Spawn-Tail nicht, sondern unterdrückt ihn für die Dauer des superFunc-Aufrufs
---(gleicher waitingForPalletToSpawn-Trick, den Revamp.updateProduction selbst schon nutzt, um Vanillas Auto-Spawn zu unterdrücken)
---und hängt danach die eigene, STORE-bewusste Version an -
---FillTypes mit STORE bekommen dadurch nie automatisch eine Palette.
---@param self table ProductionPoint-Instanz
---@param superFunc function Ursprüngliche Revamp.updateProduction
function Revamp.updateProductionStorage(self, superFunc)
	local backupPallet = self.waitingForPalletToSpawn
	self.waitingForPalletToSpawn = true
	superFunc(self)
	self.waitingForPalletToSpawn = backupPallet

	if self.isServer and self.isOwned and g_time > self.palletSpawnCooldown and not self.waitingForPalletToSpawn then
		local nextFillTypeId = nil
		while true do
			local fillTypeId = self.lastPalletFillTypeId
			if fillTypeId ~= nil
				and self.outputFillTypeIdsDirectSell[fillTypeId] == nil
				and self.outputFillTypeIdsAutoDeliver[fillTypeId] == nil
				and self.outputFillTypeIdsStorage[fillTypeId] == nil then
				local fillLevel = self.storage:getFillLevel(fillTypeId)
				if fillLevel > 0 then
					local pallet = self.outputFillTypeIdsToPallets[fillTypeId]
					if pallet ~= nil and pallet.filename ~= "nope" and pallet.capacity <= fillLevel then
						nextFillTypeId = fillTypeId
						break
					end
				end
			end
			self.lastPalletFillTypeId = next(self.outputFillTypeIdsToPallets, self.lastPalletFillTypeId)
			if self.lastPalletFillTypeId == nil then
				break
			end
		end
		if nextFillTypeId ~= nil then
			self.waitingForPalletToSpawn = true
			self.palletSpawner:spawnPallet(self:getOwnerFarmId(), nextFillTypeId, self.palletSpawnRequestCallback, self)
		end
	end
end

ProductionPoint.updateProduction = Utils.overwrittenFunction(ProductionPoint.updateProduction, Revamp.updateProductionStorage)

---Liefert den lokalisierten Anzeigetext für den aktuellen Ausgangsmodus eines FillTypes.
---@param productionPoint table ProductionPoint-Instanz
---@param fillType number FillType-Index
---@return string text Lokalisierter Modus-Text
function Revamp.getOutputModeText(productionPoint, fillType)
	local outputMode = productionPoint:getOutputDistributionMode(fillType)
	if outputMode == ProductionPoint.OUTPUT_MODE.DIRECT_SELL then
		return g_i18n:getText("ui_production_output_selling")
	elseif outputMode == ProductionPoint.OUTPUT_MODE.AUTO_DELIVER then
		return g_i18n:getText("ui_production_output_distributing")
	elseif outputMode == ProductionPoint.OUTPUT_MODE.STORE then
		return g_i18n:getText("revamp_ui_production_outputModeStore")
	end
	return g_i18n:getText("revamp_ui_production_outputModeManual")
end

---Entfernt den Ausgangsmodus-Text aus der Rezept-Auswahlliste (productsList).
---Vanilla zeigt dort den Modus des primären Outputs an, was bei mehreren Erzeugnissen einer Linie ohnehin nur die halbe Wahrheit ist.
---Die Liste der ausgehenden Erzeugnisse darunter zeigt den Modus jedes einzelnen Fülltyps, damit ist die Kurzinfo hier doppelt und irreführend zugleich.
---@param self table InGameMenuProductionFrame-Instanz
---@param list table Liste, deren Zelle gerade befüllt wird
---@param section number Sektionsindex innerhalb der Liste
---@param index number Zeilenindex innerhalb der Sektion
---@param cell table Zu befüllende Zelle
---@diagnostic disable-line: unused-local
function Revamp.populateProductsListActivity(self, list, section, index, cell)
	if list == self.productsList then
		cell:getAttribute("activity"):setText("")
	end
end

InGameMenuProductionFrame.populateCellForItemInSection = Utils.appendedFunction(InGameMenuProductionFrame.populateCellForItemInSection, Revamp.populateProductsListActivity)

-- Trennt in der Materialienliste das Erzeugnis von seinen Verteilzielen. Steht anstelle des Wortes "Verteilen" und braucht keine Übersetzung.
-- Der Pfeil ist Teil des Zeichensatzes der Spielschrift (z_locaFont in Vanillas l10n), er wird also nicht als leeres Kästchen dargestellt.
Revamp.DISTRIBUTION_ARROW = "→"

-- Anteil der Zellenbreite, den die Namensspalte der Materialienliste einnehmen darf, bevor sie in den Füllstandstext läuft.
Revamp.PRODUCTION_DETAILS_NAME_WIDTH_FACTOR = 0.64

---Ausgangsmodus als reiner Info-Text in der "OUTGOING PRODUCTS"-Liste (detailsList, cell.name == "fillTypeCell", section 2) -
---punktweit über alle Output-FillTypes, unabhängig von der gerade gewählten Rezeptlinie.
---Bewusst kein Button hier: detailsList hat handleFocus="false" (Vanilla schließt diese Liste bewusst von der Fokus-Navigation aus) -
---einzelne Zeilen sind dort nie eigene Fokus-Ziele, ein eingebauter Button wäre also nie controllererreichbar und bräche zudem bei jedem Scrollen (Zellen werden wiederverwendet).
---Der eigentliche Modus-Wechsel passiert stattdessen im "Verwalten"-Dialog (eigene, selbst kontrollierte Liste mit echter Fokus-Navigation, siehe revamp_manageDialog.lua) -
---hier nur Sichtbarkeit für Nebenprodukte, die bisher nirgends eine Modus-Anzeige hatten (nur die aktuell gewählte Rezeptlinie zeigt ihren primären Output an).
---@param self table InGameMenuProductionFrame-Instanz
---@param list table Liste, deren Zelle gerade befüllt wird
---@param section number Sektionsindex innerhalb der Liste
---@param index number Zeilenindex innerhalb der Sektion
---@param cell table Zu befüllende Zelle
---@diagnostic disable-line: unused-local
function Revamp.populateOutgoingFillTypeCell(self, list, section, index, cell)
	if list ~= self.detailsList or cell.name ~= "fillTypeCell" or section ~= 2 then
		return
	end

	local _, productionPoint = self:getSelectedProduction()
	if productionPoint == nil then
		return
	end

	local fillType = productionPoint.sortedOutputFillTypes[index]
	if fillType == nil or productionPoint.outputFillTypeIds[fillType] == nil then
		return
	end

	local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillType)

	-- Beim Verteilen stehen die Primär-Ziele direkt dahinter: wohin ein Erzeugnis geht, schaut man ständig nach, dafür soll niemand erst den Verwalten-Dialog öffnen müssen.
	-- Nur hier und nicht in Revamp.getOutputModeText selbst, weil die Modus-Spalte des Verwalten-Dialogs dafür zu schmal ist - dort steht die vollständige Zielliste ohnehin in einer eigenen Ansicht.
	-- Der Pfeil ersetzt dabei das Wort "Verteilen": er sagt dasselbe und lässt Platz für einen zweiten Zielnamen.
	local targetsText = Revamp.getPrimaryTargetsText(productionPoint, fillType)
	local text = fillTypeDesc.title .. " (" .. Revamp.getOutputModeText(productionPoint, fillType) .. ")"
	if targetsText ~= "" then
		text = fillTypeDesc.title .. " " .. Revamp.DISTRIBUTION_ARROW .. " " .. targetsText
	end

	local textElement = cell:getAttribute("fillType")
	-- Vanillas Namensspalte ist auf die reinen Fülltyp-Namen zugeschnitten und schneidet alles Längere mit "..." ab.
	-- Am rechten Rand der Zeile stehen Füllstand und Prozentwert, dazwischen liegt ungenutzter Platz - gemessen an einer 1920er Auflösung endet der breiteste Füllstandstext ("94.465 L / 144.000 L") rund 64 Prozent der Zellenbreite hinter deren linkem Rand.
	textElement:setSize(cell.absSize[1] * Revamp.PRODUCTION_DETAILS_NAME_WIDTH_FACTOR)
	textElement:setText(text)
end

InGameMenuProductionFrame.populateCellForItemInSection = Utils.appendedFunction(InGameMenuProductionFrame.populateCellForItemInSection, Revamp.populateOutgoingFillTypeCell)

---Produktionseigene Paletten (abweichend vom FillType-Standard, z.B. ein individuell texturiertes Mehl-Sack-Modell) werden nur hier aus der FillType-XML ausgelesen
---und für den späteren Auslagern-Dialog (revamp_spawner.lua) zwischengespeichert - Vanilla selbst kennt dieses <pallet filename="..."> Element nicht.
---@param self table FillTypeDesc-Instanz
---@param superFunc function Ursprüngliches FillTypeDesc.loadFromXMLFile
---@param xmlFile table XMLFile der FillType-XML
---@param xmlKey string XML-Basispfad des FillType-Elements
---@param xmlBaseDirectory string Basisverzeichnis für relative Dateipfade
---@param xmlCustomEnvironment string Custom-Environment-Name des ladenden Mods
---@return boolean success true, wenn das ursprüngliche Laden erfolgreich war
function Revamp.loadFillTypePallet(self, superFunc, xmlFile, xmlKey, xmlBaseDirectory, xmlCustomEnvironment)
	local palletPath = xmlFile:getValue(xmlKey .. ".pallet#filename", nil, xmlBaseDirectory)
	if palletPath ~= nil then
		self.pallets = self.pallets or {}
		self.pallets[xmlCustomEnvironment or "VANILLA"] = palletPath
	end

	return superFunc(self, xmlFile, xmlKey, xmlBaseDirectory, xmlCustomEnvironment)
end

FillTypeDesc.loadFromXMLFile = Utils.overwrittenFunction(FillTypeDesc.loadFromXMLFile, Revamp.loadFillTypePallet)
