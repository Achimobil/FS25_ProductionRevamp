-- Ticket #7: Rezept-Datenmodell & Grundstruktur.
--
-- Erweitert die Vanilla-Produktions-Ladefunktion um die Revamp-eigenen Rezept-Felder
-- (Mix-Gruppen, Booster, erzwungener Primär-Output, Sichtbarkeit). Die Vanilla-Funktion
-- wird dafür aufgerufen statt komplett neu geschrieben, damit alles, was Vanilla schon
-- selbst leistet (Storage/Verkaufsstelle/Palettenspawner/Validierung), unverändert bleibt.
--
-- Ausdrücklich nicht Teil dieses Tickets: FillTypeCategory-Zweig (#11), FeedMixer- und
-- Tier-Trigger-Code (#12/#45), Storage-Kauf/Verkauf/Wetter-Felder (Storage Extension/
-- Buy-Sell/Distribution). Die hier geladenen Boost-/Wetter-Felder werden zur Laufzeit
-- erst von #9/#10 ausgewertet. Mix-Gruppen selbst sind seit #8 implementiert (siehe
-- Revamp.updateProduction weiter unten).

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
	local pointMixMode = xmlFile:getValue(key .. ".productions#mixMode", "ASC"):upper()

	xmlFile:iterate(key .. ".productions.production", function(_, productionKey)
		local id = xmlFile:getValue(productionKey .. "#id")
		local production = self.productionsIdToObj[id]
		if production == nil then
			return -- von Vanilla schon abgelehnt (fehlende/doppelte id, kein Input, ungültiger FillType)
		end

		production.sharedThroughputCapacity = xmlFile:getValue(productionKey .. "#sharedThroughputCapacity", self.sharedThroughputCapacity)
		production.mixMode = xmlFile:getValue(productionKey .. "#mixMode", pointMixMode):upper()
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

		-- Inputs/Outputs über fillTypeCategory statt fillType (Vanilla-Feature, noch nicht Teil
		-- unseres Rezept-Systems, siehe #11) werden von den obigen Iterationen nie erreicht, weil
		-- sie kein #fillType-Attribut haben. Ohne diese Absicherung bliebe input.mix (bzw.
		-- output.boost) bei solchen Einträgen nil statt 0/true, was in Revamp.updateProduction und
		-- der Rezept-Anzeige zu "table index is nil" führt, sobald nil mit 0/98/99 verglichen wird.
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

-- Ticket #8: Mix-Gruppen & Wertigkeiten.
--
-- Vanilla bietet innerhalb von ProductionPoint:updateProduction() keinen Erweiterungspunkt,
-- über den sich beeinflussen ließe, welcher Input als "vorhanden" zählt bzw. abgebucht wird.
-- Deshalb wird die komplette Funktion überschrieben (kein Aufruf von superFunc), analog zum
-- Original in RevampWork/Production_Revamp: Inputs mit input.mix in 1..97 sind alternative
-- Zutaten, von denen pro Zyklus nur eine (nach production.mixMode: ASC/DESC/MOST/LEAST)
-- benötigt und abgebucht wird, statt wie bei Vanilla alle gleichzeitig.
--
-- Bei dieser Gelegenheit werden zwei weitere, seit #7 geladene aber bislang wirkungslose
-- Felder mit ausgewertet: production.sharedThroughputCapacity (nimmt eine einzelne
-- Rezeptlinie von der Punkt-weiten Kapazitätsteilung aus) und input/output.rngAffected
-- (Verbrauch/Ertrag schwankt zufällig statt exaktem Fixbetrag).
--
-- Ausdrücklich nicht Teil dieses Tickets: input.mix == Revamp.MIX_BOOST/MIX_MASTER (#9),
-- Wetter-/Zeitmodi (#10), FillTypeCategory-Rezepte (#11), FeedMixer (#12). production.mixMode
-- ist hier ein statischer XML-Wert; das spielerseitige Umschalten zur Laufzeit inkl.
-- Speichern/MP-Sync gehört zu #14/#38/#39.
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

			local enoughInputResources = true
			local enoughOutputSpace = true
			-- Mix-Gruppen-ID -> Index des production.inputs-Eintrags, der laut mixMode "gewinnt"
			local groupSelection = {}
			local groupFillLevel = {}
			local seenGroups = {}

			for x = 1, #production.inputs do
				local input = production.inputs[x]
				if input.mix == 0 then
					local fillLevel = self:getFillLevel(input.type)
					if self.isOwned and fillLevel < input.amount * cyclesPerMinuteMinuteFactor then
						enoughInputResources = false
					end
				elseif input.mix ~= Revamp.MIX_BOOST and input.mix ~= Revamp.MIX_MASTER then
					seenGroups[input.mix] = true
					local fillLevel = self:getFillLevel(input.type)
					local needAmount = input.amount * cyclesPerMinuteMinuteFactor
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
						local freeCapacity = self.storage:getFreeCapacity(output.type)
						if freeCapacity < output.amount * cyclesPerMinuteMinuteFactor then
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
					if isRequired or isSelectedGroupMember then
						local amount = input.amount * cyclesPerMinuteMinuteFactor
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
						local amount = output.amount * cyclesPerMinuteMinuteFactor
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
