-- Tier-Trigger an einer Produktionsstätte: ein Tiertransporter fährt an den Trigger, der Spieler wählt eine Tiergruppe und eine Anzahl, und die Tiere werden zu einer Warenmenge im Lager der Produktionsstätte.
-- Damit lässt sich zum Beispiel ein Schlachter bauen, dessen Zutat lebende Tiere sind - die Verarbeitung danach ist ein ganz normales Rezept, das diesen Fülltyp als Zutat hat.
--
-- Die XML-Attribute heißen absichtlich genauso wie in der LS22-Fassung, damit die Placeable-XML einer bestehenden Revamp-Produktion unverändert weiterläuft.
--
-- Wie viel ein einzelnes Tier bringt, hängt an drei Dingen: am Gewicht seiner Altersstufe, an seiner Gesundheit und an einem Mastbonus, den ein anderer Mod am Cluster hinterlassen kann.
-- Das Gewicht gibt der Modder für einzelne Altersstufen an, alle Monate dazwischen rechnet Revamp aus (siehe Revamp.loadAnimalWeights).

-- Gründe, aus denen eine Tiergruppe nicht angenommen wird - der Liefer-Dialog macht daraus die Meldung für den Spieler.
Revamp.ANIMAL_REJECT = {
	WRONG_ANIMAL = "wrongAnimal",
	WRONG_AGE = "wrongAge",
	WRONG_HEALTH = "wrongHealth",
	WRONG_TRIGGER = "wrongTrigger"
}

-- Grenzen, mit denen ein Tier-Eingang ohne eigene Angaben arbeitet. Das obere Alter ist absichtlich weit jenseits jeder erreichbaren Tier-Lebensdauer,
-- damit "ab 6 Monaten" ohne zweite Angabe genau das heißt und nicht versehentlich alte Tiere ausschließt.
Revamp.ANIMAL_DEFAULT_MIN_HEALTH = 50
Revamp.ANIMAL_DEFAULT_MAX_HEALTH = 100
Revamp.ANIMAL_DEFAULT_MIN_AGE = 6
Revamp.ANIMAL_DEFAULT_MAX_AGE = 200

---Registriert die XML-Pfade des Tier-Triggers. Wird aus Revamp.registerProductionXMLPaths mitgerufen.
---@param schema XMLSchema Schema der Placeable-XML
---@param basePath string Basis-Pfad des productionPoint-Knotens
function Revamp.registerAnimalXMLPaths(schema, basePath)
	schema:register(XMLValueType.NODE_INDEX, basePath .. ".animalTrigger#triggerNode", "Gemeinsamer Trigger-Node aller Tier-Eingänge dieser Produktionsstätte")
	schema:register(XMLValueType.NODE_INDEX, basePath .. ".animalTrigger.inputs.input(?)#triggerNode", "Eigener Trigger-Node dieses Tier-Eingangs, ohne diese Angabe gilt der gemeinsame")
	schema:register(XMLValueType.STRING, basePath .. ".animalTrigger.inputs.input(?)#animalType", "Tierart, deren Rassen alle angenommen werden - alternativ zu #animalSubType")
	schema:register(XMLValueType.STRING, basePath .. ".animalTrigger.inputs.input(?)#animalSubType", "Einzelne Rasse, die angenommen wird - alternativ zu #animalType")
	schema:register(XMLValueType.STRING, basePath .. ".animalTrigger.inputs.input(?)#inputFillType", "Fülltyp, zu dem die Tiere werden - braucht eine eigene Lagerkapazität", nil, true)
	schema:register(XMLValueType.FLOAT, basePath .. ".animalTrigger.inputs.input(?)#minHealthFactor", "Mindestgesundheit in Prozent", Revamp.ANIMAL_DEFAULT_MIN_HEALTH)
	schema:register(XMLValueType.FLOAT, basePath .. ".animalTrigger.inputs.input(?)#maxHealthFactor", "Höchstgesundheit in Prozent", Revamp.ANIMAL_DEFAULT_MAX_HEALTH)
	schema:register(XMLValueType.FLOAT, basePath .. ".animalTrigger.inputs.input(?)#minAgeMonth", "Mindestalter in Monaten", Revamp.ANIMAL_DEFAULT_MIN_AGE)
	schema:register(XMLValueType.FLOAT, basePath .. ".animalTrigger.inputs.input(?)#maxAgeMonth", "Höchstalter in Monaten", Revamp.ANIMAL_DEFAULT_MAX_AGE)
	schema:register(XMLValueType.BOOL, basePath .. ".animalTrigger.inputs.input(?)#calculateWeight", "Zwischen zwei angegebenen Altersstufen wird die Menge gleichmäßig hochgerechnet, statt bis zur nächsten Stufe gleich zu bleiben", true)
	schema:register(XMLValueType.FLOAT, basePath .. ".animalTrigger.inputs.input(?).weight(?)#ageMonth", "Alter in Monaten, für das diese Menge gilt", Revamp.ANIMAL_DEFAULT_MIN_AGE)
	schema:register(XMLValueType.FLOAT, basePath .. ".animalTrigger.inputs.input(?).weight(?)#value", "Menge in Litern, die ein Tier dieses Alters bei voller Gesundheit bringt", 1000)
end

---Mastbonus eines Clusters als Multiplikator auf die Liefermenge.
---Vanilla-Cluster haben kein solches Feld, MaizePlus hängt cluster.fatteningBonus (0 bis 0.3) an: ein gemästetes Tier bringt dadurch entsprechend mehr.
---@param cluster table AnimalCluster
---@return number factor Multiplikator, 1 wenn kein Mastbonus vorliegt
function Revamp.getAnimalFatteningFactor(cluster)
	if cluster.fatteningBonus == nil then
		return 1
	end
	return 1 + cluster.fatteningBonus
