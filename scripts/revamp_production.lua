-- Erweitert die Vanilla-Produktions-Ladefunktion um die Revamp-eigenen Rezept-Felder (Mix-Gruppen, Booster, Fülltyp-Kategorien als Zutat, erzwungener Primär-Output, Sichtbarkeit).
-- Die Vanilla-Funktion wird dafür aufgerufen statt komplett neu geschrieben, damit alles, was Vanilla schon selbst leistet (Storage/Verkaufsstelle/Palettenspawner/Validierung), unverändert bleibt.
--
-- Die FeedMixer-Anbindung wird hier nicht geladen, der Tier-Trigger steht in revamp_animals.lua.
-- Mix-Gruppen, Booster/Master-Booster und die Wetter-/Zeit-Modi wertet Revamp.updateProduction weiter unten aus, die Modus-Berechnung selbst steht in revamp_productionModes.lua.

Revamp.MIX_BOOST = 98
Revamp.MIX_MASTER = 99

function Revamp.findProductionEntryByType(entries, fillType)
	for _, entry in ipairs(entries) do
		if entry.type == fillType then
			return entry
		end
	end
	return nil
end

function Revamp.registerProductionXMLPaths(schema, basePath)
	schema:register(XMLValueType.BOOL, basePath .. ".productions#hideFromMenu", "Produktionsstätte ist standardmäßig im Menü versteckt", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions#autoStart", "Produktionsstätte startet automatisch", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?)#hideFromMenu", "Produktionslinie ist standardmäßig im Menü versteckt", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?)#autoStart", "Produktionslinie startet automatisch", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?)#sharedThroughputCapacity", "Nimmt die Produktionslinie an sharedThroughputCapacity teil", true)
	schema:register(XMLValueType.STRING, basePath .. ".productions#mixMode", "Standard-Auswahlmodus für Mix-Gruppen (ASC/DESC/MOST/LEAST)", "ASC")
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?)#mixMode", "Auswahlmodus für Mix-Gruppen dieser Produktionslinie (ASC/DESC/MOST/LEAST)", "ASC")
	schema:register(XMLValueType.STRING, basePath .. ".productions#boostMode", "Standard-Auswahlmodus bei mehreren gleichzeitig verfügbaren Master-Booster-Inputs (ASC/DESC/MOST/LEAST)", "ASC")
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?)#boostMode", "Auswahlmodus für den Master-Booster dieser Produktionslinie (ASC/DESC/MOST/LEAST)", "ASC")
	schema:register(XMLValueType.STRING, basePath .. ".productions#modes", "Standard-Modi der Produktionslinien (hourly, seasonal, monthly, limitBoosters, sun, night, rain, wind, temp, tempNegative)", "")
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?)#modes", "Modi dieser Produktionslinie (hourly, seasonal, monthly, limitBoosters, sun, night, rain, wind, temp, tempNegative)", "")
	schema:register(XMLValueType.STRING, basePath .. ".productions#startHours", "Standard-Beginn der Öffnungszeiten, mehrere Zeitfenster durch Leerzeichen getrennt", "0")
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?)#startHours", "Beginn der Öffnungszeiten dieser Produktionslinie, mehrere Zeitfenster durch Leerzeichen getrennt", "0")
	schema:register(XMLValueType.STRING, basePath .. ".productions#endHours", "Standard-Ende der Öffnungszeiten, mehrere Zeitfenster durch Leerzeichen getrennt", "24")
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?)#endHours", "Ende der Öffnungszeiten dieser Produktionslinie, mehrere Zeitfenster durch Leerzeichen getrennt", "24")
	schema:register(XMLValueType.STRING, basePath .. ".productions#seasons", "Standard-Jahreszeiten, in denen produziert wird (1 Frühling bis 4 Winter)", "1 2 3 4")
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?)#seasons", "Jahreszeiten, in denen diese Produktionslinie läuft (1 Frühling bis 4 Winter)", "1 2 3 4")
	schema:register(XMLValueType.STRING, basePath .. ".productions#months", "Standard-Monate, in denen produziert wird (1 März bis 12 Februar)", "1 2 3 4 5 6 7 8 9 10 11 12")
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?)#months", "Monate, in denen diese Produktionslinie läuft (1 März bis 12 Februar)", "1 2 3 4 5 6 7 8 9 10 11 12")
	schema:register(XMLValueType.FLOAT, basePath .. ".productions#weatherFactor", "Standard-Skalierung des Wetterfaktors", 1)
	schema:register(XMLValueType.FLOAT, basePath .. ".productions.production(?)#weatherFactor", "Skalierung des Wetterfaktors dieser Produktionslinie", 1)
	schema:register(XMLValueType.FLOAT, basePath .. ".productions#minPower", "Standard-Untergrenze des Wetterfaktors (Grundlast auch bei schlechtestem Wetter)", 0)
	schema:register(XMLValueType.FLOAT, basePath .. ".productions.production(?)#minPower", "Untergrenze des Wetterfaktors dieser Produktionslinie (Grundlast auch bei schlechtestem Wetter)", 0)
	schema:register(XMLValueType.FLOAT, basePath .. ".productions#maxPower", "Standard-Obergrenze des Wetterfaktors", 1)
	schema:register(XMLValueType.FLOAT, basePath .. ".productions.production(?)#maxPower", "Obergrenze des Wetterfaktors dieser Produktionslinie", 1)
	schema:register(XMLValueType.BOOL, basePath .. ".storage#allowBuyingForCategories", "Fülltypen, die nur über fillTypeCategories im Lager sind, dürfen im Verwalten-Dialog gekauft werden", true)
	schema:register(XMLValueType.BOOL, basePath .. ".storage#allowSellingForCategories", "Fülltypen, die nur über fillTypeCategories im Lager sind, dürfen im Verwalten-Dialog verkauft werden", true)
	schema:register(XMLValueType.BOOL, basePath .. ".storage.capacity(?)#allowBuying", "Fülltyp darf im Verwalten-Dialog gekauft werden", true)
	schema:register(XMLValueType.BOOL, basePath .. ".storage.capacity(?)#allowSelling", "Fülltyp darf im Verwalten-Dialog verkauft werden", true)
	schema:register(XMLValueType.STRING, basePath .. ".storage.capacity(?)#weatherModes", "Wetter-Modus, der den Bestand dieses Fülltyps ohne Produktion verändert (sun, night, rain, wind, temp, tempNegative)", "")
	schema:register(XMLValueType.FLOAT, basePath .. ".storage.capacity(?)#weatherAmount", "Menge pro Stunde bei vollem Wetterfaktor, negative Werte sind ein wetterabhängiger Verlust", 0)
	schema:register(XMLValueType.FLOAT, basePath .. ".storage.capacity(?)#weatherFactor", "Skalierung der wetterabhängigen Bestandsänderung dieses Fülltyps", 1)
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?).inputs.input(?)#mix", "Mix-Gruppe des Inputs (Zahl, 'boost' oder 'master')", "0")
	schema:register(XMLValueType.FLOAT, basePath .. ".productions.production(?).inputs.input(?)#boostFactor", "Multiplikator für Booster/Master-Booster (> 0, 1 ist unzulässig weil wirkungslos) - Pflichtfeld bei mix='boost'/'master'")
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).inputs.input(?)#rngAffected", "Input ist von einem Zufallsfaktor betroffen", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).inputs.input(?)#hideFromMenu", "Input ist standardmäßig im Menü versteckt", false)
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?).inputs.input(?)#fillTypeCategory", "Fülltyp-Kategorie(n) als Zutat statt eines einzelnen Fülltyps, mehrere durch Leerzeichen getrennt - braucht zwingend eine Mix-Gruppe über 'mix'")
	schema:register(XMLValueType.L10N_STRING, basePath .. ".productions.production(?).inputs.input(?)#title", "Überschrift der Mix-Gruppe dieses Inputs im Rezept, statt der Standardüberschrift 'Mix-Gruppe N'")
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).outputs.output(?)#primaryProductFillType", "Erzwingt diesen Output als primären FillType", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).outputs.output(?)#boost", "Output ist von einem Booster betroffen", true)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).outputs.output(?)#rngAffected", "Output ist von einem Zufallsfaktor betroffen", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).outputs.output(?)#hideFromMenu", "Output ist standardmäßig im Menü versteckt", false)

	Revamp.registerSpawnerXMLPaths(schema)
	Revamp.registerAnimalXMLPaths(schema, basePath)
