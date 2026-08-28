-- Trigger-Interaktion + Paletten-/Ballenspawn fürs Auslagern, byte-nah portiert aus PSCs productionStorageControl_spawner.lua (Logik geprüft, keine funktionalen Denkfehler gefunden).
-- Ersetzt (wie PSC selbst) ProductionPointActivatable.run komplett statt es zu erweitern - Vanillas eigene run()-Funktion hat exakt die zwei Fälle (buyRequest/openMenu),
-- die hier unverändert erhalten bleiben, nur der openMenu()-Fall wird um die Spawn-Auswahl ergänzt, wenn ein Palettenspawner existiert.
--
-- Drei Kleinigkeiten gegenüber dem Original bereinigt:
-- - eine Variable ("enviroment") wurde an einer Stelle verwendet, bevor sie je gesetzt wird
--   (praktisch folgenlos, weil dieser Zweig - eine produktionseigene, vom FillType-Standard abweichende Palette -
--   beim tatsächlichen Spawnen ohnehin über den Dateipfad statt über customEnvironment aufgelöst wird - trotzdem entfernt statt mitgeschleppt)
-- - eine vergessene "local"-Deklaration erzeugte eine globale Variable
-- - ein Vergleich gegen "null" (gibt es in Lua nicht) statt "nil" funktionierte nur zufällig, weil eine undefinierte globale Variable ebenfalls nil ist

Revamp.wrappedBaleFillTypes = {
	SILAGE = true,
	SUGARBEET_CUT = true,
	FORAGE = true,
	GRASS_FERMENTED = true,
	CHOPPEDMAIZE_FERMENTED = true
}

-- Ein Bitmap-Element, dessen Bild nie per setImageFilename() gesetzt wird, rendert bei dieser Engine Bildrauschen statt einfach leer zu bleiben (bekannter Effekt) -
-- deshalb immer ein echtes Bild setzen, auch wenn "eigentlich nichts" angezeigt werden soll.
-- PSCs eigene, dafür gestaltete Grafik (schlicht transparent/neutral,
-- anders als z.B. Vanillas hud_fill_empty.dds das für einen anderen Kontext gemacht ist und dort sichtbar falsch aussieht) direkt mitübernommen.
Revamp.emptyIcon = g_currentModDirectory .. "gui/emptyFillType.dds"

---Liefert alle pflanzbaren Baumtypen (mit einer zweiten Wachstumsstufe) für die Baumsetzlings-Palette, einmal ermittelt und am ProductionPointActivatable gecacht.
---@param self table ProductionPointActivatable-Instanz
---@return table treeTypes Liste aus {name, treeId}
function Revamp.getTreeTypesForSpawn(self)
	if self.treeTypes == nil then
		self.treeTypes = {}
		for _, treeType in ipairs(g_treePlantManager.treeTypes) do
			if treeType.stages[2] ~= nil then
				table.insert(self.treeTypes, {name = treeType.title, treeId = treeType.index})
			end
		end
	end
	return self.treeTypes
end

---Sortierkomparator für Ballengrößen einer FillType: erst Quader- vor Rundballen, dann jeweils aufsteigend nach Länge/Durchmesser.
---@param bale1 table Ballengrößen-Eintrag
---@param bale2 table Ballengrößen-Eintrag
---@return boolean isSmaller true, wenn bale1 vor bale2 einsortiert werden soll
Revamp.compBaleSizes = function(bale1, bale2)
	if bale1.isRoundbale == bale2.isRoundbale then
		if bale1.isRoundbale then
			return bale1.diameter < bale2.diameter
		end
		return bale1.length < bale2.length
	end
	return bale1.isRoundbale
end

