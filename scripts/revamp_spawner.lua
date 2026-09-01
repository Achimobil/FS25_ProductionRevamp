--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

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


---Legt die Buchführung an, die das Auslagern über den Palettenspawner braucht.
---Vanilla kennt diese beiden Tabellen nicht: zwischen dem Anstoßen und dem tatsächlichen Platzieren eines Objekts liegen mehrere Frames, solange muss gemerkt werden,
---wie viele Liter für einen Fülltyp noch aus dem Lager zu nehmen sind und welche Verpackung dafür gilt.
---@param palletSpawner table Palettenspawner des Spawn-Ziels
function Revamp.prepareSpawnBookkeeping(palletSpawner)
	palletSpawner.pendingLiters = {}
	palletSpawner.pendingItem = {}
end

---Liefert die Lager eines Silos, die zur Farm des Gebäudes gehören.
---Bewusst nicht über die Verladestation, obwohl die eine fertige Zusammenfassung hätte: sie nimmt ein Lager nur auf, wenn dessen Fülltypen zu einem ihrer Ladepunkte passen.
---Ein Silo, das seinen Inhalt ausschließlich über das Auslagern abgibt, braucht keine Verladestelle - dort stünde in der Station dann gar kein Lager, obwohl welche da sind.
---@param placeable table Silo-Placeable
---@return table storages Lager der eigenen Farm
function Revamp.getSiloStorages(placeable)
	local farmId = placeable:getOwnerFarmId()
	local storages = {}

	for _, storage in ipairs(placeable.spec_silo.storages) do
		-- Bei <storages perFarm="true"> legt Vanilla im Mehrspieler je Lager-Eintrag eine Kopie pro Farm an; gemeint ist hier nur die des Gebäudes.
		if storage:getOwnerFarmId() == farmId then
			table.insert(storages, storage)
		end
	end

	return storages
end

---Zieht eine ausgelagerte Menge vom Bestand des Spawn-Ziels ab.
---@param source table Spawn-Ziel, aus dem ausgelagert wird
---@param fillTypeIndex number FillType-Index
---@param delta number Abzuziehende Menge in Litern
function Revamp.removeSpawnSourceFillLevel(source, fillTypeIndex, delta)
	if source.spec_silo ~= nil then
		-- Ein Fülltyp kann in mehreren Lagern desselben Silos liegen, dann wird der Reihe nach abgeräumt.
		for _, storage in ipairs(Revamp.getSiloStorages(source)) do
			local available = storage:getFillLevel(fillTypeIndex)
			if available > 0 then
				local moved = math.min(delta, available)
				storage:setFillLevel(available - moved, fillTypeIndex)
				delta = delta - moved
				if delta <= 0 then
					return
				end
			end
		end

		return
	end

	local available = source.storage.fillLevels[fillTypeIndex]
	if available ~= nil and available > 0 then
		source.storage:setFillLevel(available - math.min(delta, available), fillTypeIndex)
	end
end

-- Ab hier: Stammholz als weitere Verpackungsart neben Palette und Ballen.
-- Ein Stamm wird nicht wie eine Palette gesucht und hingestellt - die Platzsuche der Engine kennt nur Fahrzeuge und Paletten.
-- Stattdessen liegt in der Placeable-XML ein fester Knoten, an dem die Stämme erscheinen; um freien Platz muss sich der Modder mit der Wahl dieser Stelle selbst kümmern.

-- Baumart, aus der ein Stamm entsteht. Die Fichte aus dem LS22 gibt es im LS25 nicht mehr, deshalb eine Kiefer als Vorgabe;
-- über die Placeable-XML kann der Modder eine andere wählen, etwa eine Art, die nur seine Karte mitbringt.
Revamp.WOOD_LOG_DEFAULT_TREE_TYPE = "lodgepolePine"

