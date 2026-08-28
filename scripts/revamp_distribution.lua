-- Verteilen der Erzeugnisse an die eigenen Produktionsstätten (Ausgangsmodus "Verteilen").
--
-- Vanilla verteilt stur an jede Produktion, die den Fülltyp als Zutat kennt, und teilt dabei nach freiem Lagerplatz auf:
-- die größte Halle bekommt am meisten, unabhängig davon ob sie das gerade braucht oder überhaupt läuft.
-- Revamp ersetzt das durch vier Stufen je Ziel, die der Spieler pro Ausgangs-Fülltyp einstellt.
--
-- Beliefert wird Stufe für Stufe: erst alle Primär-Ziele, was danach noch übrig ist geht an die Sekundär-Ziele und
-- zuletzt an alle übrigen. "Nie" bleibt immer leer aus. Innerhalb einer Stufe wird zu gleichen Teilen aufgeteilt,
-- nicht nach freiem Lagerplatz - eine Aufteilung nach Platz sieht für den Spieler willkürlich aus, weil sie sich mit
-- jedem Füllstand ändert.
--
-- Gespeichert wird nur, was vom Normalfall abweicht: ein Ziel ohne Eintrag ist automatisch "Rest".
--
-- Ein Ziel wird über die uniqueId seines Placeables angesprochen. Diese Id ist ausdrücklich nur auf dem eigenen Rechner gültig:
-- Placeable:writeStream überträgt sie nicht, ein Client vergibt beim Empfangen über Utils.getUniqueId eine eigene aus Zeitstempel und Speicheradresse.
-- Server und Client führen dasselbe Gebäude also unter verschiedenen Ids. Für das Savegame ist die Id trotzdem der richtige Schlüssel, weil sie dort mitgespeichert und beim Laden wieder gesetzt wird.
-- Wer später Netzwerk-Events dafür baut, muss deshalb das Ziel als Objekt übertragen (NetworkUtil.writeNodeObject) und auf der Gegenseite dessen dortige uniqueId als Schlüssel nehmen - eine Id als Zeichenkette zu verschicken zeigt beim Empfänger ins Leere.

-- Alle Stufen, in der Reihenfolge, in der die Bedienoberfläche sie durchschaltet.
Revamp.DISTRIBUTION_LEVELS = {"PRIMARY", "SECONDARY", "REST", "NEVER"}

-- Reihenfolge der Belieferung. NEVER steht bewusst nicht darin, diese Ziele werden gar nicht erst eingesammelt.
Revamp.DISTRIBUTION_ORDER = {"PRIMARY", "SECONDARY", "REST"}

-- Stufe eines Ziels, für das der Spieler nichts eingestellt hat.
Revamp.DISTRIBUTION_LEVEL_DEFAULT = "REST"

-- Kleinste Menge, die eine Lieferung wert ist. Darunter stünde in der Statistik eine Kostenbuchung über Bruchteile
-- eines Cents, und die Restmengen-Schleife unten liefe für ein paar Tropfen mehrfach durch alle Ziele.
Revamp.DISTRIBUTION_MIN_AMOUNT = 1

---Prüft, ob ein Wert eine gültige Verteilstufe ist.
---@param level string Zu prüfender Wert
---@return boolean isLevel true, wenn der Wert eine der Verteilstufen ist
function Revamp.isDistributionLevel(level)
	for _, name in ipairs(Revamp.DISTRIBUTION_LEVELS) do
		if name == level then
			return true
		end
	end
	return false
end

