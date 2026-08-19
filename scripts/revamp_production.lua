-- Ticket #7: Rezept-Datenmodell & Grundstruktur.
--
-- Erweitert die Vanilla-Produktions-Ladefunktion um die Revamp-eigenen Rezept-Felder
-- (Mix-Gruppen, Booster, erzwungener Primär-Output, Sichtbarkeit). Die Vanilla-Funktion
-- wird dafür aufgerufen statt komplett neu geschrieben, damit alles, was Vanilla schon
-- selbst leistet (Storage/Verkaufsstelle/Palettenspawner/Validierung), unverändert bleibt.
--
-- Ausdrücklich nicht Teil dieses Tickets: FillTypeCategory-Zweig (#11), FeedMixer- und
-- Tier-Trigger-Code (#12/#45), Storage-Kauf/Verkauf/Wetter-Felder (Storage Extension/
-- Buy-Sell/Distribution). Die hier geladenen Mix-/Boost-/Wetter-Felder werden zur
-- Laufzeit erst von #8/#9/#10 ausgewertet.

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
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?).inputs.input(?)#mix", "Mix-Gruppe des Inputs (Zahl, 'boost' oder 'master')", "0")
	schema:register(XMLValueType.FLOAT, basePath .. ".productions.production(?).inputs.input(?)#boostFactor", "Wertigkeits-Faktor für Booster/Master-Booster", 0)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).inputs.input(?)#rngAffected", "Input ist von einem Zufallsfaktor betroffen", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).inputs.input(?)#hideFromMenu", "Input ist standardmäßig im Menü versteckt", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).outputs.output(?)#primaryProductFillType", "Erzwingt diesen Output als primären FillType", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).outputs.output(?)#boost", "Output ist von einem Booster betroffen", true)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).outputs.output(?)#rngAffected", "Output ist von einem Zufallsfaktor betroffen", false)
	schema:register(XMLValueType.BOOL, basePath .. ".productions.production(?).outputs.output(?)#hideFromMenu", "Output ist standardmäßig im Menü versteckt", false)
end

ProductionPoint.registerXMLPaths = Utils.prependedFunction(ProductionPoint.registerXMLPaths, Revamp.registerProductionXMLPaths)

function Revamp.loadProductionPoint(self, superFunc, components, xmlFile, key, customEnv, i3dMappings)
	if not superFunc(self, components, xmlFile, key, customEnv, i3dMappings) then
		return false
	end

	local pointHideFromMenu = xmlFile:getBool(key .. ".productions#hideFromMenu", false)
	local pointAutoStart = xmlFile:getBool(key .. ".productions#autoStart", false)

	xmlFile:iterate(key .. ".productions.production", function(_, productionKey)
		local id = xmlFile:getValue(productionKey .. "#id")
		local production = self.productionsIdToObj[id]
		if production == nil then
			return -- von Vanilla schon abgelehnt (fehlende/doppelte id, kein Input, ungültiger FillType)
		end

		production.sharedThroughputCapacity = xmlFile:getValue(productionKey .. "#sharedThroughputCapacity", self.sharedThroughputCapacity)
		production.hideFromMenu = xmlFile:getBool(productionKey .. "#hideFromMenu", pointHideFromMenu)
		production.autoStart = xmlFile:getBool(productionKey .. "#autoStart", pointAutoStart)
		production.master = false

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
			input.boostFactor = xmlFile:getValue(inputKey .. "#boostFactor", 0)
			input.rngAffected = xmlFile:getBool(inputKey .. "#rngAffected", false)
			input.hideFromMenu = xmlFile:getBool(inputKey .. "#hideFromMenu", false)
			input.color = 0
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
	end)

	return true
end

ProductionPoint.load = Utils.overwrittenFunction(ProductionPoint.load, Revamp.loadProductionPoint)