end

ProductionPoint.registerXMLPaths = Utils.prependedFunction(ProductionPoint.registerXMLPaths, Revamp.registerProductionXMLPaths)

-- Attribute eines Kategorie-Inputs, die beim Auflösen an jede daraus erzeugte Einzel-Zutat weitergereicht werden.
Revamp.PRODUCTION_INPUT_ATTRIBUTES = {"amount", "mix", "boostFactor", "rngAffected", "hideFromMenu", "title"}

---Kopiert die Attribute eines Kategorie-Inputs auf eine daraus erzeugte Einzel-Zutat.
---Bewusst als Rohtext über eine feste Attributliste: der Wert soll unverändert durchgereicht werden, und ein hier unbekanntes Attribut soll nicht mit einem falsch geratenen Typ neu geschrieben werden.
---@param xmlFile table XML-Datei der Placeable
---@param sourceKey string Pfad des Kategorie-Inputs
---@param targetKey string Pfad der neuen Einzel-Zutat
function Revamp.copyProductionInputAttributes(xmlFile, sourceKey, targetKey)
	for _, attribute in ipairs(Revamp.PRODUCTION_INPUT_ATTRIBUTES) do
		local value = xmlFile:getString(sourceKey .. "#" .. attribute)
		if value ~= nil then
			xmlFile:setString(targetKey .. "#" .. attribute, value)
		end
	end
end