---Liefert die nächste Verteilstufe in der Reihenfolge Primär, Sekundär, Rest, Nie und danach wieder von vorn.
---@param level string Aktuelle Verteilstufe
---@return string nextLevel Nächste Verteilstufe
function Revamp.getNextDistributionLevel(level)
	for index, name in ipairs(Revamp.DISTRIBUTION_LEVELS) do
		if name == level then
			return Revamp.DISTRIBUTION_LEVELS[index % #Revamp.DISTRIBUTION_LEVELS + 1]
		end
	end
	return Revamp.DISTRIBUTION_LEVELS[1]
end

---Liefert den lokalisierten Namen einer Verteilstufe.
---@param level string Verteilstufe
---@return string text Lokalisierter Name
function Revamp.getDistributionLevelText(level)
	return g_i18n:getText("revamp_distributionLevel_" .. level)
end

---Liefert die eingestellte Verteilstufe und Obergrenze eines Ziels.
---@param productionPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@param uniqueId string uniqueId des Ziel-Placeables
---@return string level Verteilstufe, "REST" wenn nichts eingestellt ist
---@return number|nil limit Obergrenze in Litern, nil wenn unbegrenzt
function Revamp.getDistributionTarget(productionPoint, fillTypeIndex, uniqueId)
	local targets = productionPoint.distributionTargets
	if targets == nil or uniqueId == nil or targets[fillTypeIndex] == nil then
		return Revamp.DISTRIBUTION_LEVEL_DEFAULT, nil
	end

	local entry = targets[fillTypeIndex][uniqueId]
	if entry == nil then
		return Revamp.DISTRIBUTION_LEVEL_DEFAULT, nil
	end

	return entry.level, entry.limit
end

---Setzt Verteilstufe und Obergrenze eines Ziels.
---Ein Ziel auf "Rest" ohne Obergrenze verhält sich wie ein Ziel ohne jede Einstellung und wird deshalb ganz entfernt, statt den Normalfall in jedem Spielstand mitzuschleppen.
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@param uniqueId string uniqueId des Ziel-Placeables
---@param level string Verteilstufe aus Revamp.DISTRIBUTION_LEVELS
---@param limit? number Obergrenze in Litern, nil für unbegrenzt
---@param noEventSend? boolean true, wenn die Änderung selbst schon aus einem Event stammt und nicht erneut verschickt werden darf
function ProductionPoint:setDistributionTarget(fillTypeIndex, uniqueId, level, limit, noEventSend) ---@diagnostic disable-line: unused-local
	-- Beides kann aus einem von Hand bearbeiteten Spielstand als nil hereinkommen, und ein nil-Schlüssel bricht das Setzen unten mit "table index is nil" ab.
	if fillTypeIndex == nil or uniqueId == nil then
		return
	end

	-- Unbekannte Stufen werden auf den Normalfall zurückgesetzt statt übernommen: sie können aus einem von Hand bearbeiteten Spielstand kommen und würden sich später als stillschweigend anderes Verteilverhalten zeigen.
	if not Revamp.isDistributionLevel(level) then
		level = Revamp.DISTRIBUTION_LEVEL_DEFAULT
	end
	-- 0 ist eine gültige Obergrenze und bedeutet "nichts liefern", nur negative Werte sind Unsinn.
	-- Abgerundet wird, weil die Obergrenze als ganze Zahl im Spielstand landet und ein Bruchteil eines Liters ohnehin nichts ändert.
	if limit ~= nil then
		limit = math.floor(math.max(limit, 0))
	end

	if self.distributionTargets == nil then
		self.distributionTargets = {}
	end
	if self.distributionTargets[fillTypeIndex] == nil then
		self.distributionTargets[fillTypeIndex] = {}
	end

	if level == Revamp.DISTRIBUTION_LEVEL_DEFAULT and limit == nil then
		self.distributionTargets[fillTypeIndex][uniqueId] = nil
	else
		self.distributionTargets[fillTypeIndex][uniqueId] = {level = level, limit = limit}
	end

	Revamp.DebugText("setDistributionTarget(): %s -> %s level=%s limit=%s", g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex), uniqueId, level, tostring(limit))
end

---Liefert alle Produktionsstätten der Farm, die einen Fülltyp als Zutat verarbeiten und deshalb als Verteilziel in Frage kommen.
---Anders als beim Verteilen selbst zählt hier nicht, ob gerade eine passende Rezeptlinie läuft: eingestellt wird ein Ziel auch dann, wenn es momentan stillsteht.
---@param productionPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@return table candidates Mögliche Ziel-ProductionPoints
function Revamp.getDistributionCandidates(productionPoint, fillTypeIndex)
	local candidates = {}

	local farmTable = g_currentMission.productionChainManager.farmIds[productionPoint:getOwnerFarmId()]
	if farmTable == nil or farmTable.inputTypeToProductionPoints == nil then
		return candidates
	end

	for _, prodPoint in ipairs(farmTable.inputTypeToProductionPoints[fillTypeIndex] or {}) do
		if prodPoint ~= productionPoint and prodPoint.owningPlaceable ~= nil then
			table.insert(candidates, prodPoint)
		end
	end

	return candidates
end

