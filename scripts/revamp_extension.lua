--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- Anmeldung fremder Mods bei Revamp, rein über XML.
--
-- Ein Mod, der eine Placeable mit einem Revamp-Typ mitbringt, kann sie nicht einfach in seine eigene modDesc schreiben:
-- ohne Revamp kennt das Spiel den Typ nicht und schreibt beim Laden eine Fehlerzeile ins Log, die jeden Spieler dieses Mods trifft.
-- Stattdessen legt der fremde Mod eine Anmelde-Datei ins Wurzelverzeichnis, die nur Revamp liest - ohne Revamp existiert die Placeable für das Spiel schlicht nicht.
--
-- Bewusst rein deklarativ, ohne eine einzige Lua-Datei im fremden Mod: sobald ein Mod Skriptcode enthält, ist er nicht mehr konsolenfähig.
-- Ein reiner Placeable-Mod würde damit alle Konsolenspieler verlieren, nur um sich hier anzumelden.

-- Name der Anmelde-Datei, gesucht wird sie im Wurzelverzeichnis jedes geladenen Mods.
Revamp.EXTENSION_FILENAME = "revamp_extension.xml"

-- Die Anmeldung darf nur einmal je Sitzung laufen: die eingereihten Store-Items bleiben über einen Kartenwechsel hinweg bestehen,
-- ein zweiter Durchlauf würde dieselben Einträge ein weiteres Mal in den Laden legen.
Revamp.extensionsLoaded = false

-- Angemeldete Fülltypen, solange die Fülltypen des Spiels noch gar nicht geladen sind: die Anmelde-Dateien werden beim Laden der Store-Items gelesen, und das passiert vor dem FillTypeManager.
Revamp.extensionFillTypeRequests = {}

-- Die aufgelöste Fassung davon, Schlüssel ist der Referenz-Fülltyp: [WHEAT] = {{fillType = MY_CROP, addToStorage = true}, ...}
Revamp.extraFillTypes = {}

---Liefert das Schema der Anmelde-Datei und legt es beim ersten Aufruf an.
---Bewusst erst bei Bedarf statt beim Laden des Mods: dann steht fest, dass die XML-Verwaltung des Spiels bereits vollständig hochgefahren ist.
---@return XMLSchema schema Schema der Anmelde-Datei
function Revamp.getExtensionSchema()
	if Revamp.extensionSchema == nil then
		Revamp.extensionSchema = XMLSchema.new("revampExtension")
		Revamp.extensionSchema:register(XMLValueType.STRING, "revampExtension.storeItems.storeItem(?)#xmlFilename", "Pfad zur Store-Item-XML, relativ zum Wurzelverzeichnis des anmeldenden Mods")
		Revamp.extensionSchema:register(XMLValueType.STRING, "revampExtension.fillTypes.fillType(?)#name", "Eigener Fülltyp, der zusätzlich angenommen werden soll")
		Revamp.extensionSchema:register(XMLValueType.STRING, "revampExtension.fillTypes.fillType(?)#like", "Vorhandener Fülltyp: überall, wo dieser angenommen wird, wird künftig auch der eigene angenommen")
		Revamp.extensionSchema:register(XMLValueType.BOOL, "revampExtension.fillTypes.fillType(?)#addToStorage", "Zusätzlich in Lager aufnehmen, die den Referenz-Fülltyp aus einer Gesamtkapazität bedienen", false)
	end

	return Revamp.extensionSchema
end

