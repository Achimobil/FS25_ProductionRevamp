-- Globale Einstellungen des Mods: Werte, die für den ganzen Spielstand gelten und die ein Admin im Einstellungsmenü des Spiels umstellt.
-- Sie gehören zum Spielstand und nicht zum einzelnen Spieler und liegen deshalb als eigene revamp.xml im Spielstandordner.
--
-- Die Bedienelemente sind Klone der Vanilla-Zeilen aus dem Spiel-Einstellungsbereich: deren Aussehen steckt in Profilen, die ein Mod nicht zuverlässig nachbaut, ein Klon übernimmt es dagegen vollständig.
-- Geklont wird immer die ganze Zeile und nicht nur das Bedienelement - im LS25 sitzen Bedienelement, Beschriftung und Hilfetext gemeinsam in einem Container, der die Zeile bildet.
-- Vanilla blendet diesen Bereich im Mehrspieler für Spieler ohne Adminrechte komplett aus, die Einstellungen sind damit ohne eigenes Zutun vor fremdem Zugriff geschützt.

Revamp.SETTING_TYPE = {
	BOOL = 1,
	CHOICE = 2,
	FACTOR = 3
}

-- Ein Faktor wird als Auswahl in Zehnerschritten von 0 bis 200 Prozent bedient statt als Zahleneingabe: das lässt sich auch mit Gamepad bedienen, kann keine unsinnigen Werte annehmen und sieht aus wie die übrigen Einstellungen.
-- Die Anzahl der Schritte steht bewusst als eigener Wert da, statt sie aus Höchstwert und Schrittweite zu rechnen: 2 / 0,1 ergibt als Kommazahl knapp unter 20 und würde den letzten Schritt verschlucken.
Revamp.FACTOR_STEP = 0.1
Revamp.FACTOR_STEP_COUNT = 20
Revamp.FACTOR_MAX = 2

-- Wer an einer Produktionsstätte kaufen und verkaufen darf.
Revamp.TRADE_RESTRICTIONS = {"everyone", "farmManager", "productionAgent"}

-- Reihenfolge im Menü, jeder Schalter direkt vor den Einstellungen, die zu ihm gehören. "default" ist der Wert, mit dem ein neuer Spielstand startet.
-- Ein abgeschalteter Bereich verschwindet auch aus der Bedienung und wird nicht nur wirkungslos: was es nicht gibt, soll man auch nicht anklicken können.
-- Was der Spieler dazu schon eingestellt hatte (Verteilziele, eingelagerte Waren, Auswahlmodi), bleibt dabei gespeichert und gilt beim Wiedereinschalten unverändert weiter.
Revamp.SETTINGS = {
	{id = "distributionActive",       settingType = Revamp.SETTING_TYPE.BOOL,   default = true},
	{id = "distributionCostFactor",   settingType = Revamp.SETTING_TYPE.FACTOR, default = 1},
	{id = "storageActive",            settingType = Revamp.SETTING_TYPE.BOOL,   default = true},
	{id = "buyingActive",             settingType = Revamp.SETTING_TYPE.BOOL,   default = true},
	{id = "sellingActive",            settingType = Revamp.SETTING_TYPE.BOOL,   default = true},
	{id = "tradeRestriction",         settingType = Revamp.SETTING_TYPE.CHOICE, default = "productionAgent", values = Revamp.TRADE_RESTRICTIONS},
	{id = "directSellingPriceFactor", settingType = Revamp.SETTING_TYPE.FACTOR, default = 0.9},
	{id = "weatherModesActive",       settingType = Revamp.SETTING_TYPE.BOOL,   default = true},
	{id = "recipeSettingsActive",     settingType = Revamp.SETTING_TYPE.BOOL,   default = true}
}

-- Anzeigen, die jeder Spieler für sich ein- und ausschaltet: sie ändern nichts am Spielgeschehen und gehören deshalb weder in den Spielstand noch über das Netz, sondern in die Profildateien des Spielers.
Revamp.DISPLAY_SETTINGS = {
	{id = "showSharedIcon",          settingType = Revamp.SETTING_TYPE.BOOL, default = true},
	{id = "showBuildingCosts",       settingType = Revamp.SETTING_TYPE.BOOL, default = true},
	{id = "showDistributionTargets", settingType = Revamp.SETTING_TYPE.BOOL, default = true}
}

