--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- Einstellungen, die eine einzelne Rezeptlinie betreffen und die der Spieler im Spielstand ändern darf, statt sie hinnehmen zu müssen wie der Modder sie in der XML vorgegeben hat.
-- Die XML-Werte sind damit nur noch der Startwert einer neu gebauten Produktionsstätte.
--
-- Aktuell sind das der Mix-Modus (welche Zutat einer Mix-Gruppe verbraucht wird) und der Booster-Modus (welcher Booster zählt).
-- Beides ist bewusst nur dort umschaltbar, wo es überhaupt eine Wahl gibt - eine Mix-Gruppe mit nur einer Zutat oder eine Linie ohne Booster-Auswahl hat nichts zu entscheiden.
--
-- Anzeige und Bedienung stehen im Verwalten-Dialog (revamp_manageDialog.lua), die eigentliche Auswertung der Modi in revamp_production.lua.

Revamp.SELECTION_MODES = {"ASC", "DESC", "MOST", "LEAST"}

---Liefert den nächsten Auswahlmodus in der Reihenfolge ASC, DESC, MOST, LEAST und danach wieder von vorn.
---@param mode string Aktueller Modus
---@return string nextMode Nächster Modus
function Revamp.getNextSelectionMode(mode)
	for index, name in ipairs(Revamp.SELECTION_MODES) do
		if name == mode then
			return Revamp.SELECTION_MODES[index % #Revamp.SELECTION_MODES + 1]
		end
	end
	return Revamp.SELECTION_MODES[1]
end

---Prüft, ob ein Wert ein gültiger Auswahlmodus ist.
---@param mode string Zu prüfender Wert
---@return boolean isMode true, wenn der Wert einer der Auswahlmodi ist
function Revamp.isSelectionMode(mode)
	for _, name in ipairs(Revamp.SELECTION_MODES) do
		if name == mode then
			return true
		end
	end
	return false
end

---Liefert den lokalisierten Namen eines Auswahlmodus.
---Mix- und Booster-Modus bekommen eigene Texte: derselbe Modus bedeutet zwar dasselbe Prinzip, beschreibt aber einmal eine Zutat und einmal einen Booster.
---@param mode string Modus (ASC/DESC/MOST/LEAST)
---@param isBoost boolean true für den Booster-Modus, false für den Mix-Modus
---@return string text Lokalisierter Name
function Revamp.getSelectionModeText(mode, isBoost)
	local prefix = isBoost and "revamp_boostMode_" or "revamp_mixMode_"
	return g_i18n:getText(prefix .. mode)
end

---Bestimmt für eine Rezeptlinie, ob Mix- bzw. Booster-Modus überhaupt etwas bewirken.
---Ohne diese Prüfung böte der Verwalten-Dialog Umschalter an, die nichts ändern - der Spieler würde einen Effekt suchen, den es bei dieser Linie gar nicht gibt.
---@param production table Rezeptlinie aus productionsIdToObj
function Revamp.updateRecipeChoiceFlags(production)
	-- Der Mix-Modus entscheidet zwischen den Zutaten einer Gruppe, eine Gruppe mit nur einem Mitglied hat also nichts zu entscheiden.
	local mixGroupSizes = {}
	local numBoosters = 0
	for _, input in ipairs(production.inputs) do
		if input.mix == Revamp.MIX_BOOST then
			numBoosters = numBoosters + 1
		elseif input.mix ~= 0 and input.mix ~= Revamp.MIX_MASTER then
			mixGroupSizes[input.mix] = (mixGroupSizes[input.mix] or 0) + 1
		end
	end

	production.hasMixChoice = false
	for _, size in pairs(mixGroupSizes) do
		if size > 1 then
			production.hasMixChoice = true
			break
		end
	end

	-- Der Booster-Modus greift an zwei Stellen: beim Master-Booster (dort gewinnt immer genau einer) und mit limitBoosters, wo von mehreren gewöhnlichen Boostern nur einer zählt.
	production.hasBoostChoice = production.master or (production.limitBoosters and numBoosters > 1)

	Revamp.DebugText("updateRecipeChoiceFlags(): %s hasMixChoice=%s hasBoostChoice=%s", production.id, tostring(production.hasMixChoice), tostring(production.hasBoostChoice))
end

---Setzt Mix- und/oder Booster-Modus einer Rezeptlinie und verteilt die Änderung im Mehrspieler.
---@param productionId string Id der Rezeptlinie
---@param mixMode? string Neuer Mix-Modus, nil lässt den bisherigen stehen
---@param boostMode? string Neuer Booster-Modus, nil lässt den bisherigen stehen
---@param noEventSend? boolean true, wenn die Änderung selbst schon aus einem Event stammt und nicht erneut verschickt werden darf
function ProductionPoint:setRecipeSelectionModes(productionId, mixMode, boostMode, noEventSend)
	local production = self.productionsIdToObj[productionId]
	if production == nil then
		return
	end

	-- Unbekannte Werte werden verworfen statt übernommen: sie können aus einem von Hand bearbeiteten Spielstand kommen und würden sich später als stillschweigend anderes Auswahlverhalten zeigen.
	-- Verworfen wird vor dem Verschicken, damit auf allen Rechnern derselbe Wert steht.
	if mixMode ~= nil and not Revamp.isSelectionMode(mixMode) then
		mixMode = nil
	end
	if boostMode ~= nil and not Revamp.isSelectionMode(boostMode) then
		boostMode = nil
	end

	if mixMode ~= nil then
		production.mixMode = mixMode
	end
	if boostMode ~= nil then
		production.boostMode = boostMode
	end

	Revamp.DebugText("setRecipeSelectionModes(): %s mixMode=%s boostMode=%s", productionId, production.mixMode, production.boostMode)

	Revamp_EventRecipeSettings.sendEvent(self, productionId, mixMode, boostMode, noEventSend)
end

---Registriert das Savegame-XML-Schema für die vom Spieler geänderten Auswahlmodi.
---Bewusst ein eigener Knoten statt der vorhandenen production(?)-Einträge: die schreibt Vanilla selbst mit eigenem Index nur für aktive Linien und würde fremde Einträge darin überschreiben.
---@param schema XMLSchema Schema, in das die neuen Pfade eingetragen werden
---@param basePath string XML-Basispfad des ProductionPoint-Elements
function Revamp.registerRecipeSettingsSavegameXMLPaths(schema, basePath)
	schema:register(XMLValueType.STRING, basePath .. ".recipeSetting(?)#id", "Id der Rezeptlinie")
	schema:register(XMLValueType.STRING, basePath .. ".recipeSetting(?)#mixMode", "Vom Spieler gewählter Mix-Modus")
	schema:register(XMLValueType.STRING, basePath .. ".recipeSetting(?)#boostMode", "Vom Spieler gewählter Booster-Modus")
end

ProductionPoint.registerSavegameXMLPaths = Utils.prependedFunction(ProductionPoint.registerSavegameXMLPaths, Revamp.registerRecipeSettingsSavegameXMLPaths)

---Speichert die Auswahlmodi aller Rezeptlinien eines Produktionspunkts ins Savegame.
---Geschrieben wird nur, wo es auch etwas zu wählen gibt - sonst stünde in jedem Spielstand für jede Linie ein Eintrag, der nur den XML-Wert wiederholt.
---@param self table ProductionPoint-Instanz
---@param xmlFile table XMLFile, in das geschrieben wird
---@param key string XML-Basispfad des ProductionPoint-Elements
---@param usedModNames table Von Vanilla durchgereichte Liste verwendeter Mod-Namen
function Revamp.saveRecipeSettingsToXMLFile(self, xmlFile, key, usedModNames) ---@diagnostic disable-line: unused-local
	local xmlIndex = 0
	for _, production in ipairs(self.productions) do
		if production.hasMixChoice or production.hasBoostChoice then
			local settingKey = string.format("%s.recipeSetting(%d)", key, xmlIndex)
			xmlFile:setValue(settingKey .. "#id", production.id)
			xmlFile:setValue(settingKey .. "#mixMode", production.mixMode)
			xmlFile:setValue(settingKey .. "#boostMode", production.boostMode)
			xmlIndex = xmlIndex + 1
		end
	end
end

ProductionPoint.saveToXMLFile = Utils.prependedFunction(ProductionPoint.saveToXMLFile, Revamp.saveRecipeSettingsToXMLFile)

---Liest die im Savegame gespeicherten Auswahlmodi und wendet sie an.
---@param self table ProductionPoint-Instanz
---@param superFunc function Ursprüngliches ProductionPoint.loadFromXMLFile
---@param xmlFile table XMLFile des Savegames
---@param key string XML-Basispfad des ProductionPoint-Elements
---@return boolean success true, wenn das ursprüngliche Laden erfolgreich war
function Revamp.loadRecipeSettingsFromXMLFile(self, superFunc, xmlFile, key)
	local success = superFunc(self, xmlFile, key)

	xmlFile:iterate(key .. ".recipeSetting", function(_, settingKey)
		local productionId = xmlFile:getValue(settingKey .. "#id")
		if self.productionsIdToObj[productionId] == nil then
			-- Kein harter Fehler: die Rezeptlinie kann seit dem letzten Speichern aus der Placeable-XML verschwunden sein, der Rest des Punktes lädt trotzdem normal weiter.
			Logging.xmlWarning(xmlFile, "Production Revamp: unknown production id '%s'", tostring(productionId))
			return
		end

		self:setRecipeSelectionModes(productionId, xmlFile:getValue(settingKey .. "#mixMode"), xmlFile:getValue(settingKey .. "#boostMode"), true)
	end)

	return success
end

ProductionPoint.loadFromXMLFile = Utils.overwrittenFunction(ProductionPoint.loadFromXMLFile, Revamp.loadRecipeSettingsFromXMLFile)

---Sendet die Auswahlmodi aller Rezeptlinien beim Erstverbinden an einen Client (MP-Sync).
---Ohne das sähe ein beitretender Client die Werte aus der Placeable-XML statt der im Spielstand tatsächlich eingestellten.
---@param self table ProductionPoint-Instanz
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp.writeRecipeSettingsStream(self, streamId, connection)
	if not connection:getIsServer() then
		for _, production in ipairs(self.productions) do
			streamWriteUInt8(streamId, Revamp.getSelectionModeIndex(production.mixMode))
			streamWriteUInt8(streamId, Revamp.getSelectionModeIndex(production.boostMode))
		end
	end
end

ProductionPoint.writeStream = Utils.prependedFunction(ProductionPoint.writeStream, Revamp.writeRecipeSettingsStream)

---Empfängt die Auswahlmodi aller Rezeptlinien vom Server (MP-Sync).
---Die Rezeptlinien selbst kommen aus derselben Placeable-XML wie beim Server, gesendet wird deshalb nur der Modus je Linie in genau dieser Reihenfolge - eine Id je Eintrag wäre reiner Ballast.
---@param self table ProductionPoint-Instanz
---@param streamId number Stream-Handle
---@param connection table Netzwerkverbindung
function Revamp.readRecipeSettingsStream(self, streamId, connection)
	if connection:getIsServer() then
		for _, production in ipairs(self.productions) do
			production.mixMode = Revamp.SELECTION_MODES[streamReadUInt8(streamId)]
			production.boostMode = Revamp.SELECTION_MODES[streamReadUInt8(streamId)]
		end
	end
end

ProductionPoint.readStream = Utils.prependedFunction(ProductionPoint.readStream, Revamp.readRecipeSettingsStream)

---Liefert die Nummer eines Auswahlmodus für den Netzwerk-Stream.
---@param mode string Modus (ASC/DESC/MOST/LEAST)
---@return number index Nummer des Modus, 1 (ASC) für einen unbekannten Wert
function Revamp.getSelectionModeIndex(mode)
	for index, name in ipairs(Revamp.SELECTION_MODES) do
		if name == mode then
			return index
		end
	end
	return 1
end
