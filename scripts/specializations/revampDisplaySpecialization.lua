-- Zeigt den Bestand eines Fülltyps als Ziffernfolge am Gebäude an, wie eine LCD-Tafel an einem echten Silo.
-- Trotz des ähnlichen Namens etwas völlig anderes als die Objektdarstellung (revampObjectFillLevelSpecialization.lua): hier geht es um eine Zahl, dort um sichtbare Objekte.
--
-- Eine Spezialisierung für beide Placeable-Arten: die LS22-Fassung hatte dafür zwei nahezu identische Dateien (Silo und Produktionsstätte),
-- die sich nur in der Voraussetzungs-Prüfung, im XML-Pfad und in der Herkunft von Bestand und Kapazität unterschieden.
-- Der XML-Pfad ist deshalb jetzt für beide derselbe und hängt direkt unter <placeable>, statt unter <silo> bzw. <productionPoint>.
--
-- Die Ziffern selbst stehen nicht im Modell: das Schriftmaterial erzeugt sie zur Laufzeit unter dem angegebenen Knoten.
-- Im i3d braucht es deshalb nur eine leere TransformGroup an der Stelle, an der die Anzeige sitzen soll.

RevampDisplaySpecialization = {}

-- Wie bei der Objektdarstellung wird nicht bei jeder Bestandsänderung neu gezeichnet, sondern gesammelt.
-- Kürzer als dort, weil eine Zahl deutlich billiger zu aktualisieren ist als Sichtbarkeit und Kollision vieler Objekte.
RevampDisplaySpecialization.UPDATE_DELAY = 1000

-- Sichtweite der einzelnen Ziffern in Metern. Ohne das verschwindet die Anzeige schon aus wenigen Metern Entfernung, während das Gebäude selbst noch zu sehen ist.
RevampDisplaySpecialization.CHARACTER_CLIP_DISTANCE = 500

-- Bis zu diesem Wert gilt eine Farbumschlag-Grenze als Anteil der Kapazität statt als Literzahl - 0.5 meint also die Hälfte des Lagers.
-- Die krumme Obergrenze stammt aus der LS22-Fassung und bleibt so, damit bestehende Placeables ihre Grenzen unverändert behalten.
RevampDisplaySpecialization.COLOR_CHANGE_FACTOR_LIMIT = 1.1

---@param specializations table Spezialisierungen des Placeable-Typs
---@return boolean present true, wenn die Placeable ein Lager mitbringt, dessen Bestand angezeigt werden kann
function RevampDisplaySpecialization.prerequisitesPresent(specializations)
	return SpecializationUtil.hasSpecialization(PlaceableSilo, specializations)
		or SpecializationUtil.hasSpecialization(PlaceableProductionPoint, specializations)
end