-- Den Sammelordner für Mod-Einstellungen legt das Spiel beim Start selbst an, allerdings nur auf dem PC - daher der Ersatzpfad.
Revamp.MOD_SETTINGS_DIRECTORY = g_modSettingsDirectory or (getUserProfileAppPath() .. "modSettings/")

-- Der eigene Ordnername steht bewusst fest und kommt nicht aus dem Modnamen: eine umbenannte Mod-Datei (z.B. mit einem Präfix für die Ladereihenfolge) soll die Einstellungen des Spielers nicht verlieren.
Revamp.DISPLAY_SETTINGS_DIRECTORY = Revamp.MOD_SETTINGS_DIRECTORY .. "FS25_ProductionRevamp"
Revamp.DISPLAY_SETTINGS_PATH = Revamp.DISPLAY_SETTINGS_DIRECTORY .. "/settings.xml"

-- Die aktuellen Anzeige-Einstellungen dieses Spielers, Schlüssel ist die Id der Einstellung.
Revamp.displaySettings = {}

-- Die aktuellen Werte, Schlüssel ist die Id der Einstellung. Zum Ändern immer Revamp.setSetting benutzen, sonst fehlt die Prüfung des Wertes.
Revamp.settings = {}

-- Zugriff auf eine Definition über ihre Id, statt jedes Mal durch die Listen oben zu laufen.
Revamp.settingsById = {}
Revamp.displaySettingsById = {}

---Legt die Nachschlagetabellen an und setzt alle Einstellungen auf ihren Startwert.
function Revamp.initSettings()
	for _, definition in ipairs(Revamp.SETTINGS) do
		Revamp.settingsById[definition.id] = definition
		Revamp.settings[definition.id] = definition.default
	end

	for _, definition in ipairs(Revamp.DISPLAY_SETTINGS) do
		Revamp.displaySettingsById[definition.id] = definition
		Revamp.displaySettings[definition.id] = definition.default
	end
end

---Liest die Anzeige-Einstellungen dieses Spielers aus seinen Profildateien.
function Revamp.loadDisplaySettings()
	if not fileExists(Revamp.DISPLAY_SETTINGS_PATH) then
		return
	end

	local xmlFile = XMLFile.load("revampDisplaySettingsXML", Revamp.DISPLAY_SETTINGS_PATH)
	if xmlFile == nil then
		return
	end

	for _, definition in ipairs(Revamp.DISPLAY_SETTINGS) do
		local value = xmlFile:getBool("revamp.display#" .. definition.id)
		if value ~= nil then
			Revamp.displaySettings[definition.id] = value
		end
	end

	xmlFile:delete()
end

---Schreibt die Anzeige-Einstellungen dieses Spielers in seine Profildateien.
function Revamp.saveDisplaySettings()
	createFolder(Revamp.MOD_SETTINGS_DIRECTORY)
	createFolder(Revamp.DISPLAY_SETTINGS_DIRECTORY)

	local xmlFile = XMLFile.create("revampDisplaySettingsXML", Revamp.DISPLAY_SETTINGS_PATH, "revamp")
	if xmlFile == nil then
		return
	end

	for _, definition in ipairs(Revamp.DISPLAY_SETTINGS) do
		xmlFile:setBool("revamp.display#" .. definition.id, Revamp.displaySettings[definition.id])
	end

	xmlFile:save()
	xmlFile:delete()
end

---Prüft einen Wert gegen seine Definition und liefert ersatzweise den Startwert.
---Ohne diese Prüfung würde ein fehlender oder beschädigter Wert aus dem Spielstand als nil übernommen und die Einstellung damit unbrauchbar.
---@param definition table Eintrag aus Revamp.SETTINGS
---@param value any Zu prüfender Wert
---@return any value Gültiger Wert der Einstellung
function Revamp.getValidSettingValue(definition, value)
	if definition.settingType == Revamp.SETTING_TYPE.BOOL then
		if type(value) ~= "boolean" then
			return definition.default
		end
		return value
	end

	if definition.settingType == Revamp.SETTING_TYPE.CHOICE then
		for _, name in ipairs(definition.values) do
			if name == value then
				return value
			end
		end
		return definition.default
	end

	if type(value) ~= "number" then
		return definition.default
	end
	return math.min(math.max(value, 0), Revamp.FACTOR_MAX)
