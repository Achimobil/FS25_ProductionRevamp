-- "Verwalten"-Dialog: eigener, selbst kontrollierter Ersatz für PSCs separate Einstellungs-Dialoge.
-- Zeigt alle FillTypes einer Produktionsstätte in bis zu drei Bereichen (Input / Input+Output / Output, punktweiter Abgleich wie im FS25_InfoDisplayExtension-Vorbild -
-- ein FillType gilt als "Input+Output", sobald er IRGENDWO am Punkt Input UND IRGENDWO Output ist, auch wenn beides in verschiedenen Rezeptlinien passiert) mit echten Mengenangaben statt Balken.
--
-- Bewusst ein eigener Dialog statt Buttons in Vanillas Materialienliste (siehe revamp_storage.lua): detailsList ist von Vanilla explizit von der Fokus-Navigation ausgeschlossen (handleFocus="false"),
-- ein eigener Dialog mit eigener Liste hat dagegen echte, funktionierende Fokus-Navigation - exakt das Muster, das PSCs eigene Dialoge (RevampStorageDialog-Vorbild) schon nutzen.
--
-- Kaufen/Verkaufen/Verteil-Priorität-Buttons kommen erst mit ihren jeweiligen Modulen (Buy/Sell, Distribution) - aktuell nur der Ausgangsmodus-Button, zum Testen des Dialog-Grundgerüsts.

RevampManageDialog = {}
local RevampManageDialog_mt = Class(RevampManageDialog, YesNoDialog)

---Lädt die Dialog-XML und registriert die Dialoginstanz beim GUI-System.
function RevampManageDialog.register()
	local dialog = RevampManageDialog.new()
	local path = Utils.getFilename("gui/revamp_manageDialog.xml", g_currentModDirectory)
	g_gui:loadGui(path, "RevampManageDialog", dialog)
	RevampManageDialog.INSTANCE = dialog
end

---Öffnet den Verwalten-Dialog für einen konkreten Produktionspunkt.
---@param productionPoint table ProductionPoint-Instanz, deren FillTypes angezeigt werden
function RevampManageDialog.show(productionPoint)
	if RevampManageDialog.INSTANCE ~= nil then
		local dialog = RevampManageDialog.INSTANCE
		dialog.productionPoint = productionPoint
		dialog:setTitle(g_i18n:getText("revamp_manageDialogTitle"))
		dialog:updateRows()
		g_gui:showDialog("RevampManageDialog")
	end
end

---Erzeugt eine neue Dialoginstanz.
---@param target? table Ziel-Objekt für die GUI-Elemente (siehe YesNoDialog.new)
---@param custom_mt? table Metatable, falls von einer abgeleiteten Klasse aufgerufen
---@return table self Neue RevampManageDialog-Instanz
function RevampManageDialog.new(target, custom_mt)
	local self = YesNoDialog.new(target, custom_mt or RevampManageDialog_mt)
	return self
end

---Setzt beim Öffnen den Fokus auf die FillType-Liste - ohne das bekäme keine der Zeilen den Fokus (gleiches Muster wie Vanillas eigene Shop-Dialoge mit einer Artikelliste,
---z.B. VehicleShopDialog/PalletShopDialog, die beide FocusManager:setFocus() auf ihr Listenelement in onOpen() aufrufen).
function RevampManageDialog:onOpen()
	RevampManageDialog:superClass().onOpen(self)
	FocusManager:setFocus(self.manageList)
end

---Teilt die FillTypes eines Produktionspunkts punktweit in reine Inputs, Dual-Rolle (Input UND Output) und reine Outputs auf.
---@param productionPoint table ProductionPoint-Instanz
---@return table pureInputs FillType-Indizes, die nur als Input vorkommen
---@return table dual FillType-Indizes, die sowohl Input als auch Output sind
---@return table pureOutputs FillType-Indizes, die nur als Output vorkommen
function Revamp.splitFillTypesByRole(productionPoint)
	local inputSet, outputSet = {}, {}
	for _, fillType in ipairs(productionPoint.inputFillTypeIdsArray) do
		inputSet[fillType] = true
	end
	for _, fillType in ipairs(productionPoint.outputFillTypeIdsArray) do
		outputSet[fillType] = true
	end

	local pureInputs, dual, pureOutputs = {}, {}, {}
	for _, fillType in ipairs(productionPoint.inputFillTypeIdsArray) do
		table.insert(outputSet[fillType] and dual or pureInputs, fillType)
	end
	for _, fillType in ipairs(productionPoint.outputFillTypeIdsArray) do
		if not inputSet[fillType] then
			table.insert(pureOutputs, fillType)
		end
	end
	return pureInputs, dual, pureOutputs