---Löst Zutaten mit #fillTypeCategory in einzelne <input>-Knoten auf, noch bevor der Vanilla-Loader die Rezepte überhaupt sieht.
---Eine Kategorie als Zutat bedeutet "eine beliebige Sorte daraus" - genau das, was eine Mix-Gruppe zur Laufzeit ohnehin schon leistet.
---Statt dafür einen zweiten, dynamischen Auswahlpfad zu bauen, wird die Kategorie deshalb einmalig beim Laden zu ganz normalen Zutaten derselben Mix-Gruppe aufgelöst.
---Der Inhalt einer Kategorie steht nach dem Laden der Map ohnehin fest, und die konkrete Fülltyp-Liste wird auch sonst schon beim Laden gebraucht (Abladestelle, Lager, Rezept-Anzeige).
---Das Auflösen passiert vor superFunc, weil Vanilla #fillTypeCategory nicht kennt: es wirft eine Zutat ohne gültiges #fillType weg und verwirft eine Rezeptlinie sogar komplett ("No inputs for production"), wenn danach keine Zutat mehr übrig ist.
---Danach sieht Vanilla nur noch gewöhnliche Zutaten und erledigt seine eigene Buchführung (inputFillTypeIds, Prüfung der Abladestelle) unverändert mit.
---@param xmlFile table XML-Datei der Placeable
---@param key string Basis-Pfad des productionPoint-Knotens
function Revamp.expandFillTypeCategoryInputs(xmlFile, key)
	xmlFile:iterate(key .. ".productions.production", function(_, productionKey)
		local inputsKey = productionKey .. ".inputs"
		local usedFillTypes = {}
		local categoryInputs = {}
		local numInputs = 0

		xmlFile:iterate(inputsKey .. ".input", function(_, inputKey)
			local fillTypeName = xmlFile:getString(inputKey .. "#fillType")
			if fillTypeName ~= nil then
				local fillType = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
				if fillType ~= nil then
					usedFillTypes[fillType] = true
				end
			elseif xmlFile:getString(inputKey .. "#fillTypeCategory") ~= nil then
				table.insert(categoryInputs, {key = inputKey, index = numInputs})
			end
			numInputs = numInputs + 1
		end)

		local emptyCategoryIndices = {}
		for _, categoryInput in ipairs(categoryInputs) do
			local inputKey = categoryInput.key
			local categoryNames = xmlFile:getString(inputKey .. "#fillTypeCategory")
			local mixValue = xmlFile:getString(inputKey .. "#mix")
			local mixUpper = mixValue ~= nil and mixValue:upper() or nil
			local mixGroup = tonumber(mixValue)
			-- Ohne Mix-Gruppe würde die Kategorie zu lauter einzeln zwingend benötigten Zutaten aufgelöst, also "alle Sorten der Kategorie gleichzeitig".
			-- Das ist nie gemeint und fällt dem Modder am Ergebnis kaum auf, deshalb hier ein harter Fehler statt einer stillen Annahme.
			if mixUpper ~= "BOOST" and mixUpper ~= "MASTER" and (mixGroup == nil or mixGroup == 0) then
				Logging.xmlError(xmlFile, "Production Revamp: input '%s' with fillTypeCategory '%s' needs a mix group - set 'mix' to a group number, 'boost' or 'master'", inputKey, categoryNames)
				table.insert(emptyCategoryIndices, categoryInput.index)
			else
				-- Die Warnung von getFillTypesByCategoryNames wird bewusst nicht genutzt, ein unbekannter Kategoriename wird stattdessen unten am leeren Ergebnis erkannt.
				-- Vanilla füttert diese Warnung nämlich über string.format mit dem Ergebnis der fehlgeschlagenen Suche statt mit dem gesuchten Namen, was aus einem Tippfehler im Rezept einen Absturz beim Laden machen kann.
				local fillTypes = g_fillTypeManager:getFillTypesByCategoryNames(categoryNames)
				-- getFillTypesByCategoryNames liefert die Fülltypen in pairs()-Reihenfolge - sortiert ist die Reihenfolge im Rezept und damit auch die ASC/DESC-Auswahl der Mix-Gruppe vorhersagbar.
				table.sort(fillTypes)

				local numAdded = 0
				for _, fillType in ipairs(fillTypes) do
					-- Ein Fülltyp kann pro Rezeptlinie nur einmal Zutat sein, sonst hätten zwei Einträge in production.inputs dieselbe Identität und die Attribut-Zuordnung träfe immer nur den ersten davon.
					if not usedFillTypes[fillType] then
						usedFillTypes[fillType] = true
						local targetKey = inputKey
						if numAdded > 0 then
							-- Der erste Fülltyp übernimmt den vorhandenen Knoten, damit die Kategorie an ihrer Stelle im Rezept stehen bleibt, alle weiteren werden hinten angehängt.
							targetKey = string.format("%s.input(%d)", inputsKey, numInputs)
							numInputs = numInputs + 1
							Revamp.copyProductionInputAttributes(xmlFile, inputKey, targetKey)
						end
						xmlFile:setString(targetKey .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(fillType))
						numAdded = numAdded + 1
					end
				end

				if #fillTypes == 0 then
					Logging.xmlError(xmlFile, "Production Revamp: input '%s' has an unknown or empty fillTypeCategory '%s'", inputKey, categoryNames)
					table.insert(emptyCategoryIndices, categoryInput.index)
				elseif numAdded == 0 then
					Logging.xmlError(xmlFile, "Production Revamp: fillTypeCategory '%s' of input '%s' adds no new fillType, all of them are already an input of this production", categoryNames, inputKey)
					table.insert(emptyCategoryIndices, categoryInput.index)
				else
					Revamp.DebugText("expandFillTypeCategoryInputs(): %s loest '%s' in %d Zutaten auf", inputKey, categoryNames, numAdded)
				end
			end
		end

		-- Ein Kategorie-Knoten, der nicht aufgelöst werden konnte, brächte keinen Fülltyp mit und würde von Vanilla nur noch eine zweite, irreführende Fehlermeldung auslösen.
		-- Absteigend entfernen, weil das Entfernen eines Knotens alle dahinter liegenden Indizes nachrücken lässt.
		for i = #emptyCategoryIndices, 1, -1 do
			xmlFile:removeProperty(string.format("%s.input(%d)", inputsKey, emptyCategoryIndices[i]))
		end
	end)
end

-- Pfade, unter denen die Rezepte einer Placeable-XML stehen können: einmal direkt und einmal in der ersten Ausbaustufe einer konfigurierbaren Produktionsstätte.
-- Zweiteres liest auch Vanilla nur für die Ladenansicht aus, weil dort noch keine Ausbaustufe gewählt ist.
Revamp.PRODUCTION_STORE_SPEC_PATHS = {
	"placeable.productionPoint.productions.production",
	"placeable.productionPoint.productionPointConfigurations.productionPointConfiguration(0).productionPoint.productions.production"
}