end

---Setzt eine Einstellung auf einen neuen Wert.
---@param id string Id der Einstellung
---@param value any Neuer Wert
function Revamp.setSetting(id, value)
	local definition = Revamp.settingsById[id]
	if definition == nil then
		return
	end

	Revamp.settings[id] = Revamp.getValidSettingValue(definition, value)
	Revamp.DebugText("setSetting(): %s = %s", id, tostring(Revamp.settings[id]))
end

---Speichert die Einstellungen des Spielstands.
---@param missionInfo table FSCareerMissionInfo-Instanz des laufenden Spielstands
function Revamp.saveSettings(missionInfo)
	if missionInfo == nil or missionInfo.savegameDirectory == nil then
		return
	end

	local xmlFile = XMLFile.create("revampSettingsXML", missionInfo.savegameDirectory .. "/revamp.xml", "revamp")
	if xmlFile == nil then
		return
	end

	for _, definition in ipairs(Revamp.SETTINGS) do
		local key = "revamp.settings#" .. definition.id
		if definition.settingType == Revamp.SETTING_TYPE.BOOL then
			xmlFile:setBool(key, Revamp.settings[definition.id])
		elseif definition.settingType == Revamp.SETTING_TYPE.CHOICE then
			xmlFile:setString(key, Revamp.settings[definition.id])
		else
			xmlFile:setFloat(key, Revamp.settings[definition.id])
		end
	end

	xmlFile:save()
	xmlFile:delete()
	Revamp.DebugText("saveSettings(): gespeichert in %s", missionInfo.savegameDirectory .. "/revamp.xml")
end

---Lädt die Einstellungen des Spielstands, sobald die Karte fertig geladen ist.
---Ein Client bekommt sie stattdessen vom Server, hier wird deshalb nur serverseitig gelesen.
---@param mission table Mission00-Instanz
function Revamp.loadSettings(mission)
	if not mission:getIsServer() or mission.missionInfo.savegameDirectory == nil then
		return
	end

	local path = mission.missionInfo.savegameDirectory .. "/revamp.xml"
	if not fileExists(path) then
		return
	end

	local xmlFile = XMLFile.load("revampSettingsXML", path)
	if xmlFile == nil then
		return
	end

	for _, definition in ipairs(Revamp.SETTINGS) do
		local key = "revamp.settings#" .. definition.id
		if definition.settingType == Revamp.SETTING_TYPE.BOOL then
			Revamp.setSetting(definition.id, xmlFile:getBool(key))
		elseif definition.settingType == Revamp.SETTING_TYPE.CHOICE then
			Revamp.setSetting(definition.id, xmlFile:getString(key))
		else
			Revamp.setSetting(definition.id, xmlFile:getFloat(key))
		end
	end

	xmlFile:delete()
end

---Rechnet den Wert einer Einstellung in den Zustand ihres Bedienelements um.
---@param definition table Eintrag aus Revamp.SETTINGS
---@param value any Wert der Einstellung
---@return number state Zustand des Bedienelements, beginnend bei 1
function Revamp.getSettingState(definition, value)
	if definition.settingType == Revamp.SETTING_TYPE.BOOL then
		return value and BinaryOptionElement.STATE_RIGHT or BinaryOptionElement.STATE_LEFT
	end

	if definition.settingType == Revamp.SETTING_TYPE.CHOICE then
		for index, name in ipairs(definition.values) do
			if name == value then
				return index
			end
		end
		return 1
	end

	return math.floor(value / Revamp.FACTOR_STEP + 0.5) + 1
end