end

---Berechnet die Sektionsaufteilung neu und lädt die Liste + Auswahlzustand neu - wird beim Öffnen und nach jedem Moduswechsel aufgerufen.
function RevampManageDialog:updateRows()
	self.pureInputs, self.dual, self.pureOutputs = Revamp.splitFillTypesByRole(self.productionPoint)
	self.manageList:reloadData()
	self:onListSelectionChanged(self.manageList, self.manageList.selectedSectionIndex, self.manageList.selectedIndex)
end

---Blendet den "Ausgangsmodus ändern"-Button ein/aus - reine Input-Zeilen haben keinen Ausgangsmodus, der Button bliebe sonst klickbar, obwohl er für diese Zeile nichts bewirkt
---(sieht für den Spieler nach einer Funktion aus, die es gar nicht gibt).
---@param list table Liste, deren Auswahl sich geändert hat
---@param section number Gewählte Sektion
---@param index number Gewählter Zeilenindex innerhalb der Sektion
function RevampManageDialog:onListSelectionChanged(list, section, index)
	if list ~= self.manageList or self.yesButton == nil then
		return
	end

	local fillTypes, hasOutputRole = self:getSectionFillTypes(section)
	self.yesButton:setVisible(hasOutputRole and fillTypes[index] ~= nil)
end

---Bildet section (2 oder 3 Abschnitte, je nachdem ob es überhaupt Input+Output-FillTypes gibt) auf die passende FillType-Liste ab, plus ob die Zeile eine Output-Rolle hat
---(Modus-Spalte + Umschalten greifen nur dort - eine reine Input-Zutat hat keinen Ausgangsmodus).
---@param section number Sektionsindex
---@return table fillTypes FillType-Indizes dieser Sektion
---@return boolean hasOutputRole true, wenn die Sektion Output-FillTypes enthält
function RevampManageDialog:getSectionFillTypes(section)
	if section == 1 then
		return self.pureInputs, false
	end
	if #self.dual > 0 and section == 2 then
		return self.dual, true
	end
	return self.pureOutputs, true
end

---Liefert die Anzahl Sektionen (2 ohne Dual-Rolle-FillTypes, sonst 3).
---@param list table Liste, deren Sektionsanzahl abgefragt wird
---@return number count Anzahl Sektionen
function RevampManageDialog:getNumberOfSections(list)
	if list ~= self.manageList then
		return 1
	end
	return #self.dual > 0 and 3 or 2
end

---Liefert den lokalisierten Titel einer Sektionsüberschrift.
---@param list table Liste, deren Sektionstitel abgefragt wird
---@param section number Sektionsindex
---@return string? title Lokalisierter Sektionstitel, nil wenn list nicht die eigene Liste ist
function RevampManageDialog:getTitleForSectionHeader(list, section)
	if list ~= self.manageList then
		return nil
	end
	if section == 1 then
		return g_i18n:getText("ui_productions_incomingMaterials")
	end
	if #self.dual > 0 and section == 2 then
		return g_i18n:getText("revamp_manageSectionBoth")
	end
	return g_i18n:getText("ui_productions_outgoingProducts")
end

---Liefert die Anzahl Zeilen einer Sektion.
---@param list table Liste, deren Zeilenanzahl abgefragt wird
---@param section number Sektionsindex
---@return number count Anzahl Zeilen in dieser Sektion
function RevampManageDialog:getNumberOfItemsInSection(list, section)
	if list ~= self.manageList then
		return 0
	end
	return #self:getSectionFillTypes(section)