---Liefert die Menge eines Erzeugnisses, die eine Produktionsstätte gerade pro Stunde ausstößt.
---Grundlage der Kostenvorschau: gezeigt werden die laufenden Kosten der aktuellen Produktion, nicht die einmaligen Kosten für das Leerräumen eines vollen Lagers.
---Booster, die einzelne Ausgänge anheben, bleiben außen vor - sie hängen am Bestand einzelner Zutaten und ließen die Vorschau bei jedem Blick anders aussehen.
---@param productionPoint table ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@return number amountPerHour Ausstoß in Litern je Stunde
function Revamp.getHourlyOutputAmount(productionPoint, fillTypeIndex)
	-- Teilen sich mehrere Linien die Durchsatzkapazität, schafft jede davon nur ihren Bruchteil - genauso rechnet Revamp.updateProduction den tatsächlichen Ausstoß aus.
	local numSharedThroughputCapacity = 0
	for _, production in ipairs(productionPoint.activeProductions) do
		if production.modeStatus == nil and productionPoint.sharedThroughputCapacity and production.sharedThroughputCapacity then
			numSharedThroughputCapacity = numSharedThroughputCapacity + 1
		end
	end

	local amountPerHour = 0
	for _, production in ipairs(productionPoint.activeProductions) do
		if production.modeStatus == nil then
			local output = Revamp.findProductionEntryByType(production.outputs, fillTypeIndex)
			if output ~= nil then
				local cyclesPerHour = production.cyclesPerMinute * 60
				if numSharedThroughputCapacity > 0 and production.sharedThroughputCapacity then
					cyclesPerHour = cyclesPerHour / numSharedThroughputCapacity
				end
				amountPerHour = amountPerHour + cyclesPerHour * output.amount * (production.weatherFactorCurrent or 1) * (production.masterFactor or 1)
			end
		end
	end

	return amountPerHour
end

---Liefert die Lieferkosten, die ein einzelnes Ziel pro Stunde verursacht.
---Die Stundenmenge wird dabei gleichmäßig auf alle Ziele seiner Stufe aufgeteilt, weil das Verteilen selbst genauso rechnet.
---@param distributingPoint table Verteilende ProductionPoint-Instanz
---@param receivingPoint table Empfangende ProductionPoint-Instanz
---@param amountPerHour number Stündlicher Ausstoß des Erzeugnisses
---@param targetCount number Anzahl Ziele derselben Verteilstufe
---@return number costs Lieferkosten je Stunde
function Revamp.getDistributionCostsPerHour(distributingPoint, receivingPoint, amountPerHour, targetCount)
	if amountPerHour <= 0 or targetCount <= 0 then
		return 0
	end

	local distance = calcDistanceFrom(distributingPoint.owningPlaceable.rootNode, receivingPoint.owningPlaceable.rootNode)
	return amountPerHour / targetCount * distance * ProductionPoint.DIRECT_DELIVERY_PRICE
end

---Liefert die Namen aller Primär-Ziele eines Erzeugnisses als eine Zeile.
---Bewusst nur die Primär-Ziele: sie bekommen die Ware zuerst und beantworten damit die Frage "wo geht das hin?", ohne die Zeile mit jedem möglichen Abnehmer zu füllen.
---@param productionPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@return string text Namen der Primär-Ziele, leer wenn keines eingestellt ist
function Revamp.getPrimaryTargetsText(productionPoint, fillTypeIndex)
	local targets = productionPoint.distributionTargets
	if targets == nil or targets[fillTypeIndex] == nil then
		return ""
	end

	local names = {}
	for uniqueId, entry in pairs(targets[fillTypeIndex]) do
		if entry.level == "PRIMARY" then
			local placeable = g_currentMission.placeableSystem:getPlaceableByUniqueId(uniqueId)
			if placeable ~= nil then
				table.insert(names, placeable:getName())
			end
		end
	end

	-- Ohne das Sortieren stünden die Namen in der zufälligen Reihenfolge der Tabelle und könnten bei jedem Aufbau der Liste anders herum erscheinen.
	table.sort(names)
	return table.concat(names, ", ")
end