end

---Sortiert zwei Gewichts-Stützwerte nach ihrem Alter.
---@param a table Stützwert mit Feld age
---@param b table Stützwert mit Feld age
---@return boolean isLess true, wenn a jünger als b ist
function Revamp.compareAnimalWeightPoints(a, b)
	return a.age < b.age
end

---Ermittelt die Rassen, die ein Tier-Eingang annimmt - entweder alle Rassen einer Tierart (#animalType) oder eine einzelne Rasse (#animalSubType).
---@param xmlFile table XMLFile der Placeable
---@param animalKey string Pfad des Tier-Eingangs
---@return table|nil subTypeIndices Rassen-Indizes, nil bei fehlerhafter Angabe
function Revamp.getAnimalSubTypeIndices(xmlFile, animalKey)
	local animalSystem = g_currentMission.animalSystem
	local animalTypeName = xmlFile:getValue(animalKey .. "#animalType")
	local animalSubTypeName = xmlFile:getValue(animalKey .. "#animalSubType")

	if animalTypeName == nil and animalSubTypeName == nil then
		Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' needs either an animalType or an animalSubType", animalKey)
		return nil
	end

	-- Eine einzelne Rasse hat Vorrang: wer beides angibt, meint erkennbar genau diese Rasse und nicht ihre ganze Tierart.
	if animalSubTypeName ~= nil then
		local subTypeIndex = animalSystem:getSubTypeIndexByName(animalSubTypeName)
		if subTypeIndex == nil then
			Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' has an unknown animalSubType '%s'", animalKey, animalSubTypeName)
			return nil
		end
		return {subTypeIndex}
	end

	local animalType = animalSystem:getTypeByName(animalTypeName)
	if animalType == nil then
		Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' has an unknown animalType '%s'", animalKey, animalTypeName)
		return nil
	end

	local subTypeIndices = {}
	for _, subTypeIndex in ipairs(animalType.subTypes) do
		table.insert(subTypeIndices, subTypeIndex)
	end
	return subTypeIndices
end

---Liest die Alters- und Gesundheitsgrenzen eines Tier-Eingangs und prüft sie auf sich widersprechende Angaben.
---Unsinnige Werte werden auf den Standard zurückgesetzt statt den Eingang zu verwerfen: eine Produktionsstätte, die wegen einer vertauschten Zahl gar keine Tiere mehr annimmt, wäre für den Spieler kaputt.
---@param xmlFile table XMLFile der Placeable
---@param animalKey string Pfad des Tier-Eingangs
---@return number minHealthFactor Mindestgesundheit in Prozent
---@return number maxHealthFactor Höchstgesundheit in Prozent
---@return number minAgeMonth Mindestalter in Monaten
---@return number maxAgeMonth Höchstalter in Monaten
function Revamp.loadAnimalLimits(xmlFile, animalKey)
	local minHealthFactor = xmlFile:getValue(animalKey .. "#minHealthFactor", Revamp.ANIMAL_DEFAULT_MIN_HEALTH)
	local maxHealthFactor = xmlFile:getValue(animalKey .. "#maxHealthFactor", Revamp.ANIMAL_DEFAULT_MAX_HEALTH)
	local minAgeMonth = math.floor(xmlFile:getValue(animalKey .. "#minAgeMonth", Revamp.ANIMAL_DEFAULT_MIN_AGE))
	local maxAgeMonth = math.floor(xmlFile:getValue(animalKey .. "#maxAgeMonth", Revamp.ANIMAL_DEFAULT_MAX_AGE))

	if minHealthFactor < 0 or minHealthFactor > 100 or maxHealthFactor < 1 or maxHealthFactor > 100 or minHealthFactor > maxHealthFactor then
		Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' has an invalid health range %s - %s (allowed: 0 - 100, min must not be bigger than max), using %d - %d instead", animalKey, tostring(minHealthFactor), tostring(maxHealthFactor), Revamp.ANIMAL_DEFAULT_MIN_HEALTH, Revamp.ANIMAL_DEFAULT_MAX_HEALTH)
		minHealthFactor = Revamp.ANIMAL_DEFAULT_MIN_HEALTH
		maxHealthFactor = Revamp.ANIMAL_DEFAULT_MAX_HEALTH
	end

	if minAgeMonth < 0 or maxAgeMonth < 0 or minAgeMonth > maxAgeMonth then
		Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' has an invalid age range %s - %s (only positive numbers, min must not be bigger than max), using %d - %d instead", animalKey, tostring(minAgeMonth), tostring(maxAgeMonth), Revamp.ANIMAL_DEFAULT_MIN_AGE, Revamp.ANIMAL_DEFAULT_MAX_AGE)
		minAgeMonth = Revamp.ANIMAL_DEFAULT_MIN_AGE
		maxAgeMonth = Revamp.ANIMAL_DEFAULT_MAX_AGE
	end

	return minHealthFactor, maxHealthFactor, minAgeMonth, maxAgeMonth
end

---Baut aus den <weight>-Angaben eines Tier-Eingangs die Liefermenge für jeden einzelnen Monat zwischen Mindest- und Höchstalter.
---Der Modder gibt nur Stützwerte an ("mit 12 Monaten 1000 Liter"), alles dazwischen wird hier gefüllt: mit #calculateWeight gleichmäßig hochgerechnet, ohne bleibt die Menge bis zur nächsten Stufe gleich.
---Vor der ersten und nach der letzten Stufe gilt jeweils deren Wert, damit auch ein Tier außerhalb der angegebenen Stufen eine Menge hat.
---@param xmlFile table XMLFile der Placeable
---@param animalKey string Pfad des Tier-Eingangs
---@param minAgeMonth number Mindestalter in Monaten
---@param maxAgeMonth number Höchstalter in Monaten
---@return table|nil weights Liefermenge je Monat, nil wenn es keine brauchbare Angabe gibt
function Revamp.loadAnimalWeights(xmlFile, animalKey, minAgeMonth, maxAgeMonth)
	local ageToValue = {}
	xmlFile:iterate(animalKey .. ".weight", function(_, weightKey)
		local ageMonth = math.floor(xmlFile:getValue(weightKey .. "#ageMonth", Revamp.ANIMAL_DEFAULT_MIN_AGE))
		local value = xmlFile:getValue(weightKey .. "#value", 1000)

		if ageMonth < minAgeMonth or ageMonth > maxAgeMonth then
			Logging.xmlError(xmlFile, "Production Revamp: weight entry '%s' is outside the age range %d - %d of its animal input and was skipped", weightKey, minAgeMonth, maxAgeMonth)
		elseif value < 0 then
			Logging.xmlError(xmlFile, "Production Revamp: weight entry '%s' has a negative value %s and was skipped", weightKey, tostring(value))
		else
			ageToValue[ageMonth] = value
		end
	end)

	local points = {}
	for age, value in pairs(ageToValue) do
		table.insert(points, {age = age, value = value})
	end

	if #points == 0 then
		Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' has no usable weight entry", animalKey)
		return nil
	end

	table.sort(points, Revamp.compareAnimalWeightPoints)

	local calculateWeight = xmlFile:getValue(animalKey .. "#calculateWeight", true)
	local weights = {}
	local pointIndex = 1

	for age = minAgeMonth, maxAgeMonth do
		-- Solange weiterrücken, wie die nächste Stufe bereits erreicht ist - dadurch läuft die Schleife einmal durch beide Listen statt für jeden Monat neu zu suchen.
		while points[pointIndex + 1] ~= nil and points[pointIndex + 1].age <= age do
			pointIndex = pointIndex + 1
		end

		local currentPoint = points[pointIndex]
		local nextPoint = points[pointIndex + 1]

		if age <= currentPoint.age or nextPoint == nil or not calculateWeight then
			weights[age] = currentPoint.value
		else
			weights[age] = currentPoint.value + (nextPoint.value - currentPoint.value) * (age - currentPoint.age) / (nextPoint.age - currentPoint.age)
		end
	end

	return weights
end

---Lädt einen einzelnen Tier-Eingang und trägt ihn für alle Rassen ein, die er annimmt.
---@param productionPoint table ProductionPoint-Instanz
---@param xmlFile table XMLFile der Placeable
---@param animalKey string Pfad des Tier-Eingangs
---@param mainTriggerNode number|nil Gemeinsamer Trigger-Node aller Tier-Eingänge
---@param components table Komponenten der Placeable
---@param i3dMappings table i3d-Zuordnungen der Placeable
function Revamp.loadAnimalInput(productionPoint, xmlFile, animalKey, mainTriggerNode, components, i3dMappings)
	local subTypeIndices = Revamp.getAnimalSubTypeIndices(xmlFile, animalKey)
	if subTypeIndices == nil then
		return
	end

	local fillTypeName = xmlFile:getValue(animalKey .. "#inputFillType")
	local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
	if fillTypeIndex == nil then
		Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' has an unknown inputFillType '%s'", animalKey, tostring(fillTypeName))
		return
	end

	-- Ohne Lagerplatz für den Zielfülltyp hätten die Tiere nirgends hin: die Umwandlung schreibt ausschließlich ins Lager der Produktionsstätte.
	if productionPoint.storage == nil or not productionPoint.storage.fillTypes[fillTypeIndex] then
		Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' needs a storage capacity for its inputFillType '%s'", animalKey, fillTypeName)
		return
	end

	local triggerNode = xmlFile:getValue(animalKey .. "#triggerNode", mainTriggerNode, components, i3dMappings)
	if triggerNode == nil then
		Logging.xmlError(xmlFile, "Production Revamp: animal input '%s' has no trigger node - set it on the input itself or on animalTrigger#triggerNode", animalKey)
		return
	end

	local minHealthFactor, maxHealthFactor, minAgeMonth, maxAgeMonth = Revamp.loadAnimalLimits(xmlFile, animalKey)

	local weights = Revamp.loadAnimalWeights(xmlFile, animalKey, minAgeMonth, maxAgeMonth)
	if weights == nil then
		return
	end

	local smallestAmount, biggestAmount = math.huge, 0
	for _, value in pairs(weights) do
		smallestAmount = math.min(smallestAmount, value)
		biggestAmount = math.max(biggestAmount, value)
	end

	for _, subTypeIndex in ipairs(subTypeIndices) do
		local subTypeName = g_currentMission.animalSystem:getSubTypeByIndex(subTypeIndex).name
		local animal = productionPoint.animalTypes[subTypeName]

		if animal == nil then
			animal = {
				weight = {},
				inputFillTypes = {},
				minHealthList = {},
				maxHealthList = {},
				recipe = {},
				minHealthFactor = minHealthFactor,
				maxHealthFactor = maxHealthFactor,
				minAgeMonth = minAgeMonth,
				maxAgeMonth = maxAgeMonth
			}
			productionPoint.animalTypes[subTypeName] = animal
		end

		-- Mehrere Eingänge dürfen dieselbe Rasse in verschiedenen Altersstufen zu verschiedenen Fülltypen machen (junge Tiere zu X, ausgewachsene zu Y).
		-- Überlappen sich zwei Eingänge im Alter, gilt für die überlappenden Monate der später eingetragene.
		for age = minAgeMonth, maxAgeMonth do
			animal.weight[age] = weights[age]
			animal.inputFillTypes[age] = fillTypeIndex
			animal.minHealthList[age] = minHealthFactor
			animal.maxHealthList[age] = maxHealthFactor
		end

		-- Für die Fehlermeldung an den Spieler zählen die weitesten Grenzen über alle Eingänge dieser Rasse: was ein einzelner Eingang ablehnt, kann ein anderer annehmen.
		animal.minHealthFactor = math.min(animal.minHealthFactor, minHealthFactor)
		animal.maxHealthFactor = math.max(animal.maxHealthFactor, maxHealthFactor)
		animal.minAgeMonth = math.min(animal.minAgeMonth, minAgeMonth)
		animal.maxAgeMonth = math.max(animal.maxAgeMonth, maxAgeMonth)

		-- Ein Eintrag je Eingang für die Tier-Ansicht im Verwalten-Dialog, die genau diese Bedingungen anzeigt.
		table.insert(animal.recipe, {
			minAge = minAgeMonth,
			maxAge = maxAgeMonth,
			minHealth = minHealthFactor,
			maxHealth = maxHealthFactor,
			fillTypeIndex = fillTypeIndex,
			smallestAmount = smallestAmount,
			biggestAmount = biggestAmount
		})

		local trigger = productionPoint.animalTriggers[triggerNode]
		if trigger == nil then
			trigger = {subTypes = {}}
			productionPoint.animalTriggers[triggerNode] = trigger
			-- Der Index ist das, was im Mehrspieler über die Leitung geht: die Node-Id selbst ist auf jedem Rechner eine andere.
			table.insert(productionPoint.animalIndexToTrigger, triggerNode)
			productionPoint.animalTriggerToIndex[triggerNode] = #productionPoint.animalIndexToTrigger
		end
		trigger.subTypes[subTypeName] = true

		Revamp.DebugText("loadAnimalInput(): %s wird ab %d Monaten und %d %% Gesundheit zu %s (%s bis %s l)", subTypeName, minAgeMonth, minHealthFactor, fillTypeName, tostring(smallestAmount), tostring(biggestAmount))
	end
end

---Lädt den kompletten Tier-Trigger einer Produktionsstätte und legt für jeden verwendeten Trigger-Node ein Trigger-Objekt an.
---@param productionPoint table ProductionPoint-Instanz
---@param xmlFile table XMLFile der Placeable
---@param key string XML-Basispfad des productionPoint-Elements
---@param components table Komponenten der Placeable
---@param i3dMappings table i3d-Zuordnungen der Placeable
function Revamp.loadAnimals(productionPoint, xmlFile, key, components, i3dMappings)
	if not xmlFile:hasProperty(key .. ".animalTrigger") then
		return
	end

	productionPoint.animalTypes = {}
	productionPoint.animalTriggers = {}
	productionPoint.animalTriggerToIndex = {}
	productionPoint.animalIndexToTrigger = {}
	productionPoint.animalTriggerObjects = {}

	local mainTriggerNode = xmlFile:getValue(key .. ".animalTrigger#triggerNode", nil, components, i3dMappings)

	xmlFile:iterate(key .. ".animalTrigger.inputs.input", function(_, animalKey)
		Revamp.loadAnimalInput(productionPoint, xmlFile, animalKey, mainTriggerNode, components, i3dMappings)
	end)

	for index, triggerNode in ipairs(productionPoint.animalIndexToTrigger) do
		productionPoint.animalTriggerObjects[index] = RevampAnimalTrigger.new(productionPoint, triggerNode, index)
	end

	Revamp.linkStorageToUnloadingStation(productionPoint)
end

---Hängt das Lager einer Produktionsstätte an ihre Abladestelle, falls Vanilla das nicht schon getan hat.
---Vanilla verknüpft beide nur, wenn Lager und Abladestelle mindestens einen Fülltyp gemeinsam haben (siehe UnloadingStation:addTargetStorage) - eine Produktionsstätte, deren Zutat von Tieren kommt, braucht dafür aber gar keinen Abladetrigger.
---Ohne die Verknüpfung meldet ProductionPoint:getFillLevel für jede Zutat null, weil es dafür immer die Abladestelle fragt und nie das Lager: die Produktionslinie spränge nie an, und im Menü stünde bei der Zutat 0 l / 0 l, obwohl das Lager voll ist.
---@param productionPoint table ProductionPoint-Instanz
function Revamp.linkStorageToUnloadingStation(productionPoint)
	local unloadingStation = productionPoint.unloadingStation
	local storage = productionPoint.storage

	if unloadingStation == nil or storage == nil or unloadingStation.targetStorages[storage] ~= nil then
		return
	end

	-- Bewusst von Hand statt über addTargetStorage: genau dessen Fülltyp-Prüfung ist ja der Grund, warum das Lager hier fehlt.
	-- Was die Abladestelle annimmt, ändert sich dadurch nicht - sie hat weiterhin nur die Fülltypen ihrer Abladetrigger, hier also gar keine.
	unloadingStation.targetStorages[storage] = storage
	storage:addUnloadingStation(unloadingStation)

	Revamp.DebugText("linkStorageToUnloadingStation(): Lager an die Abladestelle gehaengt, weil kein Abladetrigger einen Fuelltyp des Lagers annimmt")
end

---Entfernt die Trigger einer Produktionsstätte, wenn sie abgerissen oder das Spiel verlassen wird.
---Ohne das bliebe ein Trigger-Callback auf einen Node bestehen, den es nicht mehr gibt.
---@param productionPoint table ProductionPoint-Instanz
function Revamp.deleteAnimalTriggers(productionPoint)
	if productionPoint.animalTriggerObjects == nil then
		return
	end

	for _, trigger in ipairs(productionPoint.animalTriggerObjects) do
		trigger:delete()
	end
	productionPoint.animalTriggerObjects = nil
end

ProductionPoint.delete = Utils.prependedFunction(ProductionPoint.delete, Revamp.deleteAnimalTriggers)

---Prüft, ob eine Produktionsstätte überhaupt Tiere annimmt.
---@param productionPoint table ProductionPoint-Instanz
---@return boolean hasAnimals true, wenn mindestens ein Tier-Eingang geladen wurde
function Revamp.getHasAnimalInputs(productionPoint)
	return productionPoint ~= nil and productionPoint.animalTypes ~= nil and next(productionPoint.animalTypes) ~= nil
end

---Prüft, ob ein bestimmter Trigger diese Rasse annimmt - eine Produktionsstätte kann mehrere Trigger mit unterschiedlichen Tierarten haben.
---@param triggerNode number Trigger-Node
---@param subTypeName string Name der Rasse
---@return boolean allowed true, wenn dieser Trigger die Rasse annimmt
function ProductionPoint:getIsSubTypeAllowedForTrigger(triggerNode, subTypeName)
	local trigger = self.animalTriggers ~= nil and self.animalTriggers[triggerNode] or nil
	if trigger == nil then
		return false
	end

	return trigger.subTypes[subTypeName] == true
end

---Rechnet aus, was eine Tiergruppe an dieser Produktionsstätte bringt und wie viele Tiere davon noch ins Lager passen.
---@param subTypeName string Name der Rasse
---@param health number Gesundheit in Prozent
---@param age number Alter in Monaten
---@param fatteningFactor number Multiplikator aus einem Mastbonus (1 = kein Bonus)
---@return number maxAnimals Anzahl Tiere, die noch ins Lager passen
---@return number|nil fillTypeIndex Fülltyp, zu dem die Tiere werden, nil bei Ablehnung
---@return number amountPerAnimal Liefermenge eines einzelnen Tieres in Litern
---@return string|nil rejectReason Grund aus Revamp.ANIMAL_REJECT, nil wenn die Tiere angenommen werden
function ProductionPoint:calculateAnimals(subTypeName, health, age, fatteningFactor)
	local animal = self.animalTypes ~= nil and self.animalTypes[subTypeName] or nil
	if animal == nil then
		return 0, nil, 0, Revamp.ANIMAL_REJECT.WRONG_ANIMAL
	end
	if animal.weight[age] == nil then
		return 0, nil, 0, Revamp.ANIMAL_REJECT.WRONG_AGE
	end
	if health < animal.minHealthList[age] or health > animal.maxHealthList[age] then
		return 0, nil, 0, Revamp.ANIMAL_REJECT.WRONG_HEALTH
	end

	local fillTypeIndex = animal.inputFillTypes[age]
	-- Ein krankes Tier bringt weniger, aber nie gar nichts: bei 0 % Gesundheit bleibt ein Zehntel der Menge übrig.
	local healthFactor = 0.1 + 0.9 * health / animal.maxHealthList[age]
	local amountPerAnimal = animal.weight[age] * healthFactor * fatteningFactor

	if amountPerAnimal <= 0 then
		return 0, fillTypeIndex, 0, nil
	end

	-- getFreeCapacity statt Kapazität minus Bestand, weil sich mehrere Waren einer Produktionsstätte einen Lagerplatz teilen können und dann weniger frei ist als die eigene Kapazität verspricht.
	local maxAnimals = math.floor(self.storage:getFreeCapacity(fillTypeIndex) / amountPerAnimal)

	return maxAnimals, fillTypeIndex, amountPerAnimal, nil
end

---Wandelt Tiere in eine Warenmenge im Lager um. Läuft serverseitig (siehe ProductionPoint:ReceiveMoveAnimalsEvent).
---@param subTypeName string Name der Rasse
---@param health number Gesundheit in Prozent
---@param age number Alter in Monaten
---@param numAnimals number Anzahl Tiere
---@param fatteningFactor number Multiplikator aus einem Mastbonus (1 = kein Bonus)
---@return boolean success true, wenn die Tiere eingebucht wurden
function ProductionPoint:transportAnimals(subTypeName, health, age, numAnimals, fatteningFactor)
	local maxAnimals, fillTypeIndex, amountPerAnimal, rejectReason = self:calculateAnimals(subTypeName, health, age, fatteningFactor)

	if rejectReason ~= nil or fillTypeIndex == nil or numAnimals < 1 or numAnimals > maxAnimals then
		return false
	end

	self.storage:setFillLevel(self.storage:getFillLevel(fillTypeIndex) + amountPerAnimal * numAnimals, fillTypeIndex)

	return true
end

---Nimmt die Tiere entgegen, die ein Spieler an einem Trigger abgibt, und verkleinert dafür die Tiergruppe im Transporter. Läuft serverseitig.
---Welcher Transporter am Trigger steht, weiß der Server aus seinem eigenen Trigger, und die Gesundheits-/Alterswerte nimmt er ebenfalls aus seiner eigenen Tiergruppe -
---der Client schickt also nur, welche Gruppe und wie viele Tiere gemeint sind.
---@param triggerIndex number Nummer des Triggers innerhalb der Produktionsstätte
---@param clusterId number Id der Tiergruppe im Transporter
---@param numAnimals number Anzahl Tiere
---@param connection? table Netzwerkverbindung des auslösenden Spielers, nil wenn die Aktion vom eigenen Rechner kommt
function ProductionPoint:ReceiveMoveAnimalsEvent(triggerIndex, clusterId, numAnimals, connection)
	if not g_currentMission:getHasPlayerPermission("tradeAnimals", connection, self:getOwnerFarmId()) then
		return
	end

	local trigger = self.animalTriggerObjects ~= nil and self.animalTriggerObjects[triggerIndex] or nil
	if trigger == nil or trigger.loadingVehicle == nil then
		return
	end

	local cluster = trigger.loadingVehicle:getClusterById(clusterId)
	if cluster == nil or numAnimals > cluster:getNumAnimals() then
		return
	end

	local subType = g_currentMission.animalSystem:getSubTypeByIndex(cluster:getSubTypeIndex())
	if subType == nil or not self:getIsSubTypeAllowedForTrigger(trigger.triggerNode, subType.name) then
		return
	end

	if self:transportAnimals(subType.name, cluster.health, cluster:getAge(), numAnimals, Revamp.getAnimalFatteningFactor(cluster)) then
		cluster:changeNumAnimals(-numAnimals)
		-- Ohne das behält der Transporter seine Tiere bis zum nächsten regulären Abgleich, der Spieler sieht die Abgabe also erst mit Verzögerung.
		trigger.loadingVehicle:getClusterSystem():updateNow()
	end
end

---Liefert den Text, mit dem eine abgelehnte Tiergruppe im Liefer-Dialog erklärt wird.
---@param productionPoint table ProductionPoint-Instanz
---@param subTypeName string Name der Rasse
---@param rejectReason string|nil Grund aus Revamp.ANIMAL_REJECT
---@param maxAnimals number Anzahl Tiere, die noch ins Lager passen
---@return string|nil rejectText Erklärung für den Spieler, nil wenn die Gruppe angenommen wird
function Revamp.getAnimalRejectText(productionPoint, subTypeName, rejectReason, maxAnimals)
	local animal = productionPoint.animalTypes ~= nil and productionPoint.animalTypes[subTypeName] or nil

	if rejectReason == Revamp.ANIMAL_REJECT.WRONG_ANIMAL or animal == nil then
		return g_i18n:getText("revamp_animalNotValid")
	end
	if rejectReason == Revamp.ANIMAL_REJECT.WRONG_TRIGGER then
		return g_i18n:getText("revamp_animalNotValidForTrigger")
	end
	if rejectReason == Revamp.ANIMAL_REJECT.WRONG_AGE then
		-- Ohne angegebenes Höchstalter stünde in der Meldung sonst die Vorgabe von 200 Monaten, ein Alter, das kein Tier je erreicht.
		if animal.maxAgeMonth >= Revamp.ANIMAL_DEFAULT_MAX_AGE then
			return string.format(g_i18n:getText("revamp_animalAgeErrorFrom"), animal.minAgeMonth)
		end
		return string.format(g_i18n:getText("revamp_animalAgeError"), animal.minAgeMonth, animal.maxAgeMonth)
	end
	if rejectReason == Revamp.ANIMAL_REJECT.WRONG_HEALTH then
		return string.format(g_i18n:getText("revamp_animalHealthError"), animal.minHealthFactor, animal.maxHealthFactor)
	end
	-- Kein Ablehnungsgrund, aber es passt kein einziges Tier mehr hinein.
	if maxAnimals < 1 then
		return g_i18n:getText("revamp_animalNoSpace")
	end

	return nil
end

---Sortiert zwei Zeilen der Tier-Ansicht nach Rasse und innerhalb einer Rasse nach Mindestalter.
---@param a table Zeile der Tier-Ansicht
---@param b table Zeile der Tier-Ansicht
---@return boolean isLess true, wenn a vor b steht
function Revamp.compareAnimalRows(a, b)
	if a.title ~= b.title then
		return a.title < b.title
	end
	return a.minAge < b.minAge
end

---Stellt für die Tier-Ansicht im Verwalten-Dialog zusammen, welche Tiere eine Produktionsstätte annimmt und was sie einbringen.
---Eine Rasse kann mehrere Zeilen haben, wenn der Modder für verschiedene Altersstufen verschiedene Bedingungen oder Zielfülltypen angegeben hat.
---@param productionPoint table ProductionPoint-Instanz
---@return table rows Zeilen der Tier-Ansicht
function Revamp.getAnimalRows(productionPoint)
	local rows = {}

	if productionPoint.animalTypes == nil then
		return rows
	end

	local animalSystem = g_currentMission.animalSystem

	for subTypeName, animal in pairs(productionPoint.animalTypes) do
		local subType = animalSystem:getSubTypeByName(subTypeName)

		for _, recipe in ipairs(animal.recipe) do
			-- Gezeigt wird das Bild des höchsten angenommenen Alters: ein Schlachter nimmt in der Regel ausgewachsene Tiere, und ein Kälberbild wäre dort irreführend.
			local visual = animalSystem:getVisualByAge(subType.subTypeIndex, recipe.maxAge)

			table.insert(rows, {
				title = g_fillTypeManager:getFillTypeTitleByIndex(subType.fillTypeIndex),
				imageFilename = visual ~= nil and visual.store.imageFilename or nil,
				minAge = recipe.minAge,
				maxAge = recipe.maxAge,
				minHealth = recipe.minHealth,
				maxHealth = recipe.maxHealth,
				fillTypeIndex = recipe.fillTypeIndex,
				smallestAmount = recipe.smallestAmount,
				biggestAmount = recipe.biggestAmount
			})
		end
	end

	table.sort(rows, Revamp.compareAnimalRows)

	return rows
end

-- Ein Trigger-Objekt je Trigger-Node einer Produktionsstätte. Aufgebaut wie Vanillas AnimalLoadingTrigger, nur ohne Tierhandel:
-- es merkt sich den Transporter im Trigger und bietet dem Spieler, der ihn fährt, das Abgeben an.
RevampAnimalTrigger = {}
local RevampAnimalTrigger_mt = Class(RevampAnimalTrigger)

---Legt einen Tier-Trigger an und meldet ihn bei der Engine an.
---@param productionPoint table ProductionPoint-Instanz, zu der der Trigger gehört
---@param triggerNode number Trigger-Node aus der Placeable
---@param triggerIndex number Nummer des Triggers innerhalb der Produktionsstätte
---@return table self Neue RevampAnimalTrigger-Instanz
function RevampAnimalTrigger.new(productionPoint, triggerNode, triggerIndex)
	local self = setmetatable({}, RevampAnimalTrigger_mt)
	self.productionPoint = productionPoint
	self.triggerNode = triggerNode
	self.triggerIndex = triggerIndex
	self.loadingVehicle = nil
	self.isEnabled = true
	self.activatable = RevampAnimalTriggerActivatable.new(self)

	addTrigger(triggerNode, "triggerCallback", self)

	return self
end

---Meldet den Trigger bei der Engine und beim Aktivieren-System wieder ab.
function RevampAnimalTrigger:delete()
	g_currentMission.activatableObjectsSystem:removeActivatable(self.activatable)

	if self.triggerNode ~= nil then
		removeTrigger(self.triggerNode)
		self.triggerNode = nil
	end

	self.loadingVehicle = nil
end

---Merkt sich, welcher Tiertransporter am Trigger steht, und schaltet das Aktivieren entsprechend ein oder aus.
---@param loadingVehicle table|nil Transporter am Trigger, nil wenn keiner mehr da ist
function RevampAnimalTrigger:setLoadingTrailer(loadingVehicle)
	-- Der Transporter merkt sich seinerseits den Trigger und meldet sich darüber ab, wenn er gelöscht wird, solange er noch darin steht.
	if self.loadingVehicle ~= nil and self.loadingVehicle.setLoadingTrigger ~= nil then
		self.loadingVehicle:setLoadingTrigger(nil)
	end

	self.loadingVehicle = loadingVehicle

	if self.loadingVehicle ~= nil and self.loadingVehicle.setLoadingTrigger ~= nil then
		self.loadingVehicle:setLoadingTrigger(self)
		g_currentMission.activatableObjectsSystem:addActivatable(self.activatable)
	else
		g_currentMission.activatableObjectsSystem:removeActivatable(self.activatable)
	end
end

---Trigger-Rückruf der Engine: reagiert nur auf Fahrzeuge, die überhaupt Tiere transportieren können.
---@param triggerId number Node des auslösenden Triggers
---@param otherId number Node des eingetretenen Objekts
---@param onEnter boolean true beim Eintreten
---@param onLeave boolean true beim Verlassen
---@param onStay boolean true beim Verweilen
function RevampAnimalTrigger:triggerCallback(triggerId, otherId, onEnter, onLeave, onStay) ---@diagnostic disable-line: unused-local
	if not self.isEnabled or (not onEnter and not onLeave) then
		return
	end

	local vehicle = g_currentMission.nodeToObject[otherId]
	if vehicle == nil or vehicle.getSupportsAnimalType == nil then
		return
	end

	if onEnter then
		self:setLoadingTrailer(vehicle)

		-- Auf Konsolen öffnet sich ein solcher Trigger von selbst, sobald man davor steht - dieselbe Bedienung wie an Vanillas Tier-Triggern.
		if Platform.gameplay.autoActivateTrigger and self.activatable:getIsActivatable() then
			self.activatable:run()

			local rootVehicle = vehicle.rootVehicle
			if rootVehicle.brakeToStop ~= nil then
				rootVehicle:brakeToStop()
			end
		end
	elseif vehicle == self.loadingVehicle then
		self:setLoadingTrailer(nil)
	end
end

---Beschreibt eine einzelne Tiergruppe aus dem Transporter für den Liefer-Dialog: Anzahl, Rasse, Alter und Gesundheit, dazu was die Produktionsstätte daraus macht.
---@param trigger table RevampAnimalTrigger-Instanz, an der abgegeben wird
---@param cluster table AnimalCluster aus dem Transporter
---@param subType table Rasse der Tiergruppe
---@return table item Eintrag für den Liefer-Dialog
function Revamp.getAnimalDeliveryItem(trigger, cluster, subType)
	local productionPoint = trigger.productionPoint
	local numAnimals = cluster:getNumAnimals()
	local visual = g_currentMission.animalSystem:getVisualByAge(cluster:getSubTypeIndex(), cluster:getAge())

	local item = {
		clusterId = cluster.id,
		numAnimals = numAnimals,
		imageFilename = visual ~= nil and visual.store.imageFilename or nil,
		title = string.format("%d x %s - %s - %d %%", numAnimals, g_fillTypeManager:getFillTypeTitleByIndex(subType.fillTypeIndex), g_i18n:formatNumMonth(cluster:getAge()), cluster.health)
	}

	item.maxAnimals, item.fillTypeIndex, item.amountPerAnimal, item.rejectReason = productionPoint:calculateAnimals(subType.name, cluster.health, cluster:getAge(), Revamp.getAnimalFatteningFactor(cluster))

	-- Eine Rasse, die die Produktionsstätte grundsätzlich annimmt, kann trotzdem an einem anderen ihrer Trigger abzugeben sein.
	if item.rejectReason ~= Revamp.ANIMAL_REJECT.WRONG_ANIMAL and not productionPoint:getIsSubTypeAllowedForTrigger(trigger.triggerNode, subType.name) then
		item.maxAnimals = 0
		item.fillTypeIndex = nil
		item.amountPerAnimal = 0
		item.rejectReason = Revamp.ANIMAL_REJECT.WRONG_TRIGGER
	end

	item.maxAnimals = math.min(item.maxAnimals, numAnimals)
	item.rejectText = Revamp.getAnimalRejectText(productionPoint, subType.name, item.rejectReason, item.maxAnimals)

	return item
end

---Stellt zusammen, was der Transporter am Trigger geladen hat und was die Produktionsstätte davon annimmt.
---@return table items Ein Eintrag je Tiergruppe im Transporter
function RevampAnimalTrigger:getDeliveryItems()
	local items = {}
	local vehicle = self.loadingVehicle

	if vehicle == nil or vehicle.getClusters == nil then
		return items
	end

	local animalSystem = g_currentMission.animalSystem

	for _, cluster in ipairs(vehicle:getClusters()) do
		local subType = animalSystem:getSubTypeByIndex(cluster:getSubTypeIndex())
		if subType ~= nil then
			table.insert(items, Revamp.getAnimalDeliveryItem(self, cluster, subType))
		end
	end

	return items
end

---Öffnet den Liefer-Dialog für den Transporter am Trigger.
function RevampAnimalTrigger:openAnimalMenu()
	local items = self:getDeliveryItems()

	if #items == 0 then
		return
	end

	RevampAnimalDeliveryDialog.show(self, items)
end

---Schickt die Abgabe an den Server.
---@param clusterId number Id der abgegebenen Tiergruppe
---@param numAnimals number Anzahl abgegebener Tiere
function RevampAnimalTrigger:deliverAnimals(clusterId, numAnimals)
	Revamp_EventMoveAnimals.sendEvent(self.productionPoint, self.triggerIndex, clusterId, numAnimals)
end

-- Der Eintrag in der Aktivieren-Anzeige, solange ein Transporter am Trigger steht.
RevampAnimalTriggerActivatable = {}
local RevampAnimalTriggerActivatable_mt = Class(RevampAnimalTriggerActivatable)

---Erzeugt den Aktivieren-Eintrag eines Tier-Triggers.
---@param trigger table RevampAnimalTrigger-Instanz
---@return table self Neue RevampAnimalTriggerActivatable-Instanz
function RevampAnimalTriggerActivatable.new(trigger)
	local self = setmetatable({}, RevampAnimalTriggerActivatable_mt)
	self.owner = trigger
	self.activateText = g_i18n:getText("revamp_transferAnimals")

	return self
end

---Entscheidet, ob das Abgeben gerade angeboten wird.
---@param dirX number Blickrichtung des Spielers
---@param dirY number Blickrichtung des Spielers
---@param dirZ number Blickrichtung des Spielers
---@return boolean isActivatable true, wenn der Spieler jetzt Tiere abgeben kann
function RevampAnimalTriggerActivatable:getIsActivatable(dirX, dirY, dirZ) ---@diagnostic disable-line: unused-local
	local owner = self.owner

	if not owner.isEnabled or owner.loadingVehicle == nil or g_localPlayer == nil then
		return false
	end
	if g_gui.currentGui ~= nil then
		return false
	end
	if not g_currentMission:getHasPlayerPermission("tradeAnimals") then
		return false
	end
	if owner.productionPoint:getOwnerFarmId() ~= g_currentMission:getFarmId() then
		return false
	end

	-- Nur wer den Transporter selbst fährt, gibt seine Tiere ab - vom Boden aus in einen fremden Anhänger zu greifen wäre eine Bedienung, die es an Vanillas Tier-Triggern auch nicht gibt.
	return owner.loadingVehicle.rootVehicle == g_localPlayer:getCurrentVehicle()
end

---Öffnet den Liefer-Dialog.
function RevampAnimalTriggerActivatable:run()
	self.owner:openAnimalMenu()
end

---Abstand des Triggers zum Spieler, damit bei mehreren gleichzeitig erreichbaren Auslösern der nächstgelegene angeboten wird.
---@param x number Position des Spielers
---@param y number Position des Spielers
---@param z number Position des Spielers
---@return number distance Abstand in Metern
function RevampAnimalTriggerActivatable:getDistance(x, y, z)
	if self.owner.triggerNode == nil then
		return math.huge
	end

	local triggerX, triggerY, triggerZ = getWorldTranslation(self.owner.triggerNode)

	return MathUtil.vector3Length(x - triggerX, y - triggerY, z - triggerZ)
end