-- Liter Holz je Stammlänge in Metern. Das Spiel rechnet die Menge aus dem Volumen des geschnittenen Stamms (Volumen mal volumeToLiter der Holzart),
-- das steht aber erst zwei Frames nach dem Ablegen fest - der Dialog braucht die Zahl schon vorher, um Stückzahl und Preis anzuzeigen. Deshalb eine Tabelle.
-- Die Werte für 6 bis 12 Meter sind an der Küstenkiefer im Spiel gemessen, indem Stämme an einem Sägewerk abgegeben und die Bestandsänderungen abgelesen wurden.
-- Je Länge wurden zwei Stämme gemessen: die beiden Varianten derselben Wachstumsstufe sind unterschiedlich dick und liefern bis zu 6 Prozent auseinanderliegende Mengen, hier steht ihr Mittel.
-- 9 und 11 Meter sind zwischen den Messwerten interpoliert, 1 bis 5 Meter aus dem Verhältnis der gemessenen Längen hochgerechnet.
-- Über 12 Meter endet die Tabelle bewusst: dort fehlen Messwerte, und ein Baum ist irgendwann schlicht nicht mehr länger. Längere Angaben in der XML werden auf diesen Wert begrenzt.
Revamp.WOOD_LITERS_PER_METER = {256, 509, 747, 952, 1157, 1366, 1558, 1711, 1926, 2141, 2387, 2632}

-- Seitlicher Abstand zwischen zwei Stämmen desselben Auftrags. Ohne ihn entstünden alle an derselben Stelle und lägen ineinander.
-- Gemessen entlang der lokalen X-Achse der Ablagestelle, die Stämme reihen sich also quer zu ihrer eigenen Länge auf.
Revamp.WOOD_LOG_SPACING = 1.2

-- Abstand zwischen zwei Stämmen. Ein Stamm entsteht als Baum, der im übernächsten Frame auf Länge geschnitten wird -
-- ohne Pause dazwischen lägen mehrere ungeschnittene Bäume gleichzeitig an derselben Stelle.
Revamp.WOOD_LOG_SPAWN_DELAY = 400

-- Die Angaben zum Stammholz hängen am Wurzelknoten der Placeable und nicht am productionPoint-Knoten, weil sie genauso für ein Silo gelten.
-- Registriert wird der Pfad deshalb mit festem Namen statt über den übergebenen Basispfad, und nur einmal - er wird von mehreren Stellen aus angemeldet.
Revamp.spawnerPathsRegistered = false

---@param schema XMLSchema Schema der Placeable-XML
function Revamp.registerSpawnerXMLPaths(schema)
	if Revamp.spawnerPathsRegistered then
		return
	end
	Revamp.spawnerPathsRegistered = true

	schema:register(XMLValueType.NODE_INDEX, "placeable.revampSpawner#triggerNode", "Trigger, an dem der Spieler das Auslagern auslöst - nur am Silo nötig, eine Produktionsstätte hat dafür ihren eigenen")
	PalletSpawner.registerXMLPaths(schema, "placeable.revampSpawner.palletSpawner")
	schema:register(XMLValueType.NODE_INDEX, "placeable.revampSpawner#woodSpawnNode", "Stelle, an der ausgelagerte Stämme abgelegt werden - der Platz dort wird nicht geprüft")
	schema:register(XMLValueType.STRING, "placeable.revampSpawner#woodTreeType", "Baumart, aus der die Stämme entstehen", Revamp.WOOD_LOG_DEFAULT_TREE_TYPE)
	schema:register(XMLValueType.INT, "placeable.revampSpawner#minWoodLogLength", "Kürzeste wählbare Stammlänge in Metern", 6)
	schema:register(XMLValueType.INT, "placeable.revampSpawner#maxWoodLogLength", "Längste wählbare Stammlänge in Metern, höchstens 12", 6)
	schema:register(XMLValueType.INT, "placeable.revampSpawner#maxWoodLogs", "Höchstzahl der Stämme, die auf einmal ausgelagert werden dürfen", 15)
end