---Liefert die möglichen Ballengrößen je FillType (mögliche Ballengrößen), einmal ermittelt und am ProductionPointActivatable gecacht.
---@param self table ProductionPointActivatable-Instanz
---@return table baleTypes FillType-Index -> {sizes = {...}}
function Revamp.getBaleTypesForSpawn(self)
	if self.baleTypes == nil then
		local baleTypes = {}
		for _, baleType in ipairs(g_baleManager.bales) do
			-- isAvailable == false: für diese Karte deaktivierter Ballentyp (z.B. packedSquareBale120/Multibale)
			if baleType.isAvailable then
				for _, baleFillType in ipairs(baleType.fillTypes) do
					local fillTypeIndex = baleFillType.fillTypeIndex
					baleTypes[fillTypeIndex] = baleTypes[fillTypeIndex] or {sizes = {}}
					table.insert(baleTypes[fillTypeIndex].sizes, {
						isRoundbale = baleType.isRoundbale,
						diameter = baleType.diameter,
						width = baleType.width,
						height = baleType.height,
						length = baleType.length,
						capacity = baleFillType.capacity,
						customEnvironment = baleType.customEnvironment or "VANILLA"
					})
				end
			end
		end
		for _, baleType in pairs(baleTypes) do
			table.sort(baleType.sizes, Revamp.compBaleSizes)
		end
		self.baleTypes = baleTypes
	end
	return self.baleTypes
end