---Stellt für den Verwalten-Dialog je Erzeugnis die Liste seiner möglichen Verteilziele samt Stufe, Obergrenze und Kostenvorschau zusammen.
---@param productionPoint table Verteilende ProductionPoint-Instanz
---@return table sections Liste aus {fillTypeIndex = ..., targets = {{productionPoint, uniqueId, level, limit, costsPerHour}, ...}}, costsPerHour nil bei Zielen, die gerade nichts bekommen
function Revamp.getDistributionSections(productionPoint)
	Revamp.removeInvalidDistributionTargets(productionPoint)

	local sections = {}

	for _, fillTypeIndex in ipairs(productionPoint.outputFillTypeIdsArray) do
		local candidates = Revamp.getDistributionCandidates(productionPoint, fillTypeIndex)
		if #candidates > 0 then
			local amountPerHour = Revamp.getHourlyOutputAmount(productionPoint, fillTypeIndex)
			local targets = {}
			local levelCounts = {}

			for _, prodPoint in ipairs(candidates) do
				local uniqueId = prodPoint.owningPlaceable:getUniqueId()
				local level, limit = Revamp.getDistributionTarget(productionPoint, fillTypeIndex, uniqueId)
				levelCounts[level] = (levelCounts[level] or 0) + 1
				table.insert(targets, {productionPoint = prodPoint, uniqueId = uniqueId, level = level, limit = limit})
			end

			-- Kosten bekommt nur die Stufe, die gerade tatsächlich an der Reihe ist: solange es Primär-Ziele gibt, geht die ganze Stundenmenge dorthin und alle übrigen zahlen nichts.
			-- Die Füllstände der Ziele bleiben dabei bewusst außen vor - sonst zeigte die Vorschau nicht die laufenden Kosten, sondern das einmalige Leerräumen eines vollen Lagers.
			local activeLevel = nil
			for _, level in ipairs(Revamp.DISTRIBUTION_ORDER) do
				if levelCounts[level] ~= nil then
					activeLevel = level
					break
				end
			end

			-- Erst in einem zweiten Durchlauf, weil die Kosten eines Ziels davon abhängen, wie viele Ziele sich seine Stufe teilen.
			-- Ziele ohne Kostenangabe behalten nil und zeigen im Dialog einen Strich statt eines Betrags, den sie gar nicht zahlen.
			for _, target in ipairs(targets) do
				if target.level == activeLevel then
					target.costsPerHour = Revamp.getDistributionCostsPerHour(productionPoint, target.productionPoint, amountPerHour, levelCounts[activeLevel])
				end
			end

			table.insert(sections, {fillTypeIndex = fillTypeIndex, targets = targets})
		end
	end

	return sections
end

---Prüft, ob eine Produktionsstätte einen Fülltyp gerade überhaupt gebrauchen kann.
---Maßgeblich ist nicht der Lagerplatz, sondern ob eine eingeschaltete Rezeptlinie diesen Fülltyp verbraucht und gerade auch laufen darf - eine nachts stillstehende Linie soll nicht auf Vorrat beliefert werden und dafür Lieferkosten verursachen.
---@param productionPoint table Empfangende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index
---@return boolean canReceive true, wenn mindestens eine laufende Rezeptlinie den Fülltyp verbraucht
function Revamp.canReceiveFillType(productionPoint, fillTypeIndex)
	for _, production in ipairs(productionPoint.activeProductions) do
		-- modeStatus setzt Revamp.updateProduction in jedem Takt: nil heißt, kein Wetter- oder Zeit-Modus hält die Linie gerade an.
		if production.modeStatus == nil and Revamp.findProductionEntryByType(production.inputs, fillTypeIndex) ~= nil then
			return true
		end
	end
	return false
end

---Entfernt Verteilziele, deren Gebäude es nicht mehr gibt.
---Läuft bei jedem Verteilen und bei jedem Aufbau der Verteilen-Ansicht statt nur beim Speichern: ein Server läuft oft monatelang durch, dort bliebe eine abgerissene Produktion sonst dauerhaft in der Liste stehen und der Dialog griffe weiter auf sie zu.
---Ein Ziel, das nur den Besitzer gewechselt hat, bleibt dagegen stehen - das Gebäude gibt es ja noch, und nach einem Rückkauf stimmt die alte Einstellung wieder.
---Braucht kein Netzwerk-Event: das Gebäude fehlt auf jedem Rechner gleichermaßen, jeder räumt also von sich aus dasselbe weg.
---@param productionPoint table ProductionPoint-Instanz, deren Zielliste geprüft wird
function Revamp.removeInvalidDistributionTargets(productionPoint)
	local targets = productionPoint.distributionTargets
	if targets == nil then
		return
	end

	for fillTypeIndex, fillTypeTargets in pairs(targets) do
		for uniqueId in pairs(fillTypeTargets) do
			if g_currentMission.placeableSystem:getPlaceableByUniqueId(uniqueId) == nil then
				fillTypeTargets[uniqueId] = nil
				Revamp.DebugText("removeInvalidDistributionTargets(): %s verliert das nicht mehr vorhandene Ziel %s", g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex), uniqueId)
			end
		end

		-- Ohne das bliebe für jedes einmal konfigurierte Erzeugnis eine leere Tabelle zurück, die beim Speichern jedes Mal wieder durchlaufen wird.
		if next(fillTypeTargets) == nil then
			targets[fillTypeIndex] = nil
		end
	end