---Rechnet den Zustand eines Bedienelements in den Wert der Einstellung um.
---@param definition table Eintrag aus Revamp.SETTINGS
---@param state number Zustand des Bedienelements, beginnend bei 1
---@return any value Wert der Einstellung
function Revamp.getSettingValueFromState(definition, state)
	if definition.settingType == Revamp.SETTING_TYPE.BOOL then
		return state == BinaryOptionElement.STATE_RIGHT
	end

	if definition.settingType == Revamp.SETTING_TYPE.CHOICE then
		return definition.values[state]
	end

	return (state - 1) * Revamp.FACTOR_STEP
end

---Liefert die Beschriftungen aller Zustände eines Bedienelements.
---@param definition table Eintrag aus Revamp.SETTINGS
---@return table texts Beschriftungen in der Reihenfolge der Zustände
function Revamp.getSettingTexts(definition)
	local texts = {}

	if definition.settingType == Revamp.SETTING_TYPE.CHOICE then
		for _, name in ipairs(definition.values) do
			table.insert(texts, g_i18n:getText("revamp_setting_" .. definition.id .. "_" .. name))
		end
		return texts
	end

	for step = 0, Revamp.FACTOR_STEP_COUNT do
		table.insert(texts, string.format("%d %%", math.floor(step * Revamp.FACTOR_STEP * 100 + 0.5)))
	end
	return texts
end

---Hängt eine Zwischenüberschrift an eine Einstellungsliste an.
---@param layout table Einstellungsliste, an die angehängt wird
---@param text string Überschrift
function Revamp.addSettingsSectionHeader(layout, text)
	local header = TextElement.new()
	header:applyProfile("fs25_settingsSectionHeader")
	-- Vanilla erkennt eine Zwischenüberschrift an diesem Namen und beginnt danach mit dem Wechsel der Zeilenfarben wieder von vorne.
	header.name = "sectionHeader"
	header:setText(text)
	layout:addElement(header)
end

---Hängt die Zeile einer Einstellung an eine Einstellungsliste an.
---@param frame table InGameMenuSettingsFrame-Instanz
---@param layout table Einstellungsliste, an die angehängt wird
---@param definition table Eintrag aus Revamp.SETTINGS oder Revamp.DISPLAY_SETTINGS
---@param callback function Wird beim Umstellen aufgerufen
---@return table optionElement Das Bedienelement der neuen Zeile
function Revamp.addSettingElement(frame, layout, definition, callback)
	-- Vanillas Verkehr ist die Vorlage für jeden Schalter, seine Wirtschaftsschwierigkeit die für jede Auswahl: beide ohne Sonderverhalten, das mitgeklont würde.
	local template = frame.economicDifficulty
	if definition.settingType == Revamp.SETTING_TYPE.BOOL then
		template = frame.checkTraffic
	end

	local container = template.parent:clone(layout)
	local optionElement = container.elements[1]

	optionElement.target = Revamp
	optionElement.onClickCallback = callback
	optionElement.settingId = definition.id
	-- Ein Schalter bringt Vanillas eigene An/Aus-Beschriftung schon mit.
	if definition.settingType ~= Revamp.SETTING_TYPE.BOOL then
		optionElement:setTexts(Revamp.getSettingTexts(definition))
	end

	for _, element in ipairs(container.elements) do
		if element.profile == "fs25_settingsMultiTextOptionTitle" then
			element:setText(g_i18n:getText("revamp_setting_" .. definition.id))
		end
	end

	-- Der Hilfetext ist ein durchsichtiger Text neben dem Bedienelement, der erst beim Anwählen der Zeile sichtbar wird, und hängt deshalb im Bedienelement statt in der Zeile.
	for _, element in ipairs(optionElement.elements) do
		if element.profile == "fs25_multiTextOptionTooltip" then
			element:setText(g_i18n:getText("revamp_setting_" .. definition.id .. "_tooltip"))
		end
	end

	return optionElement
end