---Liest die Angaben zum Ablegen von Stämmen aus der Placeable-XML.
---Ohne Ablagestelle gibt es kein Stammholz zur Auswahl - ohne sie wüsste niemand, wo die Stämme landen sollen.
---@param source table Spawn-Ziel, aus dem ausgelagert wird
---@param xmlFile table XMLFile der Placeable
---@param components table Komponenten der Placeable
---@param i3dMappings table i3dMappings der Placeable
function Revamp.loadSpawnerConfig(source, xmlFile, components, i3dMappings)
	local node = xmlFile:getValue("placeable.revampSpawner#woodSpawnNode", nil, components, i3dMappings)
	if node == nil then
		return
	end

	-- Lieber hier einmal hart abbrechen als bei jedem Auslagern still nichts zu tun: eine unbekannte Baumart fiele sonst gar nicht auf.
	local treeTypeName = xmlFile:getValue("placeable.revampSpawner#woodTreeType", Revamp.WOOD_LOG_DEFAULT_TREE_TYPE)
	if g_treePlantManager:getTreeTypeDescFromName(treeTypeName) == nil then
		Logging.xmlError(xmlFile, "Production Revamp: unknown woodTreeType '%s', no wood logs can be spawned here", treeTypeName)
		return
	end

	local maxKnownLength = #Revamp.WOOD_LITERS_PER_METER
	local minLength = math.clamp(xmlFile:getValue("placeable.revampSpawner#minWoodLogLength", 6), 1, maxKnownLength)
	local maxLength = math.clamp(xmlFile:getValue("placeable.revampSpawner#maxWoodLogLength", 6), minLength, maxKnownLength)

	source.revampWoodSpawn = {
		node = node,
		treeTypeName = treeTypeName,
		minLength = minLength,
		maxLength = maxLength,
		maxLogs = math.max(xmlFile:getValue("placeable.revampSpawner#maxWoodLogs", 15), 1)
	}
end

---Prüft, ob es für einen Fülltyp Stammholz zur Auswahl gibt.
---@param source table Spawn-Ziel, aus dem ausgelagert wird
---@param fillType table FillType-Beschreibung
---@return boolean hasWoodLogs true, wenn der Fülltyp als Stammholz ausgelagert werden kann
function Revamp.getHasWoodLogPackages(source, fillType)
	return source.revampWoodSpawn ~= nil and fillType.name == "WOOD"
end

---Trägt die wählbaren Stammlängen als Verpackungen ein.
---Nur für Holz und nur, wenn die Placeable eine Ablagestelle dafür mitbringt.
---@param option table Auswahleintrag des Fülltyps, dessen Verpackungen ergänzt werden
---@param source table Spawn-Ziel, aus dem ausgelagert wird
---@param fillType table FillType-Beschreibung
---@param fillLevel number Vorhandener Bestand in Litern
function Revamp.addWoodLogPackages(option, source, fillType, fillLevel)
	if not Revamp.getHasWoodLogPackages(source, fillType) then
		return
	end

	local woodSpawn = source.revampWoodSpawn

	for length = woodSpawn.minLength, woodSpawn.maxLength do
		local capacity = Revamp.WOOD_LITERS_PER_METER[length]
		-- Ein angefangener Stamm ergibt keinen Sinn, deshalb nur volle Stämme und keine Restmenge wie bei Paletten.
		local max = math.min(math.floor(fillLevel / capacity), woodSpawn.maxLogs)
		if max > 0 then
			table.insert(option.packages, {
				capacity = capacity,
				max = max,
				noRemainder = true,
				width = 1,
				height = 1,
				length = length,
				type = 7, -- Stammholz
				modIcon = Revamp.emptyIcon,
				title = string.format(g_i18n:getText("revamp_storageWoodLog"), length) .. " (" .. g_i18n:formatVolume(capacity, 0, fillType.unitShort) .. ")"
			})
		end
	end
end