---Liest die Anmelde-Datei eines Mods und meldet die darin genannten Store-Items an.
---@param mod table Eintrag aus g_modManager:getActiveMods()
---@param filename string Vollständiger Pfad der Anmelde-Datei
---@return number numStoreItems Anzahl der tatsächlich angemeldeten Store-Items
function Revamp.loadExtensionFile(mod, filename)
	local xmlFile = XMLFile.load("revampExtensionXML", filename, Revamp.getExtensionSchema())
	if xmlFile == nil then
		Logging.error("Production Revamp: unable to read extension file '%s'", filename)
		return 0
	end

	local numStoreItems = 0

	xmlFile:iterate("revampExtension.storeItems.storeItem", function(_, key)
		local storeItemFilename = xmlFile:getValue(key .. "#xmlFilename")
		if storeItemFilename == nil then
			Logging.xmlError(xmlFile, "Production Revamp: '%s' needs an 'xmlFilename'", key)
			return
		end

		-- Lieber hier melden als das Spiel später über eine fehlende Datei stolpern zu lassen: der Modder sieht dann, welcher Eintrag gemeint ist.
		if not fileExists(Utils.getFilename(storeItemFilename, mod.modDir)) then
			Logging.xmlError(xmlFile, "Production Revamp: store item '%s' does not exist in mod '%s'", storeItemFilename, mod.modName)
			return
		end

		-- Angemeldet wie ein Eintrag aus der modDesc des fremden Mods, mit dessen Umgebung: nur so greifen seine eigenen Texte, Bilder und Typen.
		g_storeManager:addModStoreItem(storeItemFilename, mod.modDir, mod.modName, true, false, mod.title)
		numStoreItems = numStoreItems + 1
	end)

	-- Nur einsammeln, nicht auflösen: die Fülltypen des Spiels gibt es zu diesem Zeitpunkt noch gar nicht (siehe Revamp.resolveExtensionFillTypes).
	xmlFile:iterate("revampExtension.fillTypes.fillType", function(_, key)
		local name = xmlFile:getValue(key .. "#name")
		local reference = xmlFile:getValue(key .. "#like")

		if name == nil or reference == nil then
			Logging.xmlError(xmlFile, "Production Revamp: '%s' needs a 'name' and a 'like'", key)
			return
		end

		table.insert(Revamp.extensionFillTypeRequests, {
			name = name,
			reference = reference,
			addToStorage = xmlFile:getValue(key .. "#addToStorage", false),
			modName = mod.modName
		})
	end)

	xmlFile:delete()

	return numStoreItems
end

---Sucht in allen geladenen Mods nach Anmelde-Dateien und trägt deren Store-Items ein.
---Läuft direkt bevor das Spiel die eingereihten Store-Items tatsächlich lädt - zu diesem Zeitpunkt sind alle Mods durch, und die Liste ist noch nicht abgearbeitet.
function Revamp.loadExtensions()
	if Revamp.extensionsLoaded then
		return
	end
	Revamp.extensionsLoaded = true

	local numStoreItems = 0
	local numMods = 0

	for _, mod in ipairs(g_modManager:getActiveMods()) do
		local filename = mod.modDir .. Revamp.EXTENSION_FILENAME
		if fileExists(filename) then
			local numAdded = Revamp.loadExtensionFile(mod, filename)
			if numAdded > 0 then
				numMods = numMods + 1
				numStoreItems = numStoreItems + numAdded
				Revamp.DebugText("loadExtensions(): %s meldet %d Store-Items an", mod.modName, numAdded)
			end
		end
	end

	-- Eine Zeile im Log, damit ein Modder ohne Debug-Schalter sieht, dass seine Anmeldung angekommen ist.
	if numStoreItems > 0 then
		Logging.info("Production Revamp: added %d store items from %d mods", numStoreItems, numMods)
	end
end

StoreManager.loadMapData = Utils.prependedFunction(StoreManager.loadMapData, Revamp.loadExtensions)