---Stellt ein Bedienelement auf den Wert seiner Einstellung.
---@param optionElement table Bedienelement der Zeile
---@param definition table Eintrag aus Revamp.SETTINGS oder Revamp.DISPLAY_SETTINGS
---@param value any Wert der Einstellung
function Revamp.setSettingElementState(optionElement, definition, value)
	local state = Revamp.getSettingState(definition, value)

	if definition.settingType ~= Revamp.SETTING_TYPE.BOOL then
		optionElement:setState(state)
		return
	end

	-- Ein Schalter zieht die grüne Markierung und seinen Regler nur nach, wenn sich sein Zustand tatsächlich ändert.
	-- Ein Klon startet aber mit Zustand und Reglerstellung der Vanilla-Zeile, aus der er entstanden ist: stimmt der Zustand zufällig schon, bliebe die Markierung dauerhaft auf "Aus" stehen und der Regler an der geklonten Stelle.
	-- Deshalb den Zustand direkt setzen und das Nachziehen selbst anstoßen, statt es setState zu überlassen.
	optionElement.state = state
	optionElement:updateSelection()
	-- Ohne das liefe der Regler beim Öffnen des Menüs sichtbar von seiner geklonten Stellung herüber, statt gleich richtig zu stehen.
	optionElement.skipAnimation = true
end

---Schreibt die aktuellen Werte in die Bedienelemente.
---Nötig bei jedem Öffnen, weil ein anderer Admin sie zwischenzeitlich geändert haben kann.
---@param frame table InGameMenuSettingsFrame-Instanz
function Revamp.updateSettingElements(frame)
	if frame.revampSettingElements == nil then
		return
	end

	for id, optionElement in pairs(frame.revampSettingElements) do
		Revamp.setSettingElementState(optionElement, Revamp.settingsById[id], Revamp.settings[id])
		optionElement:setDisabled(not frame.hasMasterRights)
	end

	-- Die Anzeige-Einstellungen gelten nur für diesen Spieler und brauchen deshalb keine Adminrechte.
	for id, optionElement in pairs(frame.revampDisplayElements) do
		Revamp.setSettingElementState(optionElement, Revamp.displaySettingsById[id], Revamp.displaySettings[id])
	end
end

---Legt die Revamp-Zeilen beim ersten Öffnen des Einstellungsmenüs an und bringt sie danach bei jedem Öffnen auf den aktuellen Stand.
---@param frame table InGameMenuSettingsFrame-Instanz
function Revamp.onSettingsFrameOpen(frame)
	if frame.revampSettingElements == nil then
		frame.revampSettingElements = {}
		Revamp.addSettingsSectionHeader(frame.gameSettingsLayout, g_i18n:getText("revamp_settings_title"))
		for _, definition in ipairs(Revamp.SETTINGS) do
			frame.revampSettingElements[definition.id] = Revamp.addSettingElement(frame, frame.gameSettingsLayout, definition, Revamp.onSettingChanged)
		end

		-- Die Anzeige-Einstellungen stehen bei den allgemeinen Einstellungen, nicht bei denen des Spielstands: den Spielstand-Bereich blendet Vanilla im Mehrspieler für alle ohne Adminrechte komplett aus, und dort käme kein normaler Spieler mehr an seine eigene Anzeige.
		frame.revampDisplayElements = {}
		Revamp.addSettingsSectionHeader(frame.generalSettingsLayout, g_i18n:getText("revamp_settings_displayTitle"))
		for _, definition in ipairs(Revamp.DISPLAY_SETTINGS) do
			frame.revampDisplayElements[definition.id] = Revamp.addSettingElement(frame, frame.generalSettingsLayout, definition, Revamp.onDisplaySettingChanged)
		end
	end

	Revamp.updateSettingElements(frame)
	-- Vanilla färbt die Zeilen abwechselnd ein und ist damit schon durch, bevor die Revamp-Zeilen überhaupt existieren.
	frame:updateAlternatingElements(frame.gameSettingsLayout)
	frame:updateAlternatingElements(frame.generalSettingsLayout)
end

