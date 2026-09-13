--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- Wie dringend eine Produktionsstätte eine bestimmte Zutat braucht, ausgedrückt als Verbrauch je Spielstunde und als Bestand, der davon noch da ist.
-- Aus beidem ergibt sich die Restlaufzeit: wie lange der Betrieb mit dem, was im Lager liegt, noch weiterkommt.
--
-- Gerechnet wird der Soll-Verbrauch und nicht der gemessene: eine Linie, die gerade mangels Zutat stillsteht, verbraucht nichts und hätte damit eine unendliche Restlaufzeit -
-- ausgerechnet das Ziel, das am dringendsten Nachschub braucht, fiele so aus der Rechnung.
--
-- Der Takt einer Linie wird genauso zusammengesetzt wie im Produktionstakt selbst: Länge der Jahreszeit, geteilte Durchsatzkapazität, aktueller Wetteranteil und Master-Booster.
-- Zeitvorgaben gehen dagegen als Anteil des Tages ein statt als An/Aus - eine Bäckerei, die acht von 24 Stunden arbeitet, verbraucht im Tagesmittel ein Drittel ihrer Stundenmenge.
-- Beliefert wird sie nämlich auch während ihrer Mittagspause, und ohne diesen Anteil stünde sie in der Rechnung als bedarfsfrei da.

---Zählt die Rezeptlinien, die sich die Durchsatzkapazität einer Produktionsstätte gerade teilen.
---@param productionPoint table ProductionPoint-Instanz
---@return number count Anzahl der beteiligten Linien, 0 wenn die Stätte ihre Kapazität gar nicht teilt
function Revamp.countSharedThroughputLines(productionPoint)
	if not productionPoint.sharedThroughputCapacity then
		return 0
	end

	local count = 0
	for _, production in ipairs(productionPoint.activeProductions) do
		-- Eine angehaltene Linie belegt keinen Anteil an der geteilten Kapazität, genauso rechnet Revamp.updateProduction.
		if production.modeStatus == nil and production.sharedThroughputCapacity then
			count = count + 1
		end
	end

	return count
end

---Liefert den Anteil eines Tages, an dem eine Rezeptlinie im laufenden Monat arbeiten darf.
---Ohne Zeitvorgaben ist das der ganze Tag, mit Öffnungszeiten der Anteil der offenen Stunden, und in einem ausgeschlossenen Monat oder einer ausgeschlossenen Jahreszeit gar nichts.
---@param production table Rezeptlinie
---@return number share Anteil zwischen 0 und 1
function Revamp.getRunningShareOfDay(production)
	-- Sind die Modi abgeschaltet, läuft jede Linie rund um die Uhr - genauso hält es Revamp.processProductionModes.
	if production.modes == nil or not Revamp.settings.weatherModesActive then
		return 1
	end

	local environment = g_currentMission.environment
	local share = 1

	for _, mode in ipairs(production.modes) do
		if mode == "HOURLY" then
			local openHours = 0
			for hour = 0, 23 do
				if production.hoursTable[hour] then
					openHours = openHours + 1
				end
			end
			share = share * openHours / 24
		elseif mode == "SEASONAL" and not production.seasonsList[environment.currentSeason] then
			return 0
		elseif mode == "MONTHLY" and not production.monthsList[environment.currentPeriod] then
			return 0
		end
	end

	return share
end

---Liefert die Menge, mit der eine Zutat aus einer Gruppe alternativer Zutaten in die Rechnung eingeht, und merkt sich alle Sorten der Gruppe.
---Maßgeblich ist die Menge der Sorte, die der Auswahlmodus gerade gewinnen lässt: an ihr zehrt die Linie im Moment.
---Hat die Gruppe noch nie einen Gewinner gehabt, bleibt es bei der Menge der gefragten Sorte selbst.
---@param production table Rezeptlinie
---@param groupInput table Eintrag aus production.inputs, dessen Gruppe betrachtet wird
---@param levelFillTypes table Wird um alle Sorten der Gruppe ergänzt
---@return number amount Menge je Takt
function Revamp.getMixGroupAmount(production, groupInput, levelFillTypes)
	local winnerType = production.mixGroupWinnerType ~= nil and production.mixGroupWinnerType[groupInput.mix] or nil
	local amount = groupInput.amount

	for _, input in ipairs(production.inputs) do
		if input.mix == groupInput.mix then
			levelFillTypes[input.type] = true
			if input.type == winnerType then
				amount = input.amount
			end
		end
	end

	return amount