-- Zusätzliche Fülltypen an vorhandenen Abladestellen, Verkaufsstellen und Lagern.
--
-- Für den einfachen Fall braucht es Revamp gar nicht: bringt eine Stelle ihre Fülltypen als Kategorie mit (`fillTypeCategories="GRAIN"`),
-- kann ein fremder Mod seine Frucht über seine eigene fillTypes.xml in diese Kategorie einhängen - eine Kategorie, die es schon gibt, wird dabei ergänzt statt abgelehnt (siehe FillTypeManager:addFillTypeCategory).
-- Das gilt genauso für Revamps eigene Kategorien aus revamp_fillTypes.xml.
--
-- Übrig bleibt der Fall, den Kategorien nicht abdecken: eine Stelle, die ihre Fülltypen namentlich aufzählt (`fillTypes="WHEAT BARLEY OAT"`), und davon gibt es auf den Karten reichlich.
-- Dafür meldet der Mod seinen Fülltyp mit einem Referenz-Fülltyp an: "überall, wo Weizen angenommen wird, nimm auch meine Frucht an".
-- Namentlich einzelne Stationen zu benennen wäre zwar genauer, bräche aber bei jeder Umbenennung und setzt voraus, dass der Modder jede Karte kennt, auf der sein Mod läuft.
--
-- "Überall" meint dabei nur die Stellen, die mit der Ware auch etwas anfangen können: eine Verkaufsstelle verkauft sie, ein Lager nimmt sie auf.
-- Produktionsstätten bleiben außen vor, auch wenn sie den Referenz-Fülltyp verarbeiten: eine Produktion kann nur, was in ihren Rezepten steht, und eine fremde Ware steht dort nicht.
-- Wer seine Frucht in ein Rezept bringen will, hängt sie über die eigene fillTypes.xml in die Fülltyp-Kategorie, die das Rezept als Zutat nennt.

---Löst die angemeldeten Fülltyp-Namen auf, sobald alle Fülltypen geladen sind.
---Der späteste Zeitpunkt vor dem Laden der Karten-Placeables und der früheste, zu dem auch die Fülltypen fremder Mods existieren (siehe mission00.lua: loadModFillTypes läuft nach allen loadMapData-Aufrufen und vor Mission00:load).
function Revamp.resolveExtensionFillTypes()
	local numFillTypes = 0

	for _, request in ipairs(Revamp.extensionFillTypeRequests) do
		local fillType = g_fillTypeManager:getFillTypeIndexByName(request.name)
		local reference = g_fillTypeManager:getFillTypeIndexByName(request.reference)

		if fillType == nil then
			Logging.error("Production Revamp: mod '%s' registers the unknown fillType '%s'", request.modName, request.name)
		elseif reference == nil then
			Logging.error("Production Revamp: mod '%s' refers to the unknown fillType '%s'", request.modName, request.reference)
		elseif fillType == reference then
			Logging.error("Production Revamp: mod '%s' registers fillType '%s' as an addition to itself", request.modName, request.name)
		else
			Revamp.extraFillTypes[reference] = Revamp.extraFillTypes[reference] or {}
			table.insert(Revamp.extraFillTypes[reference], {fillType = fillType, addToStorage = request.addToStorage})
			numFillTypes = numFillTypes + 1

			Revamp.DebugText("resolveExtensionFillTypes(): %s wird ueberall angenommen, wo %s angenommen wird (Lager: %s)", request.name, request.reference, tostring(request.addToStorage))
		end
	end

	Revamp.extensionFillTypeRequests = {}

	-- Eine Zeile im Log, damit ein Modder ohne Debug-Schalter sieht, dass seine Anmeldung angekommen ist.
	if numFillTypes > 0 then
		Logging.info("Production Revamp: added %d fill types to existing stations", numFillTypes)
	end
end

FillTypeManager.loadModFillTypes = Utils.appendedFunction(FillTypeManager.loadModFillTypes, Revamp.resolveExtensionFillTypes)

---Sammelt die zusätzlichen Fülltypen, die zu einer vorhandenen Fülltyp-Liste dazugehören.
---@param fillTypes table Vorhandene Fülltypen als Menge (Schlüssel ist der Index)
---@param forStorage? boolean true, wenn nur Einträge mit addToStorage gelten sollen
---@return table additions Zusätzliche Fülltyp-Indizes, leer wenn nichts dazukommt
function Revamp.getExtraFillTypes(fillTypes, forStorage)
	local additions = {}

	for reference, entries in pairs(Revamp.extraFillTypes) do
		if fillTypes[reference] then
			for _, entry in ipairs(entries) do
				if (not forStorage or entry.addToStorage) and not fillTypes[entry.fillType] then
					additions[entry.fillType] = true
				end
			end
		end
	end

	return additions
end