end

---Sammelt alle gerade belieferbaren Ziele eines Fülltyps, nach Verteilstufe getrennt.
---@param distributingPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@param prodPointsInDemand table Produktionsstätten der Farm, die den Fülltyp als Zutat kennen
---@return table buckets Verteilstufe zu Liste aus {productionPoint = ..., freeAmount = ...}
function Revamp.collectDistributionTargets(distributingPoint, fillTypeIndex, prodPointsInDemand)
	local buckets = {}
	for _, level in ipairs(Revamp.DISTRIBUTION_ORDER) do
		buckets[level] = {}
	end

	for _, prodPoint in ipairs(prodPointsInDemand) do
		-- Eine Produktionsstätte, die ihr eigenes Erzeugnis weiterverarbeitet, würde sich sonst selbst beliefern und dafür auch noch Lieferkosten zahlen.
		if prodPoint ~= distributingPoint and prodPoint.owningPlaceable ~= nil and Revamp.canReceiveFillType(prodPoint, fillTypeIndex) then
			local level, limit = Revamp.getDistributionTarget(distributingPoint, fillTypeIndex, prodPoint.owningPlaceable:getUniqueId())

			if level ~= "NEVER" then
				local freeAmount = prodPoint.storage:getFreeCapacity(fillTypeIndex)
				if limit ~= nil then
					freeAmount = math.min(freeAmount, limit - prodPoint.storage:getFillLevel(fillTypeIndex))
				end

				if freeAmount >= Revamp.DISTRIBUTION_MIN_AMOUNT then
					table.insert(buckets[level], {productionPoint = prodPoint, freeAmount = freeAmount})
				end
			end
		end
	end

	return buckets
end

---Bucht eine einzelne Lieferung: Ware wandert vom Lager der einen in das der anderen Produktionsstätte, die Lieferkosten zahlt der Empfänger.
---@param distributingPoint table Verteilende ProductionPoint-Instanz
---@param receivingPoint table Empfangende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index
---@param amount number Zu liefernde Menge in Litern
function Revamp.transferGoods(distributingPoint, receivingPoint, fillTypeIndex, amount)
	local distance = calcDistanceFrom(distributingPoint.owningPlaceable.rootNode, receivingPoint.owningPlaceable.rootNode)
	local costs = amount * distance * ProductionPoint.DIRECT_DELIVERY_PRICE

	g_currentMission:addMoney(-costs, receivingPoint.ownerFarmId, MoneyType.PRODUCTION_COSTS, true)
	receivingPoint.storage:setFillLevel(receivingPoint.storage:getFillLevel(fillTypeIndex) + amount, fillTypeIndex)
	distributingPoint.storage:setFillLevel(distributingPoint.storage:getFillLevel(fillTypeIndex) - amount, fillTypeIndex)

	Revamp.DebugText("transferGoods(): %.0f l %s von %s nach %s, %.2f m, Kosten %.2f", amount, g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex), distributingPoint:getName(), receivingPoint:getName(), distance, costs)
end