---@param placeableType table Placeable-Typ, an dem die Spezialisierung hängt
function RevampDisplaySpecialization.registerEventListeners(placeableType)
	SpecializationUtil.registerEventListener(placeableType, "onLoad", RevampDisplaySpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", RevampDisplaySpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onPostFinalizePlacement", RevampDisplaySpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onUpdate", RevampDisplaySpecialization)
end

---@param placeableType table Placeable-Typ, an dem die Spezialisierung hängt
function RevampDisplaySpecialization.registerFunctions(placeableType)
	SpecializationUtil.registerFunction(placeableType, "updateRevampDisplays", RevampDisplaySpecialization.updateRevampDisplays)
	SpecializationUtil.registerFunction(placeableType, "setRevampDisplayDirty", RevampDisplaySpecialization.setRevampDisplayDirty)
end

---@param schema XMLSchema Schema der Placeable-XML
---@param basePath string Basis-Pfad des placeable-Knotens
function RevampDisplaySpecialization.registerXMLPaths(schema, basePath)
	schema:setXMLSpecializationType("RevampDisplay")

	schema:register(XMLValueType.NODE_INDEX, basePath .. ".revampDisplays.revampDisplay(?)#node", "Knoten, an dem die Ziffern erzeugt werden")
	schema:register(XMLValueType.STRING, basePath .. ".revampDisplays.revampDisplay(?)#fillType", "Fülltyp, dessen Bestand angezeigt wird")
	schema:register(XMLValueType.STRING, basePath .. ".revampDisplays.revampDisplay(?)#font", "Name des Schriftmaterials", "DIGIT")
	schema:register(XMLValueType.STRING, basePath .. ".revampDisplays.revampDisplay(?)#mask", "Stellenmuster der Anzeige, bestimmt Stellenzahl und Nachkommastellen", "000000")
	schema:register(XMLValueType.STRING, basePath .. ".revampDisplays.revampDisplay(?)#alignment", "Ausrichtung der Zahl (LEFT, CENTER, RIGHT)", "RIGHT")
	schema:register(XMLValueType.FLOAT, basePath .. ".revampDisplays.revampDisplay(?)#size", "Höhe der Ziffern in Metern", 0.13)
	schema:register(XMLValueType.FLOAT, basePath .. ".revampDisplays.revampDisplay(?)#scaleX", "Zusätzliche Breitenskalierung der Ziffern", 1)
	schema:register(XMLValueType.FLOAT, basePath .. ".revampDisplays.revampDisplay(?)#scaleY", "Zusätzliche Höhenskalierung der Ziffern", 1)
	schema:register(XMLValueType.FLOAT, basePath .. ".revampDisplays.revampDisplay(?)#emissiveScale", "Eigenleuchten der Ziffern", 0.2)
	schema:register(XMLValueType.COLOR, basePath .. ".revampDisplays.revampDisplay(?)#color", "Farbe der Ziffern")
	schema:register(XMLValueType.COLOR, basePath .. ".revampDisplays.revampDisplay(?)#hiddenColor", "Farbe der nicht benutzten Stellen, für Anzeigen im Stil einer echten Sieben-Segment-Tafel")
	schema:register(XMLValueType.BOOL, basePath .. ".revampDisplays.revampDisplay(?)#reverse", "Zeigt statt des Bestands den Rest bis zu 'reverseAmount' an", false)
	schema:register(XMLValueType.INT, basePath .. ".revampDisplays.revampDisplay(?)#reverseAmount", "Wert, von dem bei 'reverse' heruntergezählt wird")
	schema:register(XMLValueType.COLOR, basePath .. ".revampDisplays.revampDisplay(?).colorChange(?)#color", "Farbe ab dieser Grenze")
	schema:register(XMLValueType.FLOAT, basePath .. ".revampDisplays.revampDisplay(?).colorChange(?)#amount", "Grenze, ab der die Farbe gilt - als Literzahl oder als Anteil der Kapazität", 1)

	schema:setXMLSpecializationType()
end

---Liefert die Lager, aus denen sich der angezeigte Bestand ergibt.
---Beim Silo bewusst über die Lager selbst und nicht über die Verladestation: die nimmt ein Lager nur auf, wenn dessen Fülltypen zu einem ihrer Ladepunkte passen -
---ein Silo ohne Verladestelle hätte dort gar keine Lager stehen, obwohl welche da sind.
---@param placeable table Placeable-Instanz
---@return table storages Liste der Lager
function RevampDisplaySpecialization.getStorages(placeable)
	if placeable.spec_silo ~= nil then
		return Revamp.getSiloStorages(placeable)
	end

	return {placeable.spec_productionPoint.productionPoint.storage}
end

---Liefert den Bestand eines Fülltyps über alle Lager der Placeable.
---@param placeable table Placeable-Instanz
---@param fillTypeIndex number FillType-Index
---@return number fillLevel Bestand in Litern
function RevampDisplaySpecialization.getFillLevel(placeable, fillTypeIndex)
	local fillLevel = 0
	for _, storage in ipairs(RevampDisplaySpecialization.getStorages(placeable)) do
		fillLevel = fillLevel + storage:getFillLevel(fillTypeIndex)
	end

	return fillLevel
end

---Liefert die Kapazität eines Fülltyps über alle Lager der Placeable.
---Die LS22-Fassung überschrieb den Wert hier in jedem Schleifendurchlauf und behielt am Ende den des zuletzt durchlaufenen Lagers, auch wenn dieses den angezeigten Fülltyp gar nicht führt.
---@param placeable table Placeable-Instanz
---@param fillTypeIndex number FillType-Index
---@return number capacity Kapazität in Litern
function RevampDisplaySpecialization.getCapacity(placeable, fillTypeIndex)
	local capacity = 0
	for _, storage in ipairs(RevampDisplaySpecialization.getStorages(placeable)) do
		-- Nur Lager, die diesen Fülltyp überhaupt führen: getCapacity liefert sonst den gemeinsamen Topf eines Lagers, das damit gar nichts zu tun hat.
		if storage:getIsFillTypeSupported(fillTypeIndex) then
			capacity = capacity + storage:getCapacity(fillTypeIndex)
		end
	end

	return capacity
end

---Liest die Farbumschlag-Grenzen einer Anzeige.
---@param xmlFile table XMLFile der Placeable
---@param key string XML-Pfad des revampDisplay-Knotens
---@param baseColor table Grundfarbe der Anzeige, gilt unterhalb der ersten Grenze
---@return table|nil colorChanges Grenzen aufsteigend, nil wenn die Anzeige keine Farbumschläge hat
function RevampDisplaySpecialization.loadColorChanges(xmlFile, key, baseColor)
	if not xmlFile:hasProperty(key .. ".colorChange") then
		return nil
	end

	-- Die Grundfarbe steht als Grenze 0 mit in der Liste, damit die Auswahl unten keinen Sonderfall für "noch unterhalb der ersten Grenze" braucht.
	local colorChanges = {{amount = 0, isFactor = false, color = baseColor}}

	xmlFile:iterate(key .. ".colorChange", function(_, colorKey)
		local amount = xmlFile:getValue(colorKey .. "#amount", 1)
		table.insert(colorChanges, {
			amount = amount,
			isFactor = amount < RevampDisplaySpecialization.COLOR_CHANGE_FACTOR_LIMIT,
			color = xmlFile:getValue(colorKey .. "#color", {0.6662, 0.3839, 0.5481, 1}, true)
		})
	end)

	return colorChanges
end

---@param savegame? table Spielstanddaten, nil bei einer neu gebauten Placeable
function RevampDisplaySpecialization:onLoad(savegame) ---@diagnostic disable-line: unused-local
	self.spec_revampDisplay = {}
	local spec = self.spec_revampDisplay
	local xmlFile = self.xmlFile

	spec.displays = {}
	spec.isDirty = true
	spec.lastUpdateTime = 0

	xmlFile:iterate("placeable.revampDisplays.revampDisplay", function(_, key)
		local displayNode = xmlFile:getValue(key .. "#node", nil, self.components, self.i3dMappings)
		if displayNode == nil then
			Logging.xmlError(xmlFile, "Production Revamp: '%s' has no valid node, display is skipped", key)
			return
		end

		local fillTypeName = xmlFile:getValue(key .. "#fillType")
		local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
		if fillTypeIndex == nil then
			Logging.xmlError(xmlFile, "Production Revamp: '%s' has unknown fillType '%s', display is skipped", key, tostring(fillTypeName))
			return
		end

		local fontName = xmlFile:getValue(key .. "#font", "DIGIT"):upper()
		local fontMaterial = g_materialManager:getFontMaterial(fontName, self.customEnvironment)
		if fontMaterial == nil then
			Logging.xmlWarning(xmlFile, "Production Revamp: '%s' has unknown font '%s', using 'DIGIT' instead", key, fontName)
			fontMaterial = g_materialManager:getFontMaterial("DIGIT", self.customEnvironment)
		end

		local display = {}
		display.fillTypeIndex = fillTypeIndex

		display.reverse = xmlFile:getValue(key .. "#reverse", false)
		display.reverseAmount = xmlFile:getValue(key .. "#reverseAmount")
		if display.reverse and (display.reverseAmount == nil or display.reverseAmount <= 0) then
			Logging.xmlWarning(xmlFile, "Production Revamp: '%s' needs a positive 'reverseAmount' to count down from, counting up instead", key)
			display.reverse = false
		end

		local mask = xmlFile:getValue(key .. "#mask", "000000")
		display.formatStr, display.formatPrecision = Utils.maskToFormat(mask)

		local color = xmlFile:getValue(key .. "#color", {0.9, 0.9, 0.9, 1}, true)
		display.colorChanges = RevampDisplaySpecialization.loadColorChanges(xmlFile, key, color)

		-- Die Ziffern hängen als eigene Shapes unter dem Anzeigeknoten und werden vom Schriftmaterial erzeugt, im Modell steht dafür nur der leere Knoten.
		local alignmentName = xmlFile:getValue(key .. "#alignment", "RIGHT"):upper()
		display.characterLine = CharacterLine.new(displayNode, fontMaterial, mask:len())
		display.characterLine:setSizeAndScale(xmlFile:getValue(key .. "#size", 0.13), xmlFile:getValue(key .. "#scaleX", 1), xmlFile:getValue(key .. "#scaleY", 1))
		display.characterLine:setTextAlignment(RenderText["ALIGN_" .. alignmentName] or RenderText.ALIGN_RIGHT)
		display.characterLine:setColor(color, xmlFile:getValue(key .. "#hiddenColor", nil, true), xmlFile:getValue(key .. "#emissiveScale", 0.2))
		display.currentColor = color

		for _, characterNode in ipairs(display.characterLine.characters) do
			setClipDistance(characterNode, RevampDisplaySpecialization.CHARACTER_CLIP_DISTANCE)
		end

		table.insert(spec.displays, display)
	end)

	function spec.fillLevelChangedCallback(fillType, delta) ---@diagnostic disable-line: unused-local
		self:setRevampDisplayDirty()
	end
end

---@param savegame? table Spielstanddaten, nil bei einer neu gebauten Placeable
function RevampDisplaySpecialization:onFinalizePlacement(savegame) ---@diagnostic disable-line: unused-local
	local spec = self.spec_revampDisplay

	for _, storage in pairs(RevampDisplaySpecialization.getStorages(self)) do
		storage:addFillLevelChangedListeners(spec.fillLevelChangedCallback)
	end
end

---@param savegame? table Spielstanddaten, nil bei einer neu gebauten Placeable
function RevampDisplaySpecialization:onPostFinalizePlacement(savegame) ---@diagnostic disable-line: unused-local
	self:updateRevampDisplays()
end

---Merkt vor, dass sich der Bestand geändert hat. Neu gezeichnet wird erst in onUpdate.
function RevampDisplaySpecialization:setRevampDisplayDirty()
	local spec = self.spec_revampDisplay
	spec.isDirty = true
	-- Ohne das bekommt eine ruhende Placeable gar kein onUpdate mehr und die Änderung bliebe liegen.
	self:raiseActive()
end

---@param dt number Vergangene Zeit seit dem letzten Aufruf in Millisekunden
function RevampDisplaySpecialization:onUpdate(dt)
	local spec = self.spec_revampDisplay
	if not spec.isDirty then
		return
	end

	spec.lastUpdateTime = spec.lastUpdateTime + dt
	if spec.lastUpdateTime < RevampDisplaySpecialization.UPDATE_DELAY then
		self:raiseActive()
		return
	end

	self:updateRevampDisplays()

	spec.lastUpdateTime = 0
	spec.isDirty = false
end

---Sucht die Farbe, die zum angezeigten Wert gehört: die der höchsten Grenze, die er erreicht.
---@param placeable table Placeable-Instanz
---@param display table Anzeige aus spec.displays
---@param value number Angezeigter Wert
---@return table color Farbe als {r, g, b, a}
function RevampDisplaySpecialization.getColorForValue(placeable, display, value)
	-- Erst hier statt beim Laden umgerechnet: die Kapazität steht beim Laden noch nicht fest (die Farm ist noch nicht gesetzt) und kann sich im Spiel ändern.
	local capacity = RevampDisplaySpecialization.getCapacity(placeable, display.fillTypeIndex)
	local color = display.colorChanges[1].color
	local highestAmount = -1

	for _, colorChange in ipairs(display.colorChanges) do
		local amount = colorChange.isFactor and capacity * colorChange.amount or colorChange.amount
		if amount <= value and amount > highestAmount then
			color = colorChange.color
			highestAmount = amount
		end
	end

	return color
end

---Schreibt den aktuellen Bestand auf alle Anzeigen.
function RevampDisplaySpecialization:updateRevampDisplays()
	local spec = self.spec_revampDisplay

	for _, display in pairs(spec.displays) do
		local value = RevampDisplaySpecialization.getFillLevel(self, display.fillTypeIndex)
		if display.reverse then
			value = math.max(display.reverseAmount - value, 0)
		end

		local integerPart, fractionPart = math.modf(value)
		display.characterLine:setText(string.format(display.formatStr, integerPart, math.abs(math.floor(fractionPart * 10 ^ display.formatPrecision))))

		if display.colorChanges ~= nil then
			local color = RevampDisplaySpecialization.getColorForValue(self, display, value)
			-- Nur bei einem tatsächlichen Wechsel: setColor geht über jede einzelne Ziffer und wäre sonst bei jeder Aktualisierung umsonst gemacht.
			if color ~= display.currentColor then
				display.characterLine:setColor(color)
				display.currentColor = color
			end
		end
	end
end