end

---Liefert, wie viel eine einzelne Rezeptlinie von einem Fülltyp je Spielstunde verbraucht.
---@param production table Rezeptlinie
---@param fillTypeIndex number FillType-Index der Zutat
---@param cyclesPerHour number Takt je Spielstunde ohne den Master-Booster
---@param cyclesPerHourBoosted number Takt je Spielstunde samt Master-Booster
---@param levelFillTypes table Wird um die Sorten einer Zutaten-Gruppe ergänzt
---@return number ratePerHour Verbrauch in Litern je Spielstunde
function Revamp.getLineFillTypeRate(production, fillTypeIndex, cyclesPerHour, cyclesPerHourBoosted, levelFillTypes)
	local ratePerHour = 0

	for _, input in ipairs(production.inputs) do
		if input.type == fillTypeIndex then
			local amount = input.amount
			-- Der Master-Booster verbraucht sich mit dem unskalierten Takt, damit er sich nicht über seinen eigenen Faktor hochschaukelt - alles andere zehrt am angehobenen Takt.
			local cycles = cyclesPerHourBoosted

			if input.mix == Revamp.MIX_MASTER then
				cycles = cyclesPerHour
			elseif input.mix ~= 0 and input.mix ~= Revamp.MIX_BOOST then
				amount = Revamp.getMixGroupAmount(production, input, levelFillTypes)
			end

			-- Ein Zufallsanteil wirkt je Takt und mittelt sich über eine Spielstunde auf die Hälfte ein.
			if input.rngAffected then
				amount = amount * 0.5
			end

			ratePerHour = ratePerHour + amount * cycles
		end
	end

	return ratePerHour
end

---Liefert Verbrauch und Bestand eines Fülltyps an einer Produktionsstätte.
---Ein Booster zählt auch dann mit, wenn er gerade mangels Bestand ausfällt: er hält die Linie zwar nicht an, soll aber geliefert bekommen - mit Rate 0 käme er nie wieder an Nachschub.
---Gehört die Zutat zu einer Gruppe alternativer Sorten, zählt der Bestand aller Sorten dieser Gruppe mit: solange irgendeine davon im Lager liegt, läuft die Linie weiter.
---@param productionPoint table ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index der Zutat
---@return number ratePerHour Verbrauch in Litern je Spielstunde, 0 wenn die Zutat gerade nirgends gebraucht wird
---@return number level Bestand in Litern, bei einer Zutaten-Gruppe über alle ihre Sorten
function Revamp.getFillTypeDemand(productionPoint, fillTypeIndex)
	local numSharedThroughputLines = Revamp.countSharedThroughputLines(productionPoint)
	local levelFillTypes = {[fillTypeIndex] = true}
	local ratePerHour = 0

	-- Die Länge einer Jahreszeit streckt den Produktionstakt: bei zwölf Tagen je Monat schafft eine Linie in einer Spielstunde nur ein Zwölftel ihres Nennwerts.
	-- Ohne diesen Faktor käme eine Rate heraus, die es so nie gibt, und mit ihr eine Restlaufzeit, die um denselben Faktor zu kurz ist.
	local timeAdjustment = g_currentMission.environment.timeAdjustment

	for _, production in ipairs(productionPoint.activeProductions) do
		local share = Revamp.getRunningShareOfDay(production)
		if share > 0 then
			local cyclesPerHour = production.cyclesPerMinute * 60 * timeAdjustment * share
			if numSharedThroughputLines > 0 and production.sharedThroughputCapacity then
				cyclesPerHour = cyclesPerHour / numSharedThroughputLines
			end
			if production.weatherFactorCurrent ~= nil then
				cyclesPerHour = cyclesPerHour * production.weatherFactorCurrent
			end

			ratePerHour = ratePerHour + Revamp.getLineFillTypeRate(production, fillTypeIndex, cyclesPerHour, cyclesPerHour * (production.masterFactor or 1), levelFillTypes)
		end
	end

	local level = 0
	for levelFillType in pairs(levelFillTypes) do
		level = level + productionPoint:getFillLevel(levelFillType)
	end

	return ratePerHour, level