---Sammelt für die Ladenansicht die Zutaten aller Rezepte einer Placeable-XML, inklusive der Fülltypen, die im Rezept nur über eine Kategorie stehen.
---Vanillas eigene Fassung liest die Rezepte dafür direkt aus der XML statt über ProductionPoint:load und kennt #fillTypeCategory an dieser Stelle nicht:
---eine Zutat ohne #fillType wird dort ungeprüft als Tabellenschlüssel gesetzt, was beim Aufschlagen der Produktionen im Baumenü mit "table index is nil" abbricht und das Menü unbedienbar zurücklässt.
---Vollständig ersetzt statt umschlossen, weil die Kategorie mitten in der Schleife aufgelöst werden muss - das Ergebnis der ursprünglichen Fassung ließe sich nachträglich nicht mehr ergänzen.
---@param xmlFile table XMLFile der Placeable
---@param customEnvironment string Mod-Umgebung der Placeable
---@param baseDirectory string Verzeichnis der Placeable
---@return table|nil fillTypeNames Menge der Zutaten-Namen, nil wenn die Placeable gar keine Zutaten hat
function Revamp.loadSpecValueInputFillTypes(xmlFile, customEnvironment, baseDirectory) ---@diagnostic disable-line: unused-local
	local fillTypeNames = nil

	for _, productionsPath in ipairs(Revamp.PRODUCTION_STORE_SPEC_PATHS) do
		xmlFile:iterate(productionsPath, function(_, productionKey)
			xmlFile:iterate(productionKey .. ".inputs.input", function(_, inputKey)
				local fillTypeName = xmlFile:getValue(inputKey .. "#fillType")
				if fillTypeName ~= nil then
					fillTypeNames = fillTypeNames or {}
					fillTypeNames[fillTypeName] = true
					return
				end

				-- Bewusst ohne den warning-Parameter: eine unbekannte Kategorie liefert dann einfach nichts, gemeldet wird sie ohnehin beim Laden der Produktionsstätte selbst.
				-- Vanillas Warnung an dieser Stelle würde ihren eigenen Platzhalter mit dem gescheiterten Suchergebnis füllen und damit über einen Tippfehler im Rezept stolpern.
				for _, fillType in ipairs(g_fillTypeManager:getFillTypesByCategoryNames(xmlFile:getValue(inputKey .. "#fillTypeCategory"))) do
					fillTypeNames = fillTypeNames or {}
					fillTypeNames[g_fillTypeManager:getFillTypeNameByIndex(fillType)] = true
				end
			end)
		end)
	end

	return fillTypeNames
end

-- Die Ladenansicht merkt sich diese Funktion beim Registrieren ihrer Spalten (PlaceableProductionPoint.initSpecialization), das Ersetzen muss also vorher passieren - Mod-Skripte laufen früh genug dafür.
ProductionPoint.loadSpecValueInputFillTypes = Revamp.loadSpecValueInputFillTypes