---Verteilt eine Menge zu gleichen Teilen auf die Ziele einer Stufe.
---Ein Ziel, das weniger aufnehmen kann als seinen Anteil, nimmt sein Maximum, der Überhang wird unter den übrigen Zielen derselben Stufe neu aufgeteilt - ohne diese weiteren Runden bliebe er liegen, obwohl es noch Abnehmer dafür gibt.
---@param distributingPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index
---@param targets table Ziele dieser Stufe aus Revamp.collectDistributionTargets
---@param amountToDistribute number Verfügbare Menge in Litern
---@return number transferred Tatsächlich gelieferte Menge in Litern
function Revamp.distributeToLevel(distributingPoint, fillTypeIndex, targets, amountToDistribute)
	local remaining = amountToDistribute
	local openTargets = targets

	while remaining >= Revamp.DISTRIBUTION_MIN_AMOUNT and #openTargets > 0 do
		local share = remaining / #openTargets
		local nextTargets = {}
		local roundAmount = 0

		for _, target in ipairs(openTargets) do
			local amount = math.min(share, target.freeAmount)
			if amount > 0 then
				Revamp.transferGoods(distributingPoint, target.productionPoint, fillTypeIndex, amount)
				target.freeAmount = target.freeAmount - amount
				roundAmount = roundAmount + amount
			end
			if target.freeAmount >= Revamp.DISTRIBUTION_MIN_AMOUNT then
				table.insert(nextTargets, target)
			end
		end

		remaining = remaining - roundAmount
		openTargets = nextTargets

		-- Kann kein Ziel mehr etwas aufnehmen, würde die Schleife sonst mit unveränderter Restmenge weiterlaufen.
		if roundAmount <= 0 then
			break
		end
	end

	return amountToDistribute - remaining
end

---Verteilt einen Fülltyp einer Produktionsstätte stufenweise an alle belieferbaren Ziele.
---@param distributingPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@param prodPointsInDemand table Produktionsstätten der Farm, die den Fülltyp als Zutat kennen
function Revamp.distributeFillType(distributingPoint, fillTypeIndex, prodPointsInDemand)
	local amountToDistribute = distributingPoint.storage:getFillLevel(fillTypeIndex)
	if amountToDistribute < Revamp.DISTRIBUTION_MIN_AMOUNT then
		return
	end

	local buckets = Revamp.collectDistributionTargets(distributingPoint, fillTypeIndex, prodPointsInDemand)

	for _, level in ipairs(Revamp.DISTRIBUTION_ORDER) do
		local targets = buckets[level]
		if #targets > 0 then
			local transferred = Revamp.distributeToLevel(distributingPoint, fillTypeIndex, targets, amountToDistribute)
			Revamp.DebugText("distributeFillType(): %s aus %s, Stufe %s an %d Ziele, %.0f l von %.0f l geliefert", g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex), distributingPoint:getName(), level, #targets, transferred, amountToDistribute)

			amountToDistribute = amountToDistribute - transferred
			if amountToDistribute < Revamp.DISTRIBUTION_MIN_AMOUNT then
				return
			end
		end
	end
end

---Registriert das Savegame-XML-Schema für die Verteilziele.
---@param schema XMLSchema Schema, in das die neuen Pfade eingetragen werden
---@param basePath string XML-Basispfad des ProductionPoint-Elements
function Revamp.registerDistributionSavegameXMLPaths(schema, basePath)
	schema:register(XMLValueType.STRING, basePath .. ".distributionTarget(?)#fillType", "Erzeugnis, für das dieses Ziel eingestellt ist")
	schema:register(XMLValueType.STRING, basePath .. ".distributionTarget(?)#targetId", "uniqueId der Produktionsstätte, die beliefert werden soll")
	schema:register(XMLValueType.STRING, basePath .. ".distributionTarget(?)#level", "Verteilstufe: PRIMARY, SECONDARY, REST oder NEVER")
	schema:register(XMLValueType.INT, basePath .. ".distributionTarget(?)#limit", "Obergrenze in Litern, bis zu der dieses Ziel beliefert wird")
end

ProductionPoint.registerSavegameXMLPaths = Utils.prependedFunction(ProductionPoint.registerSavegameXMLPaths, Revamp.registerDistributionSavegameXMLPaths)

---Speichert die Verteilziele eines Produktionspunkts ins Savegame.
---Das Erzeugnis steht als Name in der Datei, nicht als Fülltyp-Nummer: die Nummern verschieben sich, sobald der Spieler einen Mod hinzunimmt oder entfernt, und eine gespeicherte Nummer zeigte danach auf eine ganz andere Ware.
---Vanilla hält es beim Ausgangsmodus genauso (autoDeliverFillType).
---@param self table ProductionPoint-Instanz
---@param xmlFile table XMLFile, in das geschrieben wird
---@param key string XML-Basispfad des ProductionPoint-Elements
---@param usedModNames table Von Vanilla durchgereichte Liste verwendeter Mod-Namen
function Revamp.saveDistributionToXMLFile(self, xmlFile, key, usedModNames) ---@diagnostic disable-line: unused-local
	if self.distributionTargets == nil then
		return
	end

	local xmlIndex = 0
	for fillTypeIndex, fillTypeTargets in pairs(self.distributionTargets) do
		local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)
		if fillTypeName ~= nil then
			for uniqueId, entry in pairs(fillTypeTargets) do
				local targetKey = string.format("%s.distributionTarget(%d)", key, xmlIndex)
				xmlFile:setValue(targetKey .. "#fillType", fillTypeName)
				xmlFile:setValue(targetKey .. "#targetId", uniqueId)
				xmlFile:setValue(targetKey .. "#level", entry.level)
				-- Nur schreiben, wenn es überhaupt eine Obergrenze gibt: ein fehlendes Attribut bedeutet beim Laden "unbegrenzt".
				if entry.limit ~= nil then
					xmlFile:setValue(targetKey .. "#limit", entry.limit)
				end
				xmlIndex = xmlIndex + 1
			end
		end
	end