end

---Befüllt eine Listenzeile mit Icon, Name, Menge/Kapazität und (falls Output-Rolle) Ausgangsmodus.
---@param list table Liste, deren Zelle gerade befüllt wird
---@param section number Sektionsindex
---@param index number Zeilenindex innerhalb der Sektion
---@param cell table Zu befüllende Zelle
function RevampManageDialog:populateCellForItemInSection(list, section, index, cell)
	if list ~= self.manageList then
		return
	end

	local fillTypes, hasOutputRole = self:getSectionFillTypes(section)
	local fillType = fillTypes[index]
	local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillType)

	cell:getAttribute("icon"):setImageFilename(fillTypeDesc.hudOverlayFilename)
	cell:getAttribute("name"):setText(fillTypeDesc.title)

	local fillLevel = self.productionPoint:getFillLevel(fillType)
	local capacity = self.productionPoint:getCapacity(fillType)
	cell:getAttribute("amount"):setText(g_i18n:formatVolume(fillLevel, 0) .. " / " .. g_i18n:formatVolume(capacity, 0))

	local modeText = cell:getAttribute("mode")
	if hasOutputRole then
		modeText:setText(Revamp.getOutputModeText(self.productionPoint, fillType))
	else
		modeText:setText("")
	end
end

---Schaltet den Ausgangsmodus der aktuell gewählten Zeile weiter (Klick auf "Ausgangsmodus ändern").
function RevampManageDialog:onClickChangeMode()
	local section = self.manageList.selectedSectionIndex
	local index = self.manageList.selectedIndex
	if section == nil or index == nil then
		return
	end

	local fillTypes, hasOutputRole = self:getSectionFillTypes(section)
	local fillType = fillTypes[index]
	if fillType == nil or not hasOutputRole then
		return
	end

	self.productionPoint:toggleOutputDistributionMode(fillType)
	self.manageList:reloadData()
end

---Schließt den Dialog ohne weitere Aktion.
function RevampManageDialog:onClickBack()
	self:close()
end

---Entfernt Vanillas eigenen Ausgangsmodus-Button aus der Menü-Button-Leiste - er ist durch Verwalten überflüssig geworden (macht dasselbe, nur eingeschränkt auf den primären Output).
---Aktiv entfernt, weil die untere Button-Leiste nur 6 feste Plätze hat
---und Vanilla allein schon bis zu 5 davon belegen kann (Zurück, Seite vor/zurück, Kartenmarkierung, Besuchen, Aktivieren/Deaktivieren) -
---ohne dieses Entfernen wäre für Verwalten UND Auslagern (revamp_spawner.lua) oft kein Platz mehr.
---@param self table InGameMenuProductionFrame-Instanz
function Revamp.removeVanillaOutputModeButton(self)
	table.removeElement(self.menuButtonInfo, self.toggleStorageModeButtonInfo)
end

---Fügt den "Verwalten"-Button in die Menü-Button-Leiste ein, sobald eine eigene Produktionsstätte gewählt ist - gleiches Muster wie PSCs eigener "Spawn"-Button (updateMenuButtonsAppend),
---eigene InputAction (MENU_EXTRA_1) damit es nicht mit Vanillas bestehendem Ausgangsmodus-Button (MENU_ACTIVATE) kollidiert.
---@param self table InGameMenuProductionFrame-Instanz
function Revamp.addManageButton(self)
	Revamp.removeVanillaOutputModeButton(self)
	if self.pointsSelector:getState() == InGameMenuProductionFrame.POINTS_OWNED then
		local _, productionPoint = self:getSelectedProduction()
		if productionPoint ~= nil then
			table.insert(self.menuButtonInfo, {
				profile = "buttonOK",
				inputAction = InputAction.MENU_EXTRA_1,
				text = g_i18n:getText("revamp_manageButton"),
				callback = function()
					RevampManageDialog.show(productionPoint)
				end
			})
		end
	end
end

InGameMenuProductionFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuProductionFrame.updateMenuButtons, Revamp.addManageButton)