function Revamp.loadProductionPoint(self, superFunc, components, xmlFile, key, customEnv, i3dMappings)
	Revamp.expandFillTypeCategoryInputs(xmlFile, key)

	if not superFunc(self, components, xmlFile, key, customEnv, i3dMappings) then
		return false
	end

	Revamp.loadSpawnerConfig(self, xmlFile, components, i3dMappings)

	local pointHideFromMenu = xmlFile:getBool(key .. ".productions#hideFromMenu", false)
	local pointAutoStart = xmlFile:getBool(key .. ".productions#autoStart", false)
	local pointMixMode = xmlFile:getValue(key .. ".productions#mixMode", "ASC"):upper()
	local pointBoostMode = xmlFile:getValue(key .. ".productions#boostMode", "ASC"):upper()

	-- Vorgabewerte für alle Rezeptlinien dieses Produktionspunktes, jede Linie kann sie einzeln überschreiben.
	local pointModeDefaults = {
		modes = xmlFile:getValue(key .. ".productions#modes", ""),
		startHours = xmlFile:getValue(key .. ".productions#startHours", "0"),
		endHours = xmlFile:getValue(key .. ".productions#endHours", "24"),
		seasons = xmlFile:getValue(key .. ".productions#seasons", "1 2 3 4"),
		months = xmlFile:getValue(key .. ".productions#months", "1 2 3 4 5 6 7 8 9 10 11 12"),
		weatherFactor = xmlFile:getValue(key .. ".productions#weatherFactor", 1),
		minPower = xmlFile:getValue(key .. ".productions#minPower", 0),
		maxPower = xmlFile:getValue(key .. ".productions#maxPower", 1)
	}

	Revamp.loadWeatherStorage(self, xmlFile, key)
	Revamp.loadBuySellPermissions(self, xmlFile, key)
	Revamp.loadAnimals(self, xmlFile, key, components, i3dMappings)

	-- Öffnungszeiten aller Rezeptlinien zusammen: der Betrieb gilt als offen, solange mindestens eine Linie laufen darf.
	self.openingHoursTable = {}

	xmlFile:iterate(key .. ".productions.production", function(_, productionKey)
		local id = xmlFile:getValue(productionKey .. "#id")
		local production = self.productionsIdToObj[id]
		if production == nil then
			return -- von Vanilla schon abgelehnt (fehlende/doppelte id, kein Input, ungültiger FillType)
		end

		production.sharedThroughputCapacity = xmlFile:getValue(productionKey .. "#sharedThroughputCapacity", self.sharedThroughputCapacity)
		production.mixMode = xmlFile:getValue(productionKey .. "#mixMode", pointMixMode):upper()
		production.boostMode = xmlFile:getValue(productionKey .. "#boostMode", pointBoostMode):upper()
		production.hideFromMenu = xmlFile:getBool(productionKey .. "#hideFromMenu", pointHideFromMenu)
		production.autoStart = xmlFile:getBool(productionKey .. "#autoStart", pointAutoStart)
		production.master = false

		Revamp.loadProductionModes(production, xmlFile, productionKey, pointModeDefaults)
		for hour in pairs(production.hoursTable) do
			self.openingHoursTable[hour] = true
		end

		if production.autoStart or production.hideFromMenu then
			production.status = ProductionPoint.PROD_STATUS.RUNNING
			table.insert(self.activeProductions, production)
		end

		xmlFile:iterate(productionKey .. ".inputs.input", function(_, inputKey)
			local fillType = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getValue(inputKey .. "#fillType"))
			if fillType == nil then
				return -- von Vanilla schon abgelehnt/geloggt
			end
			local input = Revamp.findProductionEntryByType(production.inputs, fillType)
			if input == nil then
				return
			end

			local mixValue = xmlFile:getValue(inputKey .. "#mix", "0")
			if mixValue:upper() == "BOOST" then
				input.mix = Revamp.MIX_BOOST
			elseif mixValue:upper() == "MASTER" then
				input.mix = Revamp.MIX_MASTER
				production.master = true
			else
				input.mix = tonumber(mixValue) or 0
			end
			if input.mix == Revamp.MIX_BOOST or input.mix == Revamp.MIX_MASTER then
				-- boostFactor ist ein reiner Multiplikator (1 = neutral), deshalb ist der Wert 1 hier
				-- absichtlich kein gültiger Wert - er hätte ohnehin keine Wirkung, ein vergessenes
				-- Attribut soll also nicht stillschweigend als "kein Boost" durchgehen.
				local boostFactor = xmlFile:getValue(inputKey .. "#boostFactor")
				if boostFactor == nil or boostFactor <= 0 or boostFactor == 1 then
					Logging.xmlError(xmlFile, "Production Revamp: boostFactor for '%s' must be a positive number other than 1 (1 would have no effect) - got '%s'", inputKey, tostring(boostFactor))
					boostFactor = 1
				end
				input.boostFactor = boostFactor
			else
				input.boostFactor = 0
			end
			input.rngAffected = xmlFile:getBool(inputKey .. "#rngAffected", false)
			input.hideFromMenu = xmlFile:getBool(inputKey .. "#hideFromMenu", false)
			input.color = 0

			-- Ein gesetzter Titel ersetzt in der Rezept-Anzeige die Standardüberschrift "Mix-Gruppe N".
			-- Er hängt an der Zutat statt an der Rezeptlinie, weil eine Linie mehrere Mix-Gruppen haben kann - die erste Zutat einer Gruppe, die einen Titel mitbringt, bestimmt ihn.
			local title = xmlFile:getValue(inputKey .. "#title", nil, customEnv, false)
			if title ~= nil and input.mix ~= 0 and input.mix ~= Revamp.MIX_BOOST and input.mix ~= Revamp.MIX_MASTER then
				production.mixGroupTitles = production.mixGroupTitles or {}
				if production.mixGroupTitles[input.mix] == nil then
					production.mixGroupTitles[input.mix] = title
				end
			end
		end)

		xmlFile:iterate(productionKey .. ".outputs.output", function(_, outputKey)
			local fillType = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getValue(outputKey .. "#fillType"))
			if fillType == nil then
				return -- von Vanilla schon abgelehnt/geloggt
			end
			local output = Revamp.findProductionEntryByType(production.outputs, fillType)
			if output == nil then
				return
			end

			output.boost = xmlFile:getValue(outputKey .. "#boost", true)
			output.rngAffected = xmlFile:getBool(outputKey .. "#rngAffected", false)
			output.hideFromMenu = xmlFile:getBool(outputKey .. "#hideFromMenu", false)

			if xmlFile:getBool(outputKey .. "#primaryProductFillType", false) then
				production.primaryProductFillType = fillType
			end
		end)

		-- Absicherung für Zutaten und Erzeugnisse, die die obigen Iterationen nicht erreichen, weil sie im XML gar kein #fillType-Attribut haben.
		-- Revamp.expandFillTypeCategoryInputs deckt den eigenen fillTypeCategory-Fall zwar ab, ein anderer Mod kann aber jederzeit weitere Einträge beisteuern.
		-- Ohne diese Absicherung bliebe input.mix (bzw. output.boost) bei solchen Einträgen nil statt 0/true, was in Revamp.updateProduction und der Rezept-Anzeige zu "table index is nil" führt, sobald nil mit 0/98/99 verglichen wird.
		for _, input in ipairs(production.inputs) do
			if input.mix == nil then
				input.mix = 0
				input.boostFactor = 0
				input.rngAffected = false
				input.hideFromMenu = false
				input.color = 0
			end
		end
		for _, output in ipairs(production.outputs) do
			if output.boost == nil then
				output.boost = true
				output.rngAffected = false
				output.hideFromMenu = false
			end
		end

		-- Erst hier, weil die Flags die fertigen Zutaten der Linie brauchen (Mix-Gruppen, Booster, Master-Booster).
		Revamp.updateRecipeChoiceFlags(production)
	end)

	return true
end

ProductionPoint.load = Utils.overwrittenFunction(ProductionPoint.load, Revamp.loadProductionPoint)

---Lässt eine Linie, die von selbst laufen soll, nicht mehr abschalten.
---Das betrifft drei Stellen, die sie sonst wieder ausmachen würden: Vanillas ProductionPoint:setOwnerFarmId schaltet beim Bauen im laufenden Spiel jede Linie ab,
---ein Spielstand kann ein gespeichertes "aus" von früher mitbringen (etwa wenn autoStart erst mit einer neuen Fassung der Produktion dazugekommen ist),
---und im Menü hängt an einer gewählten Linie Vanillas Deaktivieren-Knopf (der zusätzlich verschwindet, siehe Revamp.removeActivateButtonForAutoStart).
---Eine versteckte Linie gehört genauso dazu: sie taucht im Menü gar nicht auf, der Spieler könnte sie also nie wieder einschalten.
---@param self table ProductionPoint-Instanz
---@param superFunc function Ursprüngliche ProductionPoint.setProductionState
---@param productionId string Id der Rezeptlinie
---@param state boolean true schaltet ein, false aus
---@param noEventSend? boolean true unterdrückt das Netzwerk-Event
function Revamp.setProductionState(self, superFunc, productionId, state, noEventSend)
	local production = self.productionsIdToObj[productionId]
	if not state and production ~= nil and (production.autoStart or production.hideFromMenu) then
		return
	end

	superFunc(self, productionId, state, noEventSend)