---Ersetzt Vanillas ProductionPointActivatable.run: Kauf-Trigger unverändert wie Vanilla,
---beim Öffnen der eigenen Produktion aber (falls ein Palettenspawner existiert) statt direkt ins Menü zu springen erst den Auslagern-Dialog mit allen auslagerbaren Output-FillTypes aufbauen.
---@param self table ProductionPointActivatable-Instanz
---@param superFunc function Ursprüngliches ProductionPointActivatable.run
---@param menue? boolean true, wenn über den Menü-Button statt den physischen Trigger ausgelöst (unterdrückt den "Produktion verwalten"-Menüpunkt, der dort schon als eigener Button existiert)
---@diagnostic disable-line: unused-local
function Revamp.spawnerRun(self, superFunc, menue)
	-- Ohne die Lager-Erweiterung öffnet der Trigger am Gebäude wieder Vanillas eigenes Produktionsmenü statt des Auslagern-Dialogs.
	if not Revamp.settings.storageActive then
		return superFunc(self, menue)
	end

	local ownerFarmId = self.productionPoint:getOwnerFarmId()
	if ownerFarmId == AccessHandler.EVERYONE and self.productionPoint.useInteractionTriggerForBuying then
		self.productionPoint:buyRequest()
	elseif ownerFarmId == self.mission:getFarmId() then
		if self.productionPoint.palletSpawner == nil then
			self.productionPoint:openMenu()
			return
		end

		if self.baleTypes == nil then
			self.baleTypes = Revamp.getBaleTypesForSpawn(self)
		end

		local outputFillTypes = {}
		for _, fillTypeIndex in ipairs(self.productionPoint.outputFillTypeIdsArray) do
			local fillLevel = self.productionPoint:getFillLevel(fillTypeIndex)
			local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
			if fillLevel > 1 and (fillType.palletFilename ~= nil or self.baleTypes[fillTypeIndex] ~= nil or fillType.name == "TREESAPLINGS") then
				local entry = {title = fillType.title, fillLevel = fillLevel, fillTypeIndex = fillTypeIndex}
				table.insert(outputFillTypes, entry)
				-- Baumsetzlinge 2x eintragen, damit beide Paletten-Varianten (Typ 4+5) verfügbar sind
				if fillType.name == "TREESAPLINGS" then
					self.treeTypes = Revamp.getTreeTypesForSpawn(self)
					table.insert(outputFillTypes, entry)
				end
			end
		end

		table.sort(outputFillTypes, function(w1, w2) return w1.title < w2.title end)

		local options = {}
		if menue ~= true then
			table.insert(options, {
				openmenu = true,
				title = g_i18n:getText("revamp_storageOpenProduction"),
				fillTypeIndex = 0,
				fillLevel = 0,
				fillTypeIcon = Revamp.emptyIcon,
				packages = {{max = 0, title = #outputFillTypes == 1 and " " or "", capacity = 0, modIcon = Revamp.emptyIcon}}
			})
		end

		local treePallet = false
		for i = 1, #outputFillTypes do
			local fillTypeIndex = outputFillTypes[i].fillTypeIndex
			local currentFillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
			local fillLevel = outputFillTypes[i].fillLevel
			if currentFillType.unitShort == "" then
				currentFillType.unitShort = g_i18n:getText("unit_literShort")
			end

			local option = {
				fillTypeIndex = fillTypeIndex,
				fillLevel = fillLevel,
				fillTypeIcon = currentFillType.hudOverlayFilename,
				unitShort = currentFillType.unitShort,
				title = currentFillType.title .. " (" .. g_i18n:formatVolume(fillLevel, 0, currentFillType.unitShort) .. ")",
				packages = {}
			}

			-- Sonderfall Baumsetzlinge: eigene Palette pro Aufruf (type 4 dann 5), kein customEnvironment
			if currentFillType.name == "TREESAPLINGS" then
				local palletXML = Utils.getFilename(treePallet and "$data/objects/pallets/treeSaplingPallet02/treeSaplingPallet02.xml" or "$data/objects/pallets/treeSaplingPallet01/treeSaplingPallet01.xml", self.baseDirectory)
				---@cast palletXML string

				local type = treePallet and 5 or 4
				treePallet = true

				local palletXmlFile = XMLFile.load("palletXmlFilename", palletXML, Vehicle.xmlSchema)
				---@cast palletXmlFile XMLFile

				local capacity = FillUnit.getCapacityFromXml(palletXmlFile)
				palletXmlFile:delete()
				local size = StoreItemUtil.getSizeValues(palletXML, "vehicle", 0, {})
				local max = math.floor(fillLevel / capacity)
				if fillLevel - max * capacity >= 1 then
					max = max + 1
				end

				for _, treeType in ipairs(self.treeTypes) do
					table.insert(option.packages, {
						capacity = capacity,
						max = max,
						width = size.width,
						height = size.height,
						length = size.length,
						type = type,
						customEnvironment = nil,
						modIcon = Revamp.emptyIcon,
						treeId = treeType.treeId,
						title = g_i18n:getText("typeDesc_pallet") .. " " .. treeType.name .. " (" .. capacity .. " " .. currentFillType.unitShort .. ")"
					})
				end
			end

			-- Paletten eintragen wenn vorhanden (nicht für Baumsetzlinge, die haben ihre eigenen oben)
			if currentFillType.palletFilename ~= nil and currentFillType.name ~= "TREESAPLINGS" then
				for environment, palletFilename in pairs(currentFillType.pallets) do
					local thisPallet = XMLFile.load("palletXmlFilename", palletFilename, Vehicle.xmlSchema)
					if thisPallet ~= nil then
						local size = StoreItemUtil.getSizeValues(palletFilename, "vehicle", 0, {})
						local capacity = FillUnit.getCapacityFromXml(thisPallet)
						thisPallet:delete()

						local max = math.floor(fillLevel / capacity)
						if fillLevel - max * capacity >= 1 then
							max = max + 1
						end

						table.insert(option.packages, {
							capacity = capacity,
							max = max,
							title = g_i18n:getText("typeDesc_pallet") .. " (" .. capacity .. " " .. currentFillType.unitShort .. ")",
							modIcon = environment ~= "VANILLA" and g_modManager:getModByName(environment).iconFilename or Revamp.emptyIcon,
							width = size.width,
							height = size.height,
							length = size.length,
							type = 1, -- Palette
							customEnvironment = environment
						})
					end
				end
			end

			-- Ballen eintragen wenn vorhanden
			if self.baleTypes[fillTypeIndex] ~= nil then
				for _, baleSize in ipairs(self.baleTypes[fillTypeIndex].sizes) do
					local bale = {
						capacity = baleSize.capacity,
						width = baleSize.width,
						height = baleSize.height,
						length = baleSize.length,
						type = 2, -- Quaderballen
						customEnvironment = baleSize.customEnvironment,
						modIcon = baleSize.customEnvironment ~= "VANILLA" and g_modManager:getModByName(baleSize.customEnvironment).iconFilename or Revamp.emptyIcon
					}
					if baleSize.isRoundbale then
						bale.type = 3 -- Rundballen
						-- Höhe/Tiefe tauschen, da der Ballen liegend (auf der Seite) gespawnt wird
						bale.length = baleSize.diameter
						bale.height = baleSize.diameter
					end
					if Revamp.wrappedBaleFillTypes[currentFillType.name] then
						bale.wrapped = true
					end
					if currentFillType.name == "COTTON" and not baleSize.isRoundbale then
						-- Drehen, damit der Quaderballen in den Spawnbereich passt
						bale.length = baleSize.height
						bale.height = baleSize.width
						bale.width = baleSize.length
						bale.wrapped = false
					end

					bale.max = math.floor(fillLevel / bale.capacity)
					if fillLevel - bale.max * bale.capacity >= 1 then
						bale.max = bale.max + 1
					end

					bale.title = g_i18n:getText(baleSize.isRoundbale and "fillType_roundBale" or "fillType_squareBale") .. " " .. tostring(baleSize.isRoundbale and baleSize.diameter or baleSize.length) .. "m (" .. g_i18n:formatVolume(bale.capacity, 0, currentFillType.unitShort) .. ")"
					table.insert(option.packages, bale)
				end
			end

			table.insert(options, option)
		end

		if #options == 0 then
			table.insert(options, {
				openmenu = true,
				title = g_i18n:getText("revamp_storageEmpty"),
				fillTypeIndex = 0,
				fillLevel = 0,
				fillTypeIcon = Revamp.emptyIcon,
				packages = {{max = 0, capacity = 0, title = g_i18n:getText("revamp_storageEmpty"), modIcon = Revamp.emptyIcon}}
			})
		end

		local farmList = {}
		for _, farm in pairs(g_farmManager:getFarms()) do
			if not farm.isSpectator and farm ~= self.playerFarm and farm.showInFarmScreen then
				table.insert(farmList, farm)
			end
		end

		RevampStorageDialog.show(farmList, self.productionPoint:getName(), options, self.productionPoint)
	end
end

ProductionPointActivatable.run = Utils.overwrittenFunction(ProductionPointActivatable.run, Revamp.spawnerRun)

---Spawnt die im Auslagern-Dialog gewählte Verpackung - Server-Seite, empfangen über Revamp_EventSpawn (siehe revamp_eventSpawn.lua).
---@param self table ProductionPoint-Instanz
---@param ownerFarmId number Farm, der das gespawnte Objekt gehören soll
---@param fillTypeIndex number FillType-Index
---@param pendingLiters number Noch aus dem Lager abzuziehende Literzahl
---@param width number Breite des zu spawnenden Objekts
---@param height number Höhe des zu spawnenden Objekts
---@param length number Länge des zu spawnenden Objekts
---@param capacity number Kapazität einer Verpackungseinheit
---@param type number Verpackungstyp (1 Palette, 2 Quaderballen, 3 Rundballen, 4/5 Baumsetzlings-Palette, 6 produktionseigene Palette)
---@param customEnvironment? string Custom-Environment-Name der Verpackung, falls modeigen
---@param treeId? number Baumtyp-Index bei Baumsetzlings-Paletten
---@param amount number Anzahl zu spawnender Objekte
---@param color1 number Foliencolor-Komponente 1 (bei einfoliert spawnenden Ballen)
---@param color2 number Foliencolor-Komponente 2
---@param color3 number Foliencolor-Komponente 3
function ProductionPoint:ReceiveSpawnEvent(ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type, customEnvironment, treeId, amount, color1, color2, color3)
	local item = {
		size = {height = height, width = width, length = length},
		capacity = capacity,
		type = type,
		treeId = treeId,
		customEnvironment = customEnvironment,
		ownerFarmId = ownerFarmId
	}

	if item.type == 1 then
		local currentFillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
		item.filename = currentFillType.pallets[customEnvironment]
	elseif item.type == 4 then
		item.filename = Utils.getFilename("$data/objects/pallets/treeSaplingPallet01/treeSaplingPallet01.xml", self.baseDirectory)
	elseif item.type == 5 then
		item.filename = Utils.getFilename("$data/objects/pallets/treeSaplingPallet02/treeSaplingPallet02.xml", self.baseDirectory)
	elseif item.type == 6 then
		item.filename = self.palletSpawner.fillTypeIdToPallet[fillTypeIndex].filename
	else
		local isRoundbale = item.type == 3
		local diameter = isRoundbale and length or 0
		local currentFillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
		if currentFillType.name == "COTTON" and not isRoundbale then
			height, width, length = item.size.length, item.size.height, item.size.width
		end
		item.filename = g_baleManager:getBaleXMLFilename(fillTypeIndex, isRoundbale, width, height, length, diameter, customEnvironment)
		item.color1 = color1
		item.color2 = color2
		item.color3 = color3
	end

	self.palletSpawner.pendingLiters[fillTypeIndex] = pendingLiters
	self.palletSpawner.pendingItem[fillTypeIndex] = item

	for _ = 1, amount do
		table.insert(self.palletSpawner.spawnQueue, {
			pallet = item,
			fillType = fillTypeIndex,
			farmId = item.ownerFarmId,
			callback = self.getPalletCallback,
			callbackTarget = self
		})
	end
	g_currentMission:addUpdateable(self.palletSpawner)
end

---Callback des PalletSpawners, sobald ein einzelnes Objekt aus der Spawn-Queue platziert wurde - befüllt die Palette/den Baumsetzling mit dem angeforderten Füllstand und zieht ihn aus dem Lager ab
---(Ballen ziehen stattdessen ihre feste Kapazität ab, da sie nicht nachträglich befüllt werden).
---@param self table ProductionPoint-Instanz
---@param pallet? table Gespawntes Objekt, nil wenn kein Platz gefunden wurde
---@param result number PalletSpawner.RESULT_*-Konstante
---@param fillTypeIndex number FillType-Index
function ProductionPoint:getPalletCallback(pallet, result, fillTypeIndex)
	self.spawnPending = false
	if pallet == nil then
		return
	end

	pallet.fillTypeIndex = fillTypeIndex
	local pendingItem = self.palletSpawner.pendingItem[fillTypeIndex]

	local delta = 0
	if pendingItem.type == 1 or pendingItem.type == 4 or pendingItem.type == 5 or pendingItem.type == 6 then
		if result == PalletSpawner.RESULT_SUCCESS then
			pallet:emptyAllFillUnits(true)
		end
		local fillUnitIndex = pallet:getFirstValidFillUnitToFill(fillTypeIndex)
		delta = pallet:addFillUnitFillLevel(self:getOwnerFarmId(), fillUnitIndex, self.palletSpawner.pendingLiters[fillTypeIndex], fillTypeIndex, ToolType.UNDEFINED)
	else
		-- Ballen spawnen mit festem Volumen, Capacity direkt zum Abziehen aus dem Storage verwenden
		delta = pallet.capacity
	end
	self.palletSpawner.pendingLiters[fillTypeIndex] = math.max(self.palletSpawner.pendingLiters[fillTypeIndex] - delta, 0)

	if pendingItem.type == 4 or pendingItem.type == 5 then
		pallet.boughtConfigurations.treeSaplingType[1] = false
		local treeId = pendingItem.treeId
		if treeId >= 20 then
			treeId = treeId - 2
		end
		pallet.boughtConfigurations.treeSaplingType[treeId] = true
		pallet.configurations.treeSaplingType = treeId

		local treeTypeName = g_treePlantManager:getTreeTypeNameFromIndex(pendingItem.treeId)
		local _, variation = pallet:getTreeSaplingPalletType()
		pallet:setTreeSaplingPalletType(treeTypeName, variation)

		local treeStages = g_treePlantManager:getTreeTypeDescFromName(treeTypeName).stages[1]
		pallet.spec_treeSaplingPallet.treeTypeFilename = variation == "DEFAULT" and treeStages[2].filename or treeStages[1].palletFilename
		pallet:updateTreeSaplingVisuals()
	end

	local available = self.storage.fillLevels[fillTypeIndex]
	if available ~= nil and available > 0 then
		self.storage:setFillLevel(available - math.min(delta, available), fillTypeIndex)
	end

	if self.palletSpawner.pendingLiters[fillTypeIndex] == 0 then
		self.palletSpawner.pendingLiters[fillTypeIndex] = nil
		self.palletSpawner.pendingItem[fillTypeIndex] = nil
	end
end

---Startet die Platzierungssuche für das nächste Objekt der Spawn-Queue -
---Paletten/Baumsetzlinge über Vanillas eigenes onSpawnSearchFinished, Ballen über die eigene onSpawnSearchFinishedOther unten.
---@param self table PalletSpawner-Instanz
---@param superFunc function Ursprüngliches PalletSpawner.update
---@diagnostic disable-line: unused-local
function Revamp.spawnerUpdate(self, superFunc)
	if #self.spawnQueue == 0 then
		g_currentMission:removeUpdateable(self)
		return
	end

	if self.currentObjectToSpawn == nil then
		self.currentObjectToSpawn = self.spawnQueue[1]
		local spawnPlaces = self.fillTypeToSpawnPlaces[self.currentObjectToSpawn.fillType] or self.spawnPlaces
		local palletType = self.currentObjectToSpawn.pallet.type
		if palletType == 1 or palletType == 4 or palletType == 5 or palletType == 6 or palletType == nil then
			g_currentMission.placementManager:getPlaceAsync(spawnPlaces, self.currentObjectToSpawn.pallet.size, self.onSpawnSearchFinished, self)
		else
			g_currentMission.placementManager:getPlaceAsync(spawnPlaces, self.currentObjectToSpawn.pallet.size, self.onSpawnSearchFinishedOther, self)
		end
	end
end

PalletSpawner.update = Utils.overwrittenFunction(PalletSpawner.update, Revamp.spawnerUpdate)

---Platzierung für Ballen gefunden (Paletten laufen über Vanillas eigenes onSpawnSearchFinished) -
---lädt das Ballenobjekt, richtet es aus (liegende Rundballen, gedrehte Cotton-Quaderballen) und registriert es.
---@param self table PalletSpawner-Instanz
---@param location? table Gefundene Platzierung (Position+Rotation), nil wenn kein Platz gefunden wurde
function PalletSpawner:onSpawnSearchFinishedOther(location)
	local objectToSpawn = self.currentObjectToSpawn

	if location == nil then
		objectToSpawn.callback(objectToSpawn.callbackTarget, nil, PalletSpawner.RESULT_NO_SPACE)
		self.currentObjectToSpawn = nil
		table.remove(self.spawnQueue, 1)
		return
	end

	location.y = location.y + 0.25
	local baleObject = Bale.new(g_currentMission:getIsServer(), g_currentMission:getIsClient())
	local fillTypeName = g_fillTypeManager:getFillTypeByIndex(objectToSpawn.fillType).name

	if objectToSpawn.pallet.type == 3 then
		-- Rundballen auf die Seite drehen, damit sie nicht wegrollen
		location.xRot = location.xRot + (3.1415927 / 2)
	end
	if fillTypeName == "COTTON" then
		-- Cotton-Quaderballen drehen, damit sie in den Spawnbereich passen, plus anheben
		location.yRot = location.yRot + (3.1415927 / 2)
		location.y = location.y + 1.30
	end

	if not baleObject:loadFromConfigXML(objectToSpawn.pallet.filename, location.x, location.y, location.z, location.xRot, location.yRot, location.zRot) then
		Logging.error("Production Revamp: PalletSpawner konnte Ballen-Objekt nicht laden ('%s')", objectToSpawn.pallet.filename)
		self.currentObjectToSpawn = nil
		table.remove(self.spawnQueue, 1)
		return
	end

	baleObject:setFillType(objectToSpawn.fillType, true)
	baleObject:setOwnerFarmId(objectToSpawn.farmId, true)
	if self.pendingLiters[objectToSpawn.fillType] > objectToSpawn.pallet.capacity then
		baleObject:setFillLevel(objectToSpawn.pallet.capacity, true)
	else
		baleObject:setFillLevel(self.pendingLiters[objectToSpawn.fillType], true)
	end

	if objectToSpawn.pallet.type == 2 and fillTypeName ~= "COTTON" then
		-- Quaderballen grundsätzlich mit Kordel, Cotton hat keine
		baleObject:setVariationId("TWINE")
	elseif objectToSpawn.pallet.type == 3 and fillTypeName ~= "WOODCHIPS" then
		-- Rundballen grundsätzlich mit Netzwrap, Cotton mit Folienwrap
		baleObject:setVariationId(fillTypeName == "COTTON" and "FOILWRAP" or "NETWRAP")
	end
	if Revamp.wrappedBaleFillTypes[fillTypeName] then
		-- Manche Ballen spawnen nur eingefoliert
		baleObject:setWrappingState(1)
		baleObject:setColor(objectToSpawn.pallet.color1, objectToSpawn.pallet.color2, objectToSpawn.pallet.color3)
	end
	baleObject:register()

	objectToSpawn.callback(objectToSpawn.callbackTarget, objectToSpawn.pallet, PalletSpawner.RESULT_SUCCESS, objectToSpawn.fillType)
	self.currentObjectToSpawn = nil
	table.remove(self.spawnQueue, 1)
end

---Trägt Ballen und Baumsetzlinge als Fake-Paletten ein, um Vanillas Fehler "not supported by loading station or pallet spawner" zu unterdrücken
---(echtes Spawnen läuft für diese Typen über onSpawnSearchFinishedOther, nicht über die hier eingetragene "nope"-Datei).
---@param self table PalletSpawner-Instanz
---@param superFunc function Ursprüngliches PalletSpawner.getSupportedFillTypes
---@return table fillTypeIdToPallet FillType-Index -> Paletteninfo
---@diagnostic disable-line: unused-local
function Revamp.spawnerGetSupportedFillTypes(self, superFunc)
	self.baleTypes = Revamp.getBaleTypesForSpawn(self)
	for fillTypeIndex in pairs(self.baleTypes) do
		if self.fillTypeIdToPallet[fillTypeIndex] == nil then
			self.fillTypeIdToPallet[fillTypeIndex] = {filename = "nope"}
		end
	end

	local treeSaplings = g_fillTypeManager:getFillTypeIndexByName("TREESAPLINGS")
	if self.fillTypeIdToPallet[treeSaplings] == nil then
		self.fillTypeIdToPallet[treeSaplings] = {filename = "nope"}
	end

	return self.fillTypeIdToPallet
end

PalletSpawner.getSupportedFillTypes = Utils.overwrittenFunction(PalletSpawner.getSupportedFillTypes, Revamp.spawnerGetSupportedFillTypes)

---Fügt den "Auslagern"-Button in die Menü-Button-Leiste ein, unabhängig vom "Verwalten"-Button (revamp_manageDialog.lua) -
---eigene InputAction (MENU_EXTRA_2), löst dieselbe run(true)-Logik wie der physische Trigger aus.
---@param self table InGameMenuProductionFrame-Instanz
function Revamp.addSpawnButton(self)
	if not Revamp.settings.storageActive then
		return
	end

	if self.pointsSelector:getState() == InGameMenuProductionFrame.POINTS_OWNED and g_currentMission:getHasPlayerPermission("manageProductions") then
		local _, productionPoint = self:getSelectedProduction()
		if productionPoint ~= nil and productionPoint.palletSpawner ~= nil then
			table.insert(self.menuButtonInfo, {
				profile = "buttonOK",
				inputAction = InputAction.MENU_EXTRA_2,
				text = g_i18n:getText("revamp_storageButtonSpawn"),
				callback = function()
					productionPoint.activatable:run(true)
				end
			})
		end
	end
end

InGameMenuProductionFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuProductionFrame.updateMenuButtons, Revamp.addSpawnButton)