---Prüft, ob eine Abladestelle mit einem zusätzlichen Fülltyp überhaupt etwas anfangen kann.
---Eine Stelle ohne eigenes Lager verkauft, was dort abgeladen wird - die braucht keinen Platz und nimmt den Fülltyp an.
---Eine Stelle mit Lager legt das Abgeladene dort hinein: sie nimmt den Fülltyp nur an, wenn eines ihrer Lager ihn auch wirklich führt.
---@param station table UnloadingStation-Instanz
---@param fillType number FillType-Index
---@return boolean canHandle true, wenn die Stelle den Fülltyp annehmen soll
function Revamp.getCanStationHandleFillType(station, fillType)
	local hasStorage = false

	for _, storage in pairs(station.targetStorages) do
		if storage.fillTypes[fillType] then
			return true
		end
		hasStorage = true
	end

	return not hasStorage
end

---Prüft, ob eine Placeable die Ware verarbeitet, statt sie zu verkaufen oder zu lagern.
---Eine Produktionsstätte nimmt nur an, was in einem ihrer Rezepte steht, und ein Tierstall nur, was seine Tiere als Futter kennen - eine fremde Ware könnten beide nicht gebrauchen, egal wie viel Platz im Lager wäre.
---Wer seine Frucht in ein Rezept bringen will, hängt sie über die eigene fillTypes.xml in die Fülltyp-Kategorie, die das Rezept als Zutat nennt; fürs Futter führt der Weg über das Futtersystem des Spiels.
---@param placeable table Placeable, zu der die Abladestelle gehört
---@return boolean isProcessing true, wenn die Placeable die Ware verarbeitet
function Revamp.getIsProcessingPlaceable(placeable)
	return placeable.spec_productionPoint ~= nil or placeable.spec_factory ~= nil or placeable.spec_husbandry ~= nil
end

---Nimmt die angemeldeten Fülltypen in eine Abladestelle auf, sobald sie fertig verdrahtet ist.
---Der Zeitpunkt ist bewusst die Anmeldung beim StorageSystem und nicht das Laden der Trigger: erst hier hängen die Ziel-Lager dran, und nur mit ihnen lässt sich entscheiden, ob die Ware überhaupt irgendwo hin kann.
---Er passt außerdem für beide Wege, mit denen eine Stelle entsteht - beim Laden der Karte und beim Bauen im laufenden Spiel.
---@param self table StorageSystem-Instanz
---@param superFunc function Ursprüngliche StorageSystem.addUnloadingStation
---@param station table Abladestelle, die sich anmeldet
---@param placeable table Placeable, zu der die Abladestelle gehört
---@return boolean success Rückgabe der ursprünglichen Funktion
function Revamp.addUnloadingStation(self, superFunc, station, placeable)
	local success = superFunc(self, station, placeable)

	if not success or next(Revamp.extraFillTypes) == nil or Revamp.getIsProcessingPlaceable(placeable) then
		return success
	end

	-- Je Trigger einzeln, weil eine Stelle mehrere mit ganz verschiedenen Listen haben kann (Schüttgut hier, Flüssiges dort).
	local addedFillTypes = {}
	local addedNames = {}
	for _, trigger in ipairs(station.unloadTriggers) do
		-- Ein Trigger ohne Liste nimmt ohnehin alles an.
		if trigger.fillTypes ~= nil then
			for fillType in pairs(Revamp.getExtraFillTypes(trigger.fillTypes)) do
				if Revamp.getCanStationHandleFillType(station, fillType) then
					trigger.fillTypes[fillType] = true

					-- Derselbe Fülltyp kann an mehreren Triggern derselben Stelle dazukommen, für die Meldung zählt er trotzdem nur einmal.
					if not addedFillTypes[fillType] then
						addedFillTypes[fillType] = true
						table.insert(addedNames, g_fillTypeManager:getFillTypeNameByIndex(fillType))
					end
				end
			end
		end
	end

	local changedTriggers = #addedNames > 0

	-- Eine Zeile je Stelle statt je Trigger: eine Verkaufsstelle mit vier Abladetriggern stünde sonst viermal im Log.
	if changedTriggers then
		Revamp.DebugText("addUnloadingStation(): %s nimmt jetzt auch %s an", station:getName(), table.concat(addedNames, ", "))
	end

	-- Vanillas eigene Sammelfunktion, damit auch das KI-Abladen dieselbe Liste bekommt.
	if changedTriggers then
		station:updateSupportedFillTypes()
	end

	-- Eine Verkaufsstelle ohne Abladetrigger führt ihre Fülltypen direkt am Element, dort gibt es nichts einzusammeln.
	if #station.unloadTriggers == 0 then
		for fillType in pairs(Revamp.getExtraFillTypes(station.supportedFillTypes)) do
			if Revamp.getCanStationHandleFillType(station, fillType) then
				station.supportedFillTypes[fillType] = true
			end
		end
	end

	-- Eine Verkaufsstelle braucht zu jedem angenommenen Fülltyp einen Preis, sonst taucht er weder im Menü auf noch lässt er sich verkaufen.
	local addedPrices = false
	if station.acceptedFillTypes ~= nil then
		for fillType in pairs(station.supportedFillTypes) do
			if station.acceptedFillTypes[fillType] == nil then
				station:addAcceptedFillType(fillType, g_fillTypeManager:getFillTypeByIndex(fillType).pricePerLiter, false, false)
				addedPrices = true
			end
		end
	end

	-- Die Preiskurven baut die Verkaufsstelle am Ende ihres Ladens für die damals bekannten Fülltypen auf.
	-- Ein später dazugekommener hätte keine, und die Preisaktualisierung greift jeden Frame ungeprüft darauf zu (SellingStation:updateFillTypePrice).
	if addedPrices and station.initPricingDynamics ~= nil then
		station:initPricingDynamics()
	end

	return success