end

ProductionPoint.setProductionState = Utils.overwrittenFunction(ProductionPoint.setProductionState, Revamp.setProductionState)

---Verarbeitet eine einzelne Rezeptlinie für den aktuellen Takt.
---Ausgelagert aus Revamp.updateProduction, damit eine gerade angehaltene Linie einfach per return übersprungen werden kann.
---@param self table ProductionPoint-Instanz
---@param production table Rezeptlinie aus self.activeProductions
---@param minuteFactorDt number Vergangene Spielminuten seit dem letzten Takt
---@param numSharedThroughputCapacity number Anzahl der Linien, die sich die Durchsatzkapazität gerade teilen
function Revamp.updateSingleProduction(self, production, minuteFactorDt, numSharedThroughputCapacity)
	if production.modeStatus ~= nil then
		-- Eine angehaltene Linie verbraucht nichts, erzeugt nichts und verursacht auch keine Betriebskosten - anders als bei fehlenden Zutaten steht hier nicht die Produktion still, sondern der ganze Betrieb.
		if self.isOwned and production.status ~= production.modeStatus then
			Revamp.DebugText("updateSingleProduction(): %s haelt an, Status=%d", production.id, production.modeStatus)
			production.status = production.modeStatus
			self.owningPlaceable:productionStatusChanged(production, production.modeStatus)
			self:setProductionStatus(production.id, production.modeStatus)
		end
		return
	end

	local cyclesPerMinuteMinuteFactor = production.cyclesPerMinute * minuteFactorDt
	if self.sharedThroughputCapacity and production.sharedThroughputCapacity then
		cyclesPerMinuteMinuteFactor = cyclesPerMinuteMinuteFactor / numSharedThroughputCapacity
	end
	if production.weatherFactorCurrent ~= nil then
		cyclesPerMinuteMinuteFactor = cyclesPerMinuteMinuteFactor * production.weatherFactorCurrent
	end

	-- Master-Booster zuerst ermitteln: seine eigene Bestandsprüfung läuft unskaliert (er soll
	-- sich nicht selbst hochskalieren), alles andere in dieser Produktion skaliert danach mit.
	local masterFactor = 1
	local masterConsume = nil
	if production.master then
		local masterWinner = nil
		for x = 1, #production.inputs do
			local input = production.inputs[x]
			if input.mix == Revamp.MIX_MASTER then
				local fillLevel = self:getFillLevel(input.type)
				input.boostSatisfied = fillLevel >= input.amount * cyclesPerMinuteMinuteFactor
				if input.boostSatisfied then
					if production.boostMode == "MOST" then
						if masterWinner == nil or input.boostFactor > production.inputs[masterWinner].boostFactor then
							masterWinner = x
						end
					elseif production.boostMode == "LEAST" then
						if masterWinner == nil or input.boostFactor < production.inputs[masterWinner].boostFactor then
							masterWinner = x
						end
					else
						masterFactor = masterFactor * input.boostFactor
						masterConsume = masterConsume or {}
						masterConsume[x] = true
					end
				end
			end
		end
		if masterWinner ~= nil then
			masterFactor = production.inputs[masterWinner].boostFactor
			masterConsume = {[masterWinner] = true}
		end
	end
	production.masterFactor = masterFactor

	-- Skalierter Takt für alles außer dem Master-Input selbst (s.o.)
	local factor = cyclesPerMinuteMinuteFactor * masterFactor

	local enoughInputResources = true
	local enoughOutputSpace = true
	-- Mix-Gruppen-ID -> Index des production.inputs-Eintrags, der laut mixMode "gewinnt"
	local groupSelection = {}
	local groupFillLevel = {}
	local seenGroups = {}
	local booster = 1
	local satisfiedBoosters = {}

	for x = 1, #production.inputs do
		local input = production.inputs[x]
		if input.mix == 0 then
			local fillLevel = self:getFillLevel(input.type)
			if self.isOwned and fillLevel < input.amount * factor then
				enoughInputResources = false
			end
		elseif input.mix == Revamp.MIX_BOOST then
			local fillLevel = self:getFillLevel(input.type)
			input.boostSatisfied = fillLevel >= input.amount * factor
			if input.boostSatisfied then
				table.insert(satisfiedBoosters, x)
			end
		elseif input.mix ~= Revamp.MIX_MASTER then
			seenGroups[input.mix] = true
			local fillLevel = self:getFillLevel(input.type)
			local needAmount = input.amount * factor
			if fillLevel >= needAmount then
				local currentWinner = groupSelection[input.mix]
				if currentWinner == nil
					or production.mixMode == "DESC"
					or (production.mixMode == "MOST" and fillLevel > groupFillLevel[input.mix])
					or (production.mixMode == "LEAST" and fillLevel < groupFillLevel[input.mix]) then
					groupSelection[input.mix] = x
					groupFillLevel[input.mix] = fillLevel
				end
			end
		end
	end
	-- Ohne den Modus limitBoosters trägt jeder ausreichend bevorratete Booster seinen eigenen Faktor bei und mehrere gleichzeitig aktive multiplizieren sich.
	-- Mit limitBoosters zählt und verbraucht sich nur ein einziger Booster, ausgewählt nach boostMode: bei MOST/LEAST der stärkste bzw. schwächste Faktor, bei ASC/DESC der erste bzw. letzte in der Reihenfolge des Rezepts.
	if production.limitBoosters and #satisfiedBoosters > 0 then
		local winner = satisfiedBoosters[1]
		for _, x in ipairs(satisfiedBoosters) do
			if production.boostMode == "MOST" then
				if production.inputs[x].boostFactor > production.inputs[winner].boostFactor then
					winner = x
				end
			elseif production.boostMode == "LEAST" then
				if production.inputs[x].boostFactor < production.inputs[winner].boostFactor then
					winner = x
				end
			elseif production.boostMode == "DESC" then
				winner = x
			end
		end
		for _, x in ipairs(satisfiedBoosters) do
			production.inputs[x].boostSatisfied = x == winner
		end
		booster = production.inputs[winner].boostFactor
	else
		for _, x in ipairs(satisfiedBoosters) do
			booster = booster * production.inputs[x].boostFactor
		end
	end
	production.boosterFactor = booster

	production.mixGroupSatisfied = production.mixGroupSatisfied or {}
	for mix in pairs(seenGroups) do
		production.mixGroupSatisfied[mix] = groupSelection[mix] ~= nil

		if groupSelection[mix] == nil then
			if self.isOwned then
				enoughInputResources = false
			end
		else
			local winnerType = production.inputs[groupSelection[mix]].type
			production.mixGroupWinnerType = production.mixGroupWinnerType or {}
			if production.mixGroupWinnerType[mix] ~= winnerType then
				production.mixGroupWinnerType[mix] = winnerType
				Revamp.DebugText("updateSingleProduction(): %s Mix-Gruppe %d waehlt jetzt %s (mixMode=%s)", production.id, mix, g_fillTypeManager:getFillTypeNameByIndex(winnerType), production.mixMode)
			end
		end
	end

	if enoughInputResources == false and self.isOwned then
		if production.status ~= ProductionPoint.PROD_STATUS.MISSING_INPUTS then
			production.status = ProductionPoint.PROD_STATUS.MISSING_INPUTS
			self.owningPlaceable:productionStatusChanged(production, ProductionPoint.PROD_STATUS.MISSING_INPUTS)
			self:setProductionStatus(production.id, production.status)
		end
	end

	if enoughInputResources and self.isOwned then
		for x = 1, #production.outputs do
			local output = production.outputs[x]
			if not output.sellDirectly then
				local outputMultiplier = 1
				if output.boost == true then
					outputMultiplier = booster
				elseif output.boost == "reverse" then
					outputMultiplier = 1 / booster
				end
				local freeCapacity = self.storage:getFreeCapacity(output.type)
				if freeCapacity < output.amount * factor * outputMultiplier then
					enoughOutputSpace = false
					if production.status ~= ProductionPoint.PROD_STATUS.NO_OUTPUT_SPACE then
						production.status = ProductionPoint.PROD_STATUS.NO_OUTPUT_SPACE
						self:setProductionStatus(production.id, production.status)
					end
					break
				end
			end
		end
	end

	if self.isOwned then
		self.productionCostsToClaim = self.productionCostsToClaim + production.costsPerActiveMinute * minuteFactorDt
	end

	if not self.isOwned or (enoughInputResources and enoughOutputSpace) then
		for x = 1, #production.inputs do
			local input = production.inputs[x]
			local isRequired = input.mix == 0
			local isSelectedGroupMember = input.mix ~= 0 and input.mix ~= Revamp.MIX_BOOST and input.mix ~= Revamp.MIX_MASTER and groupSelection[input.mix] == x
			local isBoostConsumed = input.mix == Revamp.MIX_BOOST and input.boostSatisfied
			local isMasterConsumed = masterConsume ~= nil and masterConsume[x] == true
			if isRequired or isSelectedGroupMember or isBoostConsumed or isMasterConsumed then
				-- Der Master-Input selbst verbraucht sich unskaliert, damit er sich nicht über
				-- masterFactor selbst hochschaukelt - alle anderen Inputs nutzen den skalierten Takt.
				local consumeFactor = isMasterConsumed and cyclesPerMinuteMinuteFactor or factor
				local amount = input.amount * consumeFactor
				if input.rngAffected then
					amount = amount * math.random()
				end
				if self.loadingStation == nil then
					local fillLevel = self:getFillLevel(input.type)
					self.storage:setFillLevel(fillLevel - amount, input.type)
				else
					self.loadingStation:removeFillLevel(input.type, amount, self:getOwnerFarmId())
				end
			end
		end

		if self.isOwned then
			for x = 1, #production.outputs do
				local output = production.outputs[x]
				local outputMultiplier = 1
				if output.boost == true then
					outputMultiplier = booster
				elseif output.boost == "reverse" then
					outputMultiplier = 1 / booster
				end
				local amount = output.amount * factor * outputMultiplier
				if output.rngAffected then
					amount = amount * math.random()
				end
				if output.sellDirectly then
					if self.isServer then
						self.soldFillTypesToPayOut[output.type] = self.soldFillTypesToPayOut[output.type] + amount
					end
				else
					local fillLevel = self.storage:getFillLevel(output.type)
					self.storage:setFillLevel(fillLevel + amount, output.type)
				end
			end
		end

		if production.status ~= ProductionPoint.PROD_STATUS.RUNNING then
			production.status = ProductionPoint.PROD_STATUS.RUNNING
			self.owningPlaceable:productionStatusChanged(production, production.status)
			ProductionPointProductionStatusEvent.sendEvent(self, production.index, production.status)
		end
	end
