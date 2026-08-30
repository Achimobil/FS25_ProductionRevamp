-- Blendet Objekte im Modell abhängig vom Lagerbestand nacheinander ein: je voller das Lager, desto mehr Kinder des angegebenen Wurzelknotens sind sichtbar.
-- Gedacht für Dinge, die man im Lager tatsächlich stapeln würde - Paletten, Säcke, Kisten - statt für eine abstrakte Anzeige.
--
-- Eine Spezialisierung für beide Placeable-Arten: die LS22-Fassung hatte dafür zwei nahezu identische Dateien (Silo und Produktionsstätte),
-- die sich nur in der Voraussetzungs-Prüfung, im XML-Pfad und in der Herkunft des Füllstands unterschieden.
-- Der XML-Pfad ist deshalb jetzt für beide derselbe und hängt direkt unter <placeable>, statt unter <silo> bzw. <productionPoint>.
--
-- Gewächshäuser sind mit abgedeckt, ohne dass sie eigens genannt werden müssten: der Vanilla-Typ "greenhouse" bringt die productionPoint-Spezialisierung selbst mit.

RevampObjectFillLevelSpecialization = {}

-- Der Bestand ändert sich beim Befüllen laufend, das Umschalten von Sichtbarkeit und Kollision ist dagegen vergleichsweise teuer.
-- Gesammelt wird deshalb über ein festes Zeitfenster: erst wenn seit der letzten Änderung so lange nichts mehr passiert ist, wird einmal neu gezeichnet.
RevampObjectFillLevelSpecialization.UPDATE_DELAY = 5000

-- Kollisionsmaske eines ausgeblendeten Objekts: es soll nicht weiter im Weg stehen, wenn man es nicht mehr sieht.
-- Die Maske eines sichtbaren Objekts steht dagegen nirgends fest, sondern wird beim Laden aus dem Modell gelesen und beim Einblenden wieder gesetzt.
-- Die LS22-Fassung trug hier eine feste Zahl ein, die aus dem alten Kollisionssystem des LS22 stammte und im LS25 nicht mehr dasselbe bedeutet.
RevampObjectFillLevelSpecialization.COLLISION_MASK_HIDDEN = 0

---@param specializations table Spezialisierungen des Placeable-Typs
---@return boolean present true, wenn die Placeable ein Lager mitbringt, auf das sich die Anzeige beziehen kann
function RevampObjectFillLevelSpecialization.prerequisitesPresent(specializations)
	return SpecializationUtil.hasSpecialization(PlaceableSilo, specializations)
		or SpecializationUtil.hasSpecialization(PlaceableProductionPoint, specializations)
end