end

ProductionPoint.saveToXMLFile = Utils.prependedFunction(ProductionPoint.saveToXMLFile, Revamp.saveDistributionToXMLFile)

---Liest die im Savegame gespeicherten Verteilziele und wendet sie an.
---Ob es das Ziel-Placeable überhaupt (noch) gibt, wird hier ausdrücklich nicht geprüft: die Placeables werden nacheinander geladen, ein Ziel weiter hinten in der Datei existiert zum Zeitpunkt dieses Aufrufs also noch gar nicht.
---Nicht mehr vorhandene Ziele räumt stattdessen Revamp.removeInvalidDistributionTargets im laufenden Spiel weg.
---@param self table ProductionPoint-Instanz
---@param superFunc function Ursprüngliches ProductionPoint.loadFromXMLFile
---@param xmlFile table XMLFile des Savegames
---@param key string XML-Basispfad des ProductionPoint-Elements
---@return boolean success true, wenn das ursprüngliche Laden erfolgreich war
function Revamp.loadDistributionFromXMLFile(self, superFunc, xmlFile, key)
	local success = superFunc(self, xmlFile, key)

	xmlFile:iterate(key .. ".distributionTarget", function(_, targetKey)
		local fillTypeName = xmlFile:getValue(targetKey .. "#fillType")
		local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
		if fillTypeIndex == nil then
			-- Kein harter Fehler: die Ware kann aus einem inzwischen entfernten Mod stammen, der Rest des Punktes lädt trotzdem normal weiter.
			Logging.xmlWarning(xmlFile, "Production Revamp: unknown fillType '%s' for a distribution target", tostring(fillTypeName))
			return
		end

		self:setDistributionTarget(fillTypeIndex, xmlFile:getValue(targetKey .. "#targetId"), xmlFile:getValue(targetKey .. "#level"), xmlFile:getValue(targetKey .. "#limit"), true)
	end)

	return success
end

ProductionPoint.loadFromXMLFile = Utils.overwrittenFunction(ProductionPoint.loadFromXMLFile, Revamp.loadDistributionFromXMLFile)

---Verteilt einmal je Spielstunde die Erzeugnisse aller Produktionsstätten, die auf "Verteilen" stehen.
---Ersetzt Vanillas eigene Verteilung vollständig, deren Aufteilung nach freiem Lagerplatz es hier nicht mehr gibt.
---@param self table ProductionChainManager-Instanz
---@param superFunc function Ursprüngliche ProductionChainManager.distributeGoods
function Revamp.distributeGoods(self, superFunc) ---@diagnostic disable-line: unused-local
	if not self.isServer then
		return
	end

	local currentHour = g_currentMission.environment.currentHour

	for _, farmTable in pairs(self.farmIds) do
		if farmTable.productionPoints ~= nil then
			for _, distributingPoint in ipairs(farmTable.productionPoints) do
				Revamp.removeInvalidDistributionTargets(distributingPoint)

				-- Ein wegen seiner Öffnungszeiten geschlossener Betrieb verschickt auch nichts, genauso wie er keine Paletten mehr rausstellt.
				if distributingPoint.openingHoursTable == nil or distributingPoint.openingHoursTable[currentHour] then
					for fillTypeIndex in pairs(distributingPoint.outputFillTypeIdsAutoDeliver) do
						Revamp.distributeFillType(distributingPoint, fillTypeIndex, farmTable.inputTypeToProductionPoints[fillTypeIndex] or {})
					end
				end
			end
		end
	end
end

ProductionChainManager.distributeGoods = Utils.overwrittenFunction(ProductionChainManager.distributeGoods, Revamp.distributeGoods)