---Legt einen einzelnen Stamm an der Ablagestelle ab.
---Bewusst nicht über TreePlantManager:loadTreeTrunk, obwohl es das im LS25 fertig gibt: die Vanilla-Fassung verteilt den Stamm nicht ins Netzwerk,
---sie wird dort nur von Konsolenbefehlen benutzt. Im Mehrspieler stünde der Stamm sonst nur auf dem Server.
---@param source table Spawn-Ziel, aus dem ausgelagert wird
---@param length number Länge des Stamms in Metern
---@param offsetX number Seitlicher Versatz zur Ablagestelle in Metern
---@return boolean spawned true, wenn der Stamm tatsächlich entstanden ist
function Revamp.spawnWoodLog(source, length, offsetX)
	local woodSpawn = source.revampWoodSpawn
	local treeTypeDesc = woodSpawn ~= nil and g_treePlantManager:getTreeTypeDescFromName(woodSpawn.treeTypeName) or nil
	if woodSpawn == nil or woodSpawn.node == nil or treeTypeDesc == nil then
		return false
	end

	local x, y, z = localToWorld(woodSpawn.node, offsetX, 0, 0)
	local dirX, dirY, dirZ = localDirectionToWorld(woodSpawn.node, 0, 0, 1)

	-- Letzte Wachstumsstufe, also der ausgewachsene Baum; die Variante darin ist reine Optik.
	local growthStateI = #treeTypeDesc.stages
	local variationIndex = math.random(1, #treeTypeDesc.stages[growthStateI])

	local treeId, splitShapeFileId = g_treePlantManager:loadTreeNode(treeTypeDesc, x, y, z, 0, 0, 0, growthStateI, variationIndex)
	if treeId == 0 then
		return false
	end

	-- Ohne teilbare Form lässt sich der Baum nicht zum Stamm schneiden - dann lieber gar nichts hinstellen als einen ganzen Baum.
	if not getFileIdHasSplitShapes(splitShapeFileId) then
		delete(treeId)
		return false
	end

	table.insert(g_treePlantManager.treesData.splitTrees, {
		node = treeId,
		growthStateI = growthStateI,
		variationIndex = variationIndex,
		x = x,
		y = y,
		z = z,
		rx = 0,
		ry = 0,
		rz = 0,
		treeType = treeTypeDesc.index,
		splitShapeFileId = splitShapeFileId,
		hasSplitShapes = true
	})

	g_server:broadcastEvent(TreePlantEvent.new(treeTypeDesc.index, x, y, z, 0, 0, 0, growthStateI, variationIndex, splitShapeFileId, false))

	-- Das eigentliche Schneiden übernimmt der TreePlantManager in den nächsten Frames, deshalb nur der Auftrag statt eines direkten Aufrufs.
	table.insert(g_treePlantManager.loadTreeTrunkDatas, {
		framesLeft = 2,
		shape = treeId + 2,
		x = x,
		y = y,
		z = z,
		length = length,
		offset = 0.5,
		dirX = dirX,
		dirY = dirY,
		dirZ = dirZ,
		delimb = true,
		useOnlyStump = false,
		cutTreeTrunkCallback = TreePlantManager.cutTreeTrunkCallback
	})

	return true
end

---Legt den nächsten Stamm des laufenden Auftrags ab und zieht seine Menge vom Lager ab.
---@param source table Spawn-Ziel, aus dem ausgelagert wird
function Revamp.spawnNextWoodLog(source)
	local job = source.revampWoodLogJob
	if job == nil then
		return
	end

	if Revamp.spawnWoodLog(source, job.length, job.spawned * Revamp.WOOD_LOG_SPACING) then
		Revamp.removeSpawnSourceFillLevel(source, job.fillTypeIndex, job.capacity)
		job.remaining = job.remaining - 1
		job.spawned = job.spawned + 1
	else
		-- Ging einer nicht, gehen die folgenden auch nicht - abbrechen statt es im Sekundentakt weiter zu versuchen.
		job.remaining = 0
	end

	if job.remaining <= 0 then
		source.revampWoodLogJob = nil
		return
	end

	local timer = Timer.new(Revamp.WOOD_LOG_SPAWN_DELAY)
	timer:setFinishCallback(function()
		Revamp.spawnNextWoodLog(source)
	end)
	timer:start(true)
end

---Startet das Ablegen mehrerer Stämme.
---@param source table Spawn-Ziel, aus dem ausgelagert wird
---@param fillTypeIndex number FillType-Index
---@param capacity number Liter je Stamm
---@param length number Länge der Stämme in Metern
---@param amount number Anzahl der Stämme
function Revamp.startWoodLogSpawn(source, fillTypeIndex, capacity, length, amount)
	-- Ein zweiter Auftrag würde den ersten mittendrin überschreiben; der laufende wird deshalb zuerst zu Ende gebracht.
	if source.revampWoodLogJob ~= nil then
		return
	end

	source.revampWoodLogJob = {
		fillTypeIndex = fillTypeIndex,
		capacity = capacity,
		length = length,
		remaining = amount,
		spawned = 0
	}

	Revamp.spawnNextWoodLog(source)
end

---Baut aus einer Liste von Fülltypen mit Bestand die Auswahleinträge des Auslagern-Dialogs: je Fülltyp ein Eintrag mit allen Verpackungen, die es dafür gibt.
---Vom Spawn-Ziel losgelöst, damit Produktionsstätte und Silo dieselbe Liste bekommen - das Ziel liefert nur noch, was drin liegt.
---@param self table Träger der zwischengespeicherten Ballen- und Baumlisten (Aktivierbares bzw. Spezialisierung)
---@param source table Spawn-Ziel, aus dem ausgelagert wird
---@param outputFillTypes table Liste aus {fillTypeIndex, fillLevel}, bereits nach Anzeigename sortiert
---@return table options Einträge für RevampStorageDialog
function Revamp.buildSpawnOptions(self, source, outputFillTypes)
	if self.baleTypes == nil then
		self.baleTypes = Revamp.getBaleTypesForSpawn(self)
	end

	-- Nur Fülltypen, von denen mehr als ein Liter da ist und für die es überhaupt eine Verpackung gibt.
	local selectable = {}
	for _, entry in ipairs(outputFillTypes) do
		local fillType = g_fillTypeManager:getFillTypeByIndex(entry.fillTypeIndex)
		if entry.fillLevel > 1 and (fillType.palletFilename ~= nil or self.baleTypes[entry.fillTypeIndex] ~= nil or fillType.name == "TREESAPLINGS" or Revamp.getHasWoodLogPackages(source, fillType)) then
			entry.title = fillType.title
			table.insert(selectable, entry)
			-- Baumsetzlinge 2x eintragen, damit beide Paletten-Varianten (Typ 4+5) verfügbar sind
			if fillType.name == "TREESAPLINGS" then
				self.treeTypes = Revamp.getTreeTypesForSpawn(self)
				table.insert(selectable, entry)
			end
		end
	end

	outputFillTypes = selectable
	table.sort(outputFillTypes, function(w1, w2) return w1.title < w2.title end)

	local options = {}

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

		Revamp.addWoodLogPackages(option, source, currentFillType, fillLevel)

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

		return options
	end

---Liefert die Farmen, denen das Ausgelagerte gehören kann.
---@param playerFarm? table Eigene Farm, die nicht mit in der Liste stehen soll
---@return table farmList Auswählbare Farmen
function Revamp.getSpawnFarmList(playerFarm)
	local farmList = {}
	for _, farm in pairs(g_farmManager:getFarms()) do
		if not farm.isSpectator and farm ~= playerFarm and farm.showInFarmScreen then
			table.insert(farmList, farm)
		end
	end

	return farmList
end

---Öffnet den Auslagern-Dialog für ein Silo.
---Anders als bei der Produktionsstätte kommen die Waren nicht aus einer Erzeugnis-Liste, sondern aus den Lagern selbst - ein Silo hat keine Ausgänge, alles darin ist auslagerbar.
---@param placeable table Silo-Placeable mit der Spawner-Spezialisierung
function Revamp.showSiloSpawnDialog(placeable)
	local fillLevels = {}
	for _, storage in ipairs(Revamp.getSiloStorages(placeable)) do
		for fillTypeIndex, fillLevel in pairs(storage:getFillLevels()) do
			fillLevels[fillTypeIndex] = (fillLevels[fillTypeIndex] or 0) + fillLevel
		end
	end

	local outputFillTypes = {}
	for fillTypeIndex, fillLevel in pairs(fillLevels) do
		table.insert(outputFillTypes, {fillTypeIndex = fillTypeIndex, fillLevel = fillLevel})
	end

	local options = Revamp.buildSpawnOptions(placeable.spec_revampSpawner, placeable, outputFillTypes)

	RevampStorageDialog.show(Revamp.getSpawnFarmList(), placeable:getName(), options, placeable)
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

		local outputFillTypes = {}
		for _, fillTypeIndex in ipairs(self.productionPoint.outputFillTypeIdsArray) do
			table.insert(outputFillTypes, {fillTypeIndex = fillTypeIndex, fillLevel = self.productionPoint:getFillLevel(fillTypeIndex)})
		end

		local options = Revamp.buildSpawnOptions(self, self.productionPoint, outputFillTypes)

		-- Der Pseudo-Eintrag steht vorn, damit der Dialog auch bei leerem Lager eine Zeile hat und man von dort ins Produktionsmenü kommt.
		if menue ~= true then
			table.insert(options, 1, {
				openmenu = true,
				title = g_i18n:getText("revamp_storageOpenProduction"),
				fillTypeIndex = 0,
				fillLevel = 0,
				fillTypeIcon = Revamp.emptyIcon,
				packages = {{max = 0, title = #options == 1 and " " or "", capacity = 0, modIcon = Revamp.emptyIcon}}
			})
		end

		RevampStorageDialog.show(Revamp.getSpawnFarmList(self.playerFarm), self.productionPoint:getName(), options, self.productionPoint)
	end
end

ProductionPointActivatable.run = Utils.overwrittenFunction(ProductionPointActivatable.run, Revamp.spawnerRun)

---Spawnt die im Auslagern-Dialog gewählte Verpackung - Server-Seite, empfangen über Revamp_EventSpawn (siehe revamp_eventSpawn.lua).
---@param self table Spawn-Ziel, aus dem ausgelagert wird
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
function Revamp.receiveSpawnEvent(self, ownerFarmId, fillTypeIndex, pendingLiters, width, height, length, capacity, type, customEnvironment, treeId, amount, color1, color2, color3)
	-- Stammholz läuft nicht über den Palettenspawner: es wird nicht gesucht und platziert, sondern an einer festen Stelle abgelegt.
	if type == 7 then
		Revamp.startWoodLogSpawn(self, fillTypeIndex, capacity, length, amount)
		return
	end

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

ProductionPoint.ReceiveSpawnEvent = Revamp.receiveSpawnEvent

---Callback des PalletSpawners, sobald ein einzelnes Objekt aus der Spawn-Queue platziert wurde - befüllt die Palette/den Baumsetzling mit dem angeforderten Füllstand und zieht ihn aus dem Lager ab
---(Ballen ziehen stattdessen ihre feste Kapazität ab, da sie nicht nachträglich befüllt werden).
---@param self table Spawn-Ziel, aus dem ausgelagert wird
---@param pallet? table Gespawntes Objekt, nil wenn kein Platz gefunden wurde
---@param result number PalletSpawner.RESULT_*-Konstante
---@param fillTypeIndex number FillType-Index
function Revamp.spawnPalletCallback(self, pallet, result, fillTypeIndex)
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

	Revamp.removeSpawnSourceFillLevel(self, fillTypeIndex, delta)

	if self.palletSpawner.pendingLiters[fillTypeIndex] == 0 then
		self.palletSpawner.pendingLiters[fillTypeIndex] = nil
		self.palletSpawner.pendingItem[fillTypeIndex] = nil
	end
end

ProductionPoint.getPalletCallback = Revamp.spawnPalletCallback

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

	-- Baumsetzlinge und Holz genauso: die einen bekommen ihre Palette erst beim Spawnen zugeordnet, das andere wird als Stamm abgelegt statt platziert.
	for _, fillTypeName in ipairs({"TREESAPLINGS", "WOOD"}) do
		local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
		if fillTypeIndex ~= nil and self.fillTypeIdToPallet[fillTypeIndex] == nil then
			self.fillTypeIdToPallet[fillTypeIndex] = {filename = "nope"}
		end
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