---Übernimmt eine im Einstellungsmenü geänderte Einstellung.
---Als Server wird sie sofort gesetzt und an alle Clients verteilt, als Client geht sie zum Server und kommt von dort zurück:
---so steht überall der Stand, den der Server tatsächlich übernommen hat, statt der Client sich seinen eigenen zu setzen.
---@param state number Neuer Zustand des Bedienelements
---@param optionElement table Geändertes Bedienelement
function Revamp:onSettingChanged(state, optionElement)
	local definition = Revamp.settingsById[optionElement.settingId]
	if definition == nil then
		return
	end

	if g_server ~= nil then
		Revamp.setSetting(definition.id, Revamp.getSettingValueFromState(definition, state))
		Revamp_EventSettings.sendToClients()
		return
	end

	g_client:getServerConnection():sendEvent(Revamp_EventSettingsChange.new(definition.id, state))
end

---Übernimmt eine geänderte Anzeige-Einstellung und schreibt sie sofort in die Profildatei.
---@param state number Neuer Zustand des Bedienelements
---@param optionElement table Geändertes Bedienelement
function Revamp:onDisplaySettingChanged(state, optionElement)
	local definition = Revamp.displaySettingsById[optionElement.settingId]
	if definition == nil then
		return
	end

	Revamp.displaySettings[definition.id] = Revamp.getSettingValueFromState(definition, state)
	Revamp.saveDisplaySettings()
end

---Schickt einem gerade fertig geladenen Client die aktuellen Einstellungen.
---Läuft auf dem Server: Vanilla verteilt an dieser Stelle mit SavegameSettingsEvent auch seine eigenen Spielstand-Einstellungen.
---@param mission table FSBaseMission-Instanz
---@param connection table Netzwerkverbindung des beitretenden Clients
function Revamp.sendSettingsToConnection(mission, connection)
	-- Vanilla ruft dieselbe Stelle auch für eine abgewiesene Verbindung auf, die dann sofort geschlossen wird und nichts mehr empfangen kann.
	if mission.playersSynchronizing[connection] == nil then
		return
	end

	connection:sendEvent(Revamp_EventSettings.new())
end

---Liefert die Benutzerkennung, unter der eine Aktion ausgeführt wird.
---@param connection? table Netzwerkverbindung des auslösenden Spielers, nil wenn die Aktion vom eigenen Rechner kommt
---@return number|nil userId Benutzerkennung, nil wenn die Verbindung keinem Spieler zugeordnet werden kann
function Revamp.getUserId(connection)
	-- Die eigene Verbindung gehört im Einzelspieler und auf dem Server zum Spieler an diesem Rechner, ein Benutzer dazu ist im Benutzerverwalter nicht hinterlegt.
	if connection == nil or connection:getIsLocal() then
		return g_currentMission.playerUserId
	end

	local user = g_currentMission.userManager:getUserByConnection(connection)
	if user == nil then
		return nil
	end
	return user:getId()
end

---Prüft, ob ein Spieler an einer Produktionsstätte kaufen und verkaufen darf.
---@param productionPoint table ProductionPoint-Instanz
---@param connection? table Netzwerkverbindung des auslösenden Spielers, nil wenn die Aktion vom eigenen Rechner kommt
---@return boolean allowed true, wenn gehandelt werden darf
function Revamp.isTradeAllowedForUser(productionPoint, connection)
	local restriction = Revamp.settings.tradeRestriction

	if restriction == "everyone" then
		return true
	end

	local farmId = productionPoint:getOwnerFarmId()
	if restriction == "productionAgent" then
		return g_currentMission:getHasPlayerPermission("manageProductions", connection, farmId)
	end

	-- Für den Betriebsleiter kennt Vanilla keine eigene Berechtigung, danach muss der Betrieb selbst gefragt werden.
	local userId = Revamp.getUserId(connection)
	local farm = g_farmManager:getFarmById(farmId)
	return userId ~= nil and farm ~= nil and farm:isUserFarmManager(userId)
end

Revamp.initSettings()
Revamp.loadDisplaySettings()

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, Revamp.loadSettings)
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, Revamp.saveSettings)

FSBaseMission.onConnectionFinishedLoading = Utils.appendedFunction(FSBaseMission.onConnectionFinishedLoading, Revamp.sendSettingsToConnection)

InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, Revamp.onSettingsFrameOpen)
InGameMenuSettingsFrame.updateGameSettings = Utils.appendedFunction(InGameMenuSettingsFrame.updateGameSettings, Revamp.updateSettingElements)
