-- Erweitert die Vanilla-Produktions-Ladefunktion um die Revamp-eigenen Rezept-Felder
-- (Mix-Gruppen, Booster, erzwungener Primär-Output, Sichtbarkeit). Die Vanilla-Funktion wird dafür
-- aufgerufen statt komplett neu geschrieben, damit alles, was Vanilla schon selbst leistet
-- (Storage/Verkaufsstelle/Palettenspawner/Validierung), unverändert bleibt.
--
-- FillTypeCategory-basierte Inputs/Outputs, FeedMixer-/Tier-Trigger-Anbindung sowie Storage-Kauf/
-- Verkauf/Wetter-Felder werden hier nicht geladen. Wetter-Felder werden aktuell an keiner Stelle
-- ausgewertet; Mix-Gruppen und Booster/Master-Booster wertet Revamp.updateProduction weiter unten aus.

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
	schema:register(XMLValueType.STRING, basePath .. ".productions.production(?).inputs.input(?)#mix", "Mix-Gruppe des Inputs (Zahl, 'boost' oder 'master')", "0")
	schema:register(XMLValueType.FLOAT, basePath .. ".productions.production(?).inputs.input(?)#boostFactor", "Multiplikator für Booster/Master-Booster (> 0, 1 ist unzulässig weil wirkungslos) - Pflichtfeld bei mix='boost'/'master'")
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
	local pointMixMode = xmlFile:getValue(key .. ".productions#mixMode", "ASC"):upper()
	local pointBoostMode = xmlFile:getValue(key .. ".productions#boostMode", "ASC"):upper()

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

		-- Inputs/Outputs über fillTypeCategory statt fillType (ein Vanilla-Feature) werden von den
		-- obigen Iterationen nie erreicht, weil sie kein #fillType-Attribut haben. Ohne diese
		-- Absicherung bliebe input.mix (bzw. output.boost) bei solchen Einträgen nil statt 0/true, was
		-- in Revamp.updateProduction und der Rezept-Anzeige zu "table index is nil" führt, sobald nil
		-- mit 0/98/99 verglichen wird.
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
	end)

	return true
end

ProductionPoint.load = Utils.overwrittenFunction(ProductionPoint.load, Revamp.loadProductionPoint)

-- Vanilla bietet innerhalb von ProductionPoint:updateProduction() keinen Erweiterungspunkt, über
-- den sich beeinflussen ließe, welcher Input als "vorhanden" zählt bzw. abgebucht wird. Deshalb wird
-- die komplette Funktion überschrieben (kein Aufruf von superFunc): Inputs mit input.mix in 1..97
-- sind alternative Zutaten, von denen pro Zyklus nur eine (nach production.mixMode: ASC/DESC/
-- MOST/LEAST) benötigt und abgebucht wird, statt wie bei Vanilla alle gleichzeitig.
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
-- Booster (mix=98): jeder gerade ausreichend bevorratete Booster-Input trägt seinen eigenen
-- boostFactor bei, mehrere gleichzeitig aktive multiplizieren sich (booster = Produkt aller aktiven
-- boostFactor-Werte). Ein Einzel-Sieger-Modus (nur der laut boostMode "beste" Booster zählt) ist
-- nicht umgesetzt - er würde einen generischen production.modes-Mechanismus voraussetzen, den es
-- hier noch nicht gibt.
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

	if numActiveProductions > 0 then
		local minuteFactorDt = dt * self.minuteFactorTimescaled * timeAdjust

		local numSharedThroughputCapacity = 0
		if self.sharedThroughputCapacity then
			for i = 1, numActiveProductions do
				if self.activeProductions[i].sharedThroughputCapacity then
					numSharedThroughputCapacity = numSharedThroughputCapacity + 1
				end
			end
		end

		for i = 1, numActiveProductions do
			local production = self.activeProductions[i]
			local cyclesPerMinuteMinuteFactor = production.cyclesPerMinute * minuteFactorDt
			if self.sharedThroughputCapacity and production.sharedThroughputCapacity then
				cyclesPerMinuteMinuteFactor = cyclesPerMinuteMinuteFactor / numSharedThroughputCapacity
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
						booster = booster * input.boostFactor
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
						Revamp.DebugText("updateProduction(): %s Mix-Gruppe %d waehlt jetzt %s (mixMode=%s)", production.id, mix, g_fillTypeManager:getFillTypeNameByIndex(winnerType), production.mixMode)
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
	end

	if self.isServer and self.isOwned and g_time > self.palletSpawnCooldown and not self.waitingForPalletToSpawn then
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