end

---Liefert die Restlaufzeit eines Fülltyps an einer Produktionsstätte.
---@param productionPoint table ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index der Zutat
---@return number|nil hoursLeft Spielstunden, die der Bestand noch reicht, nil wenn die Zutat gar nicht verbraucht wird
function Revamp.getFillTypeHoursLeft(productionPoint, fillTypeIndex)
	local ratePerHour, level = Revamp.getFillTypeDemand(productionPoint, fillTypeIndex)
	if ratePerHour <= 0 then
		return nil
	end

	return level / ratePerHour
end

---Sortiert zwei Ziele danach, welches von beiden zuerst ohne Vorrat dasteht.
---@param a table Ziel mit hoursLeft
---@param b table Ziel mit hoursLeft
---@return boolean isLess true, wenn a vor b steht
function Revamp.compareDemandTargets(a, b)
	return a.hoursLeft < b.hoursLeft
end

---Teilt eine Menge so auf mehrere Ziele auf, dass sich ihre Restlaufzeiten angleichen.
---Die Ziele mit der kürzesten Restlaufzeit werden zuerst aufgefüllt, bis sie das nächste Ziel eingeholt haben, dann geht es mit beiden gemeinsam weiter.
---Reicht die Menge, um alle auf denselben Stand zu bringen, hebt der Rest diesen gemeinsamen Stand einfach weiter an.
---Er verteilt sich damit von selbst im Verhältnis der Verbräuche und braucht keinen zweiten Rechenschritt.
---Ziele ohne Verbrauch bleiben leer aus: sie können nicht leerlaufen und haben deshalb auch keine Dringlichkeit.
---@param targets table Ziele mit je rate und fillLevel
---@param amount number Zu verteilende Menge in Litern
---@return table shares Menge je Ziel, Schlüssel ist dessen Position in targets
function Revamp.getDemandShares(targets, amount)
	local shares = {}
	local ordered = {}

	for index, target in ipairs(targets) do
		shares[index] = 0
		if target.rate > 0 then
			table.insert(ordered, {index = index, rate = target.rate, level = target.fillLevel, hoursLeft = target.fillLevel / target.rate})
		end
	end

	if #ordered == 0 then
		return shares
	end

	table.sort(ordered, Revamp.compareDemandTargets)

	-- Gemeinsame Restlaufzeit, auf die sich die bedürftigsten Ziele anheben lassen, und wie viele Ziele daran beteiligt sind.
	local commonHours = 0
	local numInvolved = 0
	local sumRate = 0
	local sumLevel = 0

	for position, entry in ipairs(ordered) do
		sumRate = sumRate + entry.rate
		sumLevel = sumLevel + entry.level
		numInvolved = position

		-- Was es kostet, alle bisherigen Ziele auf den Stand des nächsten zu bringen. Beim letzten Ziel gibt es kein nächstes mehr, dort bleibt die ganze Restmenge.
		local nextEntry = ordered[position + 1]
		if nextEntry == nil or amount < sumRate * nextEntry.hoursLeft - sumLevel then
			commonHours = (amount + sumLevel) / sumRate
			break
		end
	end

	for position = 1, numInvolved do
		local entry = ordered[position]
		shares[entry.index] = math.max(entry.rate * commonHours - entry.level, 0)
	end

	return shares
end