end

-- Vanilla bietet innerhalb von ProductionPoint:updateProduction() keinen Erweiterungspunkt, über
-- den sich beeinflussen ließe, welcher Input als "vorhanden" zählt bzw. abgebucht wird. Deshalb wird
-- die komplette Funktion überschrieben (kein Aufruf von superFunc): Inputs mit input.mix in 1..97
-- sind alternative Zutaten, von denen pro Zyklus nur eine (nach production.mixMode: ASC/DESC/
-- MOST/LEAST) benötigt und abgebucht wird, statt wie bei Vanilla alle gleichzeitig.
-- Die eigentliche Arbeit je Rezeptlinie steht in Revamp.updateSingleProduction weiter oben, hier bleiben nur die Dinge, die den ganzen Produktionspunkt betreffen.
--
-- production.sharedThroughputCapacity nimmt eine einzelne Rezeptlinie von der punktweiten
-- Kapazitätsteilung aus; input/output.rngAffected lässt Verbrauch/Ertrag zufällig schwanken statt
-- exaktem Fixbetrag. production.mixMode ist ein statischer XML-Wert, kein Laufzeit-Umschalter.
--
-- Booster/Master-Booster (input.mix == Revamp.MIX_BOOST/MIX_MASTER) sind rein optional: fehlender
-- Bestand blockiert die Produktion nie (anders als mix=0 oder eine leere Mix-Gruppe), er lässt nur
-- den jeweiligen Bonus ausfallen.
--
-- boostFactor ist ein reiner Multiplikator (> 0, Neutralwert 1 ist absichtlich unzulässig, siehe
-- Validierung in Revamp.loadProductionPoint oben) - damit hat "Faktor" dieselbe Bedeutung wie in
-- Vanilla (z.B. foodFactor/productionFactor in der Tierhaltung: 1 = neutral, multiplikativ).
--
-- Booster (mix=98): jeder gerade ausreichend bevorratete Booster-Input trägt seinen eigenen boostFactor bei, mehrere gleichzeitig aktive multiplizieren sich (booster = Produkt aller aktiven boostFactor-Werte).
-- Der Modus limitBoosters schaltet das auf einen einzigen Sieger um, ausgewählt nach boostMode.
--
-- Master-Booster (mix=99): wirkt als globaler Durchsatz-Multiplikator auf die gesamte Produktion
-- (alle anderen Inputs/Outputs), außer auf seinen eigenen Verbrauch (sonst rückgekoppelt). Bei
-- boostMode MOST/LEAST gewinnt genau ein Master-Input (dessen boostFactor direkt als Multiplikator
-- übernommen wird), sonst (ASC/DESC) multiplizieren sich wie beim Booster alle aktiven zusammen. Die
-- Sieger-Auswahl nutzt eine nil-Sentinel-Technik (erster passender Kandidat gewinnt immer, danach
-- nur noch bei echter Verbesserung) statt eines fest verdrahteten Startwerts - ein Vergleich gegen
-- einen festen Startwert würde z.B. einen boostFactor von 0,7 bei MOST nie gewinnen lassen.
--
-- output.boost == "reverse" nutzt den Kehrwert des Boosters (1/booster) - da booster durch die
-- Validierung immer > 0 ist, ist der Kehrwert immer wohldefiniert und braucht kein Clamping.
function Revamp.updateProduction(self, superFunc) ---@diagnostic disable-line: unused-local
	if self.lastUpdatedTime == nil then
		self.lastUpdatedTime = g_time
		return
	end

	local dt = math.clamp(g_time - self.lastUpdatedTime, 0, 30000)
	local timeAdjust = g_currentMission.environment.timeAdjustment
	local numActiveProductions = #self.activeProductions

	local minuteFactorDt = dt * self.minuteFactorTimescaled * timeAdjust

	-- Wetterabhängige Lager laufen unabhängig von den Rezeptlinien: ein Regenfass sammelt auch dann, wenn am Punkt gerade gar keine Produktion eingeschaltet ist.
	if self.hasWeatherStorage and self.isOwned then
		Revamp.processWeatherStorage(self, minuteFactorDt / 60)
	end

	if numActiveProductions > 0 then
		-- Die Wetter- und Zeit-Modi werden für alle Linien vorab ausgewertet, weil eine gerade angehaltene Linie auch keinen Anteil an der geteilten Durchsatzkapazität belegen soll.
		-- Sonst würden die tatsächlich laufenden Linien nachts von einer stehenden Solar-Linie mit ausgebremst.
		local numSharedThroughputCapacity = 0
		for i = 1, numActiveProductions do
			local production = self.activeProductions[i]
			production.modeStatus = Revamp.processProductionModes(production)
			if production.modeStatus == nil and self.sharedThroughputCapacity and production.sharedThroughputCapacity then
				numSharedThroughputCapacity = numSharedThroughputCapacity + 1
			end
		end

		for i = 1, numActiveProductions do
			Revamp.updateSingleProduction(self, self.activeProductions[i], minuteFactorDt, numSharedThroughputCapacity)
		end
	end

	-- Ein wegen seiner Öffnungszeiten geschlossener Betrieb stellt auch keine Paletten mehr raus.
	local isWithinOpeningHours = self.openingHoursTable == nil or self.openingHoursTable[g_currentMission.environment.currentHour] == true

	if self.isServer and self.isOwned and isWithinOpeningHours and g_time > self.palletSpawnCooldown and not self.waitingForPalletToSpawn then
		local nextFillTypeId = nil
		while true do
			local fillTypeId = self.lastPalletFillTypeId
			if fillTypeId ~= nil and self.outputFillTypeIdsDirectSell[fillTypeId] == nil and self.outputFillTypeIdsAutoDeliver[fillTypeId] == nil then
				local fillLevel = self.storage:getFillLevel(fillTypeId)
				if fillLevel > 0 then
					local pallet = self.outputFillTypeIdsToPallets[fillTypeId]
					if pallet and pallet.capacity <= fillLevel then
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

	self.lastUpdatedTime = g_time
end

ProductionPoint.updateProduction = Utils.overwrittenFunction(ProductionPoint.updateProduction, Revamp.updateProduction)