---@param placeableType table Placeable-Typ, an dem die Spezialisierung hängt
function RevampObjectFillLevelSpecialization.registerEventListeners(placeableType)
	SpecializationUtil.registerEventListener(placeableType, "onLoad", RevampObjectFillLevelSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", RevampObjectFillLevelSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onPostFinalizePlacement", RevampObjectFillLevelSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onUpdate", RevampObjectFillLevelSpecialization)
end

---@param placeableType table Placeable-Typ, an dem die Spezialisierung hängt
function RevampObjectFillLevelSpecialization.registerFunctions(placeableType)
	SpecializationUtil.registerFunction(placeableType, "updateRevampObjectFillLevels", RevampObjectFillLevelSpecialization.updateRevampObjectFillLevels)
	SpecializationUtil.registerFunction(placeableType, "setRevampObjectFillLevelDirty", RevampObjectFillLevelSpecialization.setRevampObjectFillLevelDirty)
end

---@param schema XMLSchema Schema der Placeable-XML
---@param basePath string Basis-Pfad des placeable-Knotens
function RevampObjectFillLevelSpecialization.registerXMLPaths(schema, basePath)
	-- Eigener Typ statt des Namens einer fremden Spezialisierung: die LS22-Silo-Fassung trug hier versehentlich "SiloDisplay" und kollidierte damit im Schema mit der Zahlenanzeige.
	schema:setXMLSpecializationType("RevampObjectFillLevel")

	schema:register(XMLValueType.NODE_INDEX, basePath .. ".revampObjectFillLevels.revampObjectFillLevel(?)#rootNode", "Wurzelknoten, dessen Kinder abhängig vom Bestand ein- und ausgeblendet werden")
	schema:register(XMLValueType.BOOL, basePath .. ".revampObjectFillLevels.revampObjectFillLevel(?)#useSubNodesInsteadOfMainNodes", "Nimmt die zweite statt der ersten Ebene unterhalb des Wurzelknotens als anzuzeigende Objekte", false)
	schema:register(XMLValueType.STRING, basePath .. ".revampObjectFillLevels.revampObjectFillLevel(?)#fillType", "Fülltyp, dessen Bestand die Anzeige steuert")
	schema:register(XMLValueType.STRING, basePath .. ".revampObjectFillLevels.revampObjectFillLevel(?)#fillTypes", "Mehrere Fülltypen, deren Bestände zusammengezählt die Anzeige steuern")
	schema:register(XMLValueType.STRING, basePath .. ".revampObjectFillLevels.revampObjectFillLevel(?)#fillTypeCategories", "Fülltyp-Kategorien, deren Bestände zusammengezählt die Anzeige steuern")
	schema:register(XMLValueType.INT, basePath .. ".revampObjectFillLevels.revampObjectFillLevel(?)#maxAtFillLevel", "Bestand, ab dem alle Objekte sichtbar sind")
	schema:register(XMLValueType.INT, basePath .. ".revampObjectFillLevels.revampObjectFillLevel(?)#firstAtFillLevel", "Bestand, ab dem das erste Objekt sichtbar ist. Ohne Angabe teilt sich der Höchstbestand gleichmäßig auf alle Objekte auf")
	schema:register(XMLValueType.BOOL, basePath .. ".revampObjectFillLevels.revampObjectFillLevel(?)#invert", "Dreht das Ein- und Ausblenden um: die Objekte verschwinden, je voller das Lager wird", false)

	schema:setXMLSpecializationType()
end

---Liefert die Lager, aus denen sich der angezeigte Bestand ergibt.
---Beim Silo bewusst über die Lager selbst und nicht über die Verladestation: die nimmt ein Lager nur auf, wenn dessen Fülltypen zu einem ihrer Ladepunkte passen -
---ein Silo ohne Verladestelle hätte dort gar keine Lager stehen, obwohl welche da sind.
---@param placeable table Placeable-Instanz
---@return table storages Liste der Lager
function RevampObjectFillLevelSpecialization.getStorages(placeable)
	if placeable.spec_silo ~= nil then
		return Revamp.getSiloStorages(placeable)
	end

	return {placeable.spec_productionPoint.productionPoint.storage}
end

---Liefert den Bestand eines Fülltyps über alle Lager der Placeable.
---@param placeable table Placeable-Instanz
---@param fillTypeIndex number FillType-Index
---@return number fillLevel Bestand in Litern
function RevampObjectFillLevelSpecialization.getFillLevel(placeable, fillTypeIndex)
	local fillLevel = 0
	for _, storage in ipairs(RevampObjectFillLevelSpecialization.getStorages(placeable)) do
		fillLevel = fillLevel + storage:getFillLevel(fillTypeIndex)
	end

	return fillLevel
end

---Sammelt die Fülltypen eines Eintrags aus #fillType, #fillTypes und #fillTypeCategories.
---@param xmlFile table XMLFile der Placeable
---@param key string XML-Pfad des revampObjectFillLevel-Knotens
---@return table fillTypes Menge der FillType-Indizes
function RevampObjectFillLevelSpecialization.loadFillTypes(xmlFile, key)
	local fillTypes = {}

	local singleName = xmlFile:getValue(key .. "#fillType")
	local names = xmlFile:getValue(key .. "#fillTypes")
	if singleName ~= nil and names ~= nil then
		Logging.xmlWarning(xmlFile, "Production Revamp: '%s' has both 'fillType' and 'fillTypes', only one of the two is used", key)
	end
	names = names or singleName

	if names ~= nil then
		for _, fillTypeName in ipairs(names:split(" ")) do
			local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
			if fillTypeIndex == nil then
				Logging.xmlWarning(xmlFile, "Production Revamp: '%s' has unknown fillType '%s'", key, fillTypeName)
			else
				fillTypes[fillTypeIndex] = true
			end
		end
	end

	local categoryNames = xmlFile:getValue(key .. "#fillTypeCategories")
	if categoryNames ~= nil then
		for _, fillTypeIndex in pairs(g_fillTypeManager:getFillTypesByCategoryNames(categoryNames, "Warning: Production Revamp: revampObjectFillLevel has invalid fillTypeCategory '%s'")) do
			fillTypes[fillTypeIndex] = true
		end
	end

	return fillTypes
end

---Merkt sich einen Knoten samt seiner Kollisionsmaske aus dem Modell, damit sie beim Einblenden wieder hergestellt werden kann.
---Die Kollision eines Objekts hängt oft nicht am Objekt selbst, sondern an einer eigenen Shape darunter - deshalb kommt die erste Ebene darunter mit in die Liste.
---@param node number Knoten, der ein- und ausgeblendet wird
---@return table object Eintrag mit Knoten und den ursprünglichen Kollisionsmasken
function RevampObjectFillLevelSpecialization.buildObjectEntry(node)
	local object = {node = node, collisionNodes = {{node = node, mask = getCollisionFilterMask(node)}}}

	for i = 0, getNumOfChildren(node) - 1 do
		local childNode = getChildAt(node, i)
		table.insert(object.collisionNodes, {node = childNode, mask = getCollisionFilterMask(childNode)})
	end

	return object
end

---Sammelt die Objekte, die ein Eintrag ein- und ausblendet.
---@param rootNode number Wurzelknoten aus der XML
---@param useSubNodes boolean true, wenn die zweite statt der ersten Ebene gemeint ist
---@return table objects Objekte in der Reihenfolge, in der sie sichtbar werden
function RevampObjectFillLevelSpecialization.collectObjects(rootNode, useSubNodes)
	local objects = {}

	for i = 0, getNumOfChildren(rootNode) - 1 do
		local childNode = getChildAt(rootNode, i)
		if not useSubNodes then
			table.insert(objects, RevampObjectFillLevelSpecialization.buildObjectEntry(childNode))
		else
			for j = 0, getNumOfChildren(childNode) - 1 do
				table.insert(objects, RevampObjectFillLevelSpecialization.buildObjectEntry(getChildAt(childNode, j)))
			end
		end
	end

	return objects
end

---@param savegame? table Spielstanddaten, nil bei einer neu gebauten Placeable
function RevampObjectFillLevelSpecialization:onLoad(savegame) ---@diagnostic disable-line: unused-local
	self.spec_revampObjectFillLevel = {}
	local spec = self.spec_revampObjectFillLevel
	local xmlFile = self.xmlFile

	spec.objectFillLevels = {}
	spec.isDirty = true
	spec.lastUpdateTime = 0

	xmlFile:iterate("placeable.revampObjectFillLevels.revampObjectFillLevel", function(_, key)
		local rootNode = xmlFile:getValue(key .. "#rootNode", nil, self.components, self.i3dMappings)
		if rootNode == nil then
			Logging.xmlError(xmlFile, "Production Revamp: '%s' has no valid rootNode, entry is skipped", key)
			return
		end

		local objectFillLevel = {}
		objectFillLevel.rootNode = rootNode
		objectFillLevel.objects = RevampObjectFillLevelSpecialization.collectObjects(rootNode, xmlFile:getValue(key .. "#useSubNodesInsteadOfMainNodes", false))
		if #objectFillLevel.objects == 0 then
			Logging.xmlError(xmlFile, "Production Revamp: rootNode of '%s' has no children to show, entry is skipped", key)
			return
		end

		objectFillLevel.fillTypes = RevampObjectFillLevelSpecialization.loadFillTypes(xmlFile, key)
		if next(objectFillLevel.fillTypes) == nil then
			Logging.xmlError(xmlFile, "Production Revamp: '%s' needs at least one of 'fillType', 'fillTypes' or 'fillTypeCategories', entry is skipped", key)
			return
		end

		objectFillLevel.maxAtFillLevel = xmlFile:getValue(key .. "#maxAtFillLevel")
		if objectFillLevel.maxAtFillLevel == nil then
			Logging.xmlError(xmlFile, "Production Revamp: '%s' needs a 'maxAtFillLevel', entry is skipped", key)
			return
		end

		-- Ohne eigene Angabe teilt sich der Höchstbestand gleichmäßig auf die Objekte auf, das erste erscheint also bei einem vollen Anteil.
		objectFillLevel.firstAtFillLevel = xmlFile:getValue(key .. "#firstAtFillLevel")
			or objectFillLevel.maxAtFillLevel / #objectFillLevel.objects

		objectFillLevel.invert = xmlFile:getValue(key .. "#invert", false)
		-- Das erste Objekt steht schon bei firstAtFillLevel, die restlichen verteilen sich auf den Weg von dort bis maxAtFillLevel.
		objectFillLevel.fillLevelStep = (objectFillLevel.maxAtFillLevel - objectFillLevel.firstAtFillLevel) / math.max(#objectFillLevel.objects - 1, 1)

		table.insert(spec.objectFillLevels, objectFillLevel)
	end)

	function spec.fillLevelChangedCallback(fillType, delta) ---@diagnostic disable-line: unused-local
		self:setRevampObjectFillLevelDirty()
	end
end

---@param savegame? table Spielstanddaten, nil bei einer neu gebauten Placeable
function RevampObjectFillLevelSpecialization:onFinalizePlacement(savegame) ---@diagnostic disable-line: unused-local
	local spec = self.spec_revampObjectFillLevel

	for _, storage in pairs(RevampObjectFillLevelSpecialization.getStorages(self)) do
		storage:addFillLevelChangedListeners(spec.fillLevelChangedCallback)
	end
end

---@param savegame? table Spielstanddaten, nil bei einer neu gebauten Placeable
function RevampObjectFillLevelSpecialization:onPostFinalizePlacement(savegame) ---@diagnostic disable-line: unused-local
	self:updateRevampObjectFillLevels()
end

---Merkt vor, dass sich der Bestand geändert hat. Neu gezeichnet wird erst in onUpdate.
function RevampObjectFillLevelSpecialization:setRevampObjectFillLevelDirty()
	local spec = self.spec_revampObjectFillLevel
	spec.isDirty = true
	-- Ohne das bekommt eine ruhende Placeable gar kein onUpdate mehr und die Änderung bliebe liegen.
	self:raiseActive()
end

---@param dt number Vergangene Zeit seit dem letzten Aufruf in Millisekunden
function RevampObjectFillLevelSpecialization:onUpdate(dt)
	local spec = self.spec_revampObjectFillLevel
	if not spec.isDirty then
		return
	end

	spec.lastUpdateTime = spec.lastUpdateTime + dt
	if spec.lastUpdateTime < RevampObjectFillLevelSpecialization.UPDATE_DELAY then
		self:raiseActive()
		return
	end

	self:updateRevampObjectFillLevels()

	spec.lastUpdateTime = 0
	spec.isDirty = false
end

---Setzt Sichtbarkeit und Kollision aller Objekte auf den aktuellen Bestand.
function RevampObjectFillLevelSpecialization:updateRevampObjectFillLevels()
	local spec = self.spec_revampObjectFillLevel

	for _, objectFillLevel in pairs(spec.objectFillLevels) do
		local fillLevel = 0
		for fillTypeIndex in pairs(objectFillLevel.fillTypes) do
			fillLevel = fillLevel + RevampObjectFillLevelSpecialization.getFillLevel(self, fillTypeIndex)
		end

		local visibleMaxIndex = 0
		if fillLevel >= objectFillLevel.firstAtFillLevel then
			visibleMaxIndex = 1
		end
		if fillLevel > objectFillLevel.firstAtFillLevel then
			visibleMaxIndex = visibleMaxIndex + math.floor((fillLevel - objectFillLevel.firstAtFillLevel) / objectFillLevel.fillLevelStep)
		end

		for index, object in ipairs(objectFillLevel.objects) do
			-- Umgedreht wird nur, welches Objekt als sichtbar gilt - die Reihenfolge bleibt dieselbe.
			local isShown = index <= visibleMaxIndex
			if objectFillLevel.invert then
				isShown = not isShown
			end

			setVisibility(object.node, isShown)
			for _, collisionNode in ipairs(object.collisionNodes) do
				setCollisionFilterMask(collisionNode.node, isShown and collisionNode.mask or RevampObjectFillLevelSpecialization.COLLISION_MASK_HIDDEN)
			end
		end
	end
end