end

StorageSystem.addUnloadingStation = Utils.overwrittenFunction(StorageSystem.addUnloadingStation, Revamp.addUnloadingStation)

---Nimmt die angemeldeten Fülltypen in ein Lager auf, aber nur wo sie sich einen gemeinsamen Topf teilen.
---Ein Lager, in dem der Referenz-Fülltyp eine eigene, fest zugeteilte Menge hat, bleibt unangetastet: dort würde ein zusätzlicher Fülltyp entweder ohne Kapazität dastehen oder eine erfinden, die der Kartenbauer nie vorgesehen hat.
---@param self table Storage-Instanz
---@param superFunc function Ursprüngliche Storage.load
---@param components table Komponenten der Placeable
---@param xmlFile table XMLFile der Placeable
---@param key string XML-Pfad des Lagers
---@param i3dMappings table i3d-Zuordnungen der Placeable
---@param baseDirectory string Verzeichnis der Placeable
---@return boolean success true, wenn das Lager geladen wurde
function Revamp.loadStorage(self, superFunc, components, xmlFile, key, i3dMappings, baseDirectory)
	if not superFunc(self, components, xmlFile, key, i3dMappings, baseDirectory) then
		return false
	end

	-- Nur die Fülltypen ohne eigene Kapazität als Anknüpfungspunkt nehmen, damit auch ein gemischt aufgebautes Lager richtig behandelt wird.
	local sharedFillTypes = {}
	for fillType in pairs(self.fillTypes) do
		if self.capacities[fillType] == nil then
			sharedFillTypes[fillType] = true
		end
	end

	for fillType in pairs(Revamp.getExtraFillTypes(sharedFillTypes, true)) do
		if not self.fillTypes[fillType] then
			self.fillTypes[fillType] = true
			self.fillLevels[fillType] = 0
			self.fillLevelsLastSynced[fillType] = 0
			self.fillLevelsLastPublished[fillType] = 0
			table.insert(self.sortedFillTypes, fillType)

			-- An einem gebauten Silo lässt sich nirgends ablesen, was es annimmt - ohne diese Zeile bliebe nur, die Ware tatsächlich hinzufahren.
			Revamp.DebugText("loadStorage(): %s in ein Lager mit %d l Gesamtkapazitaet aufgenommen (%s)", g_fillTypeManager:getFillTypeNameByIndex(fillType), self.capacity, key)
		end
	end

	table.sort(self.sortedFillTypes)

	return true
end

Storage.load = Utils.overwrittenFunction(Storage.load, Revamp.loadStorage)
