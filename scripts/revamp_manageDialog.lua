--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- "Verwalten"-Dialog: eigener, selbst kontrollierter Ersatz für PSCs separate Einstellungs-Dialoge.
-- Zeigt alle FillTypes einer Produktionsstätte in bis zu drei Bereichen (Input / Input+Output / Output, punktweiter Abgleich wie im FS25_InfoDisplayExtension-Vorbild -
-- ein FillType gilt als "Input+Output", sobald er IRGENDWO am Punkt Input UND IRGENDWO Output ist, auch wenn beides in verschiedenen Rezeptlinien passiert) mit echten Mengenangaben statt Balken.
--
-- Bewusst ein eigener Dialog statt Buttons in Vanillas Materialienliste (siehe revamp_storage.lua): detailsList ist von Vanilla explizit von der Fokus-Navigation ausgeschlossen (handleFocus="false"),
-- ein eigener Dialog mit eigener Liste hat dagegen echte, funktionierende Fokus-Navigation - exakt das Muster, das PSCs eigene Dialoge (RevampStorageDialog-Vorbild) schon nutzen.
--
-- Kaufen/Verkaufen-Buttons öffnen RevampBuyGoodsDialog für die aktuell gewählte Zeile (siehe revamp_buyGoodsDialog.lua) -
-- Kaufen nur bei Input-Rolle, Verkaufen nur bei Output-Rolle, analog zu PSTs eigener Aufteilung (inputFillTypeIdsArray/outputFillTypeIdsArray).
--
-- Über die weiteren Ansichten sind zusätzlich die Einstellungen erreichbar, die nicht pro Ware gelten: die Auswahlmodi für Zutaten und Booster
-- pro Rezeptlinie (siehe revamp_recipeSettings.lua), die Verteilziele je Erzeugnis (siehe revamp_distribution.lua) und die Übersicht der annehmbaren Tiere an einer Produktionsstätte mit Tier-Trigger (siehe revamp_animals.lua).
-- Der Dialog ist damit der gemeinsame Ort für alles, was der Spieler an einer eigenen Produktionsstätte einstellen kann, statt für jede weitere Einstellung einen eigenen Menü-Button zu brauchen (die Leiste hat nur sechs Plätze).

RevampManageDialog = {}
local RevampManageDialog_mt = Class(RevampManageDialog, YesNoDialog)

-- Der Dialog hat vier Ansichten: die FillType-Ansicht zeigt, was pro Ware gilt (Bestand, Ausgangsmodus, Kaufen/Verkaufen),
-- die Produktionslinien-Ansicht das, was pro Rezeptlinie gilt (die Auswahlmodi, siehe revamp_recipeSettings.lua),
-- die Verteilen-Ansicht die Ziele je Erzeugnis (siehe revamp_distribution.lua)
-- und die Tier-Ansicht, welche Tiere die Produktionsstätte annimmt und was sie einbringen (siehe revamp_animals.lua).
-- Die Verteilziele hätten auch in die Waren-Ansicht gepasst, brauchen aber eine Zeile je Ziel statt je Ware und damit eine eigene Liste.
-- Die Tier-Ansicht gibt es nur an einer Produktionsstätte mit Tier-Trigger, überall sonst wird sie beim Umschalten übersprungen.
RevampManageDialog.VIEW = {
	FILLTYPES = 1,
	PRODUCTIONS = 2,
	DISTRIBUTION = 3,
	ANIMALS = 4
}
RevampManageDialog.VIEW_COUNT = 4

-- Beschriftung des Umschalt-Buttons, benannt ist darauf immer die Ansicht, in die er führt.
RevampManageDialog.VIEW_TEXTS = {
	[RevampManageDialog.VIEW.FILLTYPES] = "revamp_manageViewFillTypes",
	[RevampManageDialog.VIEW.PRODUCTIONS] = "revamp_manageViewProductions",
	[RevampManageDialog.VIEW.DISTRIBUTION] = "revamp_manageViewDistribution",
	[RevampManageDialog.VIEW.ANIMALS] = "revamp_manageViewAnimals"
}

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
		dialog.viewMode = RevampManageDialog.VIEW.FILLTYPES
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
	-- Auslagern gilt für die ganze Stätte und nicht für die gewählte Zeile, deshalb steht die Sichtbarkeit hier und nicht in onListSelectionChanged.
	self.spawnButton:setVisible(Revamp.getCanSpawnGoods(self.productionPoint))
	self:updateButtonRows()
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

---Sammelt die Rezeptlinien eines Produktionspunkts für die Produktionslinien-Ansicht.
---Vom Modder versteckte Linien bleiben draußen, genau wie im Vanilla-Produktionsmenü - sie sollen für den Spieler gar nicht existieren.
---@param productionPoint table ProductionPoint-Instanz
---@return table productions Sichtbare Rezeptlinien in der Reihenfolge der Placeable-XML
function Revamp.getVisibleProductions(productionPoint)
	local productions = {}
	for _, production in ipairs(productionPoint.productions) do
		if not production.hideFromMenu then
			table.insert(productions, production)
		end
	end
	return productions
end

---Gibt alle gebauten Listenzeilen an den Zellen-Cache zurück, damit die nächste Ansicht ihre eigene Zeilenform bekommt.
---SmoothListElement:reloadData(true) macht das selbst, läuft dabei aber über #section.cells: war die Liste gescrollt, fehlt dort der Index 1,
---der Längenoperator liefert dann 0 und keine einzige Zeile wird zurückgegeben.
function RevampManageDialog:releaseListCells()
	for _, section in pairs(self.manageList.sections) do
		-- Erst sammeln, dann zurückgeben: queueReusableCell entfernt die Zelle aus section.cells und verändert damit die gerade laufende Iteration.
		local cells = {}
		for index, cell in pairs(section.cells) do
			-- Der Sektionskopf bei Index 0 hat in allen Ansichten dieselbe Form und bleibt stehen.
			if index > 0 then
				table.insert(cells, cell)
			end
		end

		for _, cell in ipairs(cells) do
			self.manageList:queueReusableCell(cell)
		end
	end
end

---Berechnet die Sektionsaufteilung neu und lädt die Liste + Auswahlzustand neu - wird beim Öffnen, nach jedem Moduswechsel und nach jedem Ansichtswechsel aufgerufen.
function RevampManageDialog:updateRows()
	self.pureInputs, self.dual, self.pureOutputs = Revamp.splitFillTypesByRole(self.productionPoint)
	self.productions = Revamp.getVisibleProductions(self.productionPoint)
	self.distributionSections = Revamp.getDistributionSections(self.productionPoint)
	self.animals = Revamp.getAnimalRows(self.productionPoint)
	-- Jede Ansicht hat ihre eigene Zeilenform, die Zeilen der bisherigen müssen vor dem Neuaufbau also weg.
	-- reloadData(true) allein erwischt dabei nicht alle, siehe releaseListCells.
	self:releaseListCells()
	self.manageList:reloadData(true)
	self:updateTitle()
	self:updateSharedStorageHint()
	self:onListSelectionChanged(self.manageList, self.manageList.selectedSectionIndex, self.manageList.selectedIndex)
end

---Schreibt die gerade gezeigte Ansicht in den Dialogtitel.
---Der Umschalt-Knopf ist immer nach der Ansicht benannt, in die er führt, ohne den Titel stünde also nirgends, welche gerade zu sehen ist.
function RevampManageDialog:updateTitle()
	self:setTitle(g_i18n:getText("revamp_manageDialogTitle") .. " - " .. g_i18n:getText(RevampManageDialog.VIEW_TEXTS[self.viewMode]))
end

---Zeigt unter der Liste die Legende zum Kennzeichen für geteilten Lagerplatz (siehe Revamp.getSharedStorageCapacity in revamp_storage.lua).
---Nur in der Waren-Ansicht, die anderen beiden Ansichten zeigen gar keine Mengen und damit auch kein Kennzeichen.
function RevampManageDialog:updateSharedStorageHint()
	local sharedCapacity = nil
	if self.viewMode == RevampManageDialog.VIEW.FILLTYPES then
		sharedCapacity = Revamp.getSharedStorageCapacity(self.productionPoint)
	end

	self.sharedStorageHint:setVisible(sharedCapacity ~= nil)
	if sharedCapacity ~= nil then
		self.sharedStorageHint:setText(Revamp.SHARED_STORAGE_MARK .. " " .. string.format(g_i18n:getText("revamp_manageSharedStorageHint"), g_i18n:formatVolume(sharedCapacity, 0)))
	end
end

---Prüft, ob eine Ansicht gerade zur Verfügung steht - ein abgeschaltetes Modul und eine Ansicht, die es an dieser Produktionsstätte gar nicht gibt, sollen nicht nur wirkungslos, sondern nicht erreichbar sein.
---@param viewMode number Eine der RevampManageDialog.VIEW-Konstanten
---@return boolean available true, wenn die Ansicht benutzbar ist
function RevampManageDialog:isViewAvailable(viewMode)
	if viewMode == RevampManageDialog.VIEW.PRODUCTIONS then
		-- Ohne eine einzige Wahlmöglichkeit bleibt von der Ansicht nur eine Liste der Linien-Namen mit leerer Modus-Spalte übrig.
		return Revamp.settings.recipeSettingsActive and Revamp.getHasRecipeChoices(self.productionPoint)
	end
	if viewMode == RevampManageDialog.VIEW.DISTRIBUTION then
		return Revamp.settings.distributionActive
	end
	if viewMode == RevampManageDialog.VIEW.ANIMALS then
		return Revamp.getHasAnimalInputs(self.productionPoint)
	end
	-- Die Waren-Ansicht zeigt die Bestände und bleibt deshalb immer erreichbar.
	return true
end

---Liefert die nächste verfügbare Ansicht, abgeschaltete werden dabei übersprungen.
---Sind alle übrigen abgeschaltet, kommt die aktuelle Ansicht selbst zurück.
---@param viewMode number Ansicht, von der aus weitergeschaltet wird
---@return number nextViewMode Nächste verfügbare Ansicht
function RevampManageDialog:getNextView(viewMode)
	for _ = 1, RevampManageDialog.VIEW_COUNT do
		viewMode = viewMode % RevampManageDialog.VIEW_COUNT + 1
		if self:isViewAvailable(viewMode) then
			break
		end
	end

	return viewMode
end

---Schaltet der Reihe nach durch die Ansichten Waren, Produktionslinien, Verteilen und Tiere.
function RevampManageDialog:onClickToggleView()
	self.viewMode = self:getNextView(self.viewMode)

	self:updateRows()
	-- Erst nach dem Neuaufbau, weil setSelectedItem gegen die Sektionen der jeweils geladenen Liste prüft.
	-- Ohne das Zurücksetzen stünde der Auswahlbalken nach dem Umschalten auf der Zeilennummer der vorherigen Ansicht.
	self.manageList:setSelectedItem(1, 1, true)
end

---Liefert die Zeilenform der aktuellen Ansicht - jede Ansicht hat ihre eigene, weil in jeder andere Spalten stehen.
---@param list table Liste, die die Zeile aufbauen will
---@param section number Sektionsindex
---@param index number Zeilenindex innerhalb der Sektion
function RevampManageDialog:getCellTypeForItemInSection(list, section, index) ---@diagnostic disable-line: unused-local
	if self.viewMode == RevampManageDialog.VIEW.PRODUCTIONS then
		return "productionRow"
	end
	if self.viewMode == RevampManageDialog.VIEW.DISTRIBUTION then
		return "distributionRow"
	end
	if self.viewMode == RevampManageDialog.VIEW.ANIMALS then
		return "animalRow"
	end
	return "fillTypeRow"
end

---Blendet "Ausgangsmodus ändern"/"Kaufen"/"Verkaufen" pro Zeilenrolle ein/aus - eine reine Input-Zeile hat z.B. keinen Ausgangsmodus, der Button bliebe sonst klickbar,
---obwohl er für diese Zeile nichts bewirkt (sieht für den Spieler nach einer Funktion aus, die es gar nicht gibt).
---Genauso ausgeblendet werden Kaufen/Verkaufen für Fülltypen, die der Modder dafür gesperrt hat (siehe revamp_buySell.lua).
---@param list table Liste, deren Auswahl sich geändert hat
---@param section number Gewählte Sektion
---@param index number Gewählter Zeilenindex innerhalb der Sektion
function RevampManageDialog:onListSelectionChanged(list, section, index)
	if list ~= self.manageList or self.yesButton == nil then
		return
	end

	if self.viewMode == RevampManageDialog.VIEW.PRODUCTIONS then
		local production = self.productions[index]
		self.yesButton:setVisible(false)
		self.buyButton:setVisible(false)
		self.sellButton:setVisible(false)
		self.mixModeButton:setVisible(production ~= nil and production.hasMixChoice)
		self.boostModeButton:setVisible(production ~= nil and production.hasBoostChoice)
		self.levelButton:setVisible(false)
		self.limitButton:setVisible(false)
	elseif self.viewMode == RevampManageDialog.VIEW.DISTRIBUTION then
		local target = self:getDistributionTargetAt(section, index)
		self.yesButton:setVisible(false)
		self.buyButton:setVisible(false)
		self.sellButton:setVisible(false)
		self.mixModeButton:setVisible(false)
		self.boostModeButton:setVisible(false)
		self.levelButton:setVisible(target ~= nil)
		-- Eine Obergrenze für ein Ziel, das ohnehin nie beliefert wird, hätte keine Wirkung.
		self.limitButton:setVisible(target ~= nil and target.level ~= "NEVER")
	elseif self.viewMode == RevampManageDialog.VIEW.ANIMALS then
		-- Die Tier-Ansicht zeigt nur, was der Modder festgelegt hat - daran gibt es für den Spieler nichts einzustellen.
		self.yesButton:setVisible(false)
		self.buyButton:setVisible(false)
		self.sellButton:setVisible(false)
		self.mixModeButton:setVisible(false)
		self.boostModeButton:setVisible(false)
		self.levelButton:setVisible(false)
		self.limitButton:setVisible(false)
	else
		local fillTypes, hasInputRole, hasOutputRole = self:getSectionFillTypes(section)
		local fillType = fillTypes[index]
		local hasRow = fillType ~= nil
		self.yesButton:setVisible(hasOutputRole and hasRow)
		-- Wer an dieser Produktionsstätte gar nicht handeln darf, bekommt beide Knöpfe nicht zu sehen.
		local mayTrade = Revamp.isTradeAllowedForUser(self.productionPoint)
		self.buyButton:setVisible(mayTrade and Revamp.settings.buyingActive and hasInputRole and hasRow and Revamp.isBuyingAllowed(self.productionPoint, fillType))
		-- Verkaufen nur anbieten, wenn tatsächlich etwas im Lager ist - unter 1 Liter Restbestand (z.B. durch Rundung) gäbe es sonst einen klickbaren Button ohne Wirkung.
		self.sellButton:setVisible(mayTrade and Revamp.settings.sellingActive and hasOutputRole and hasRow and Revamp.isSellingAllowed(self.productionPoint, fillType) and self.productionPoint:getFillLevel(fillType) >= 1)
		self.mixModeButton:setVisible(false)
		self.boostModeButton:setVisible(false)
		self.levelButton:setVisible(false)
		self.limitButton:setVisible(false)
	end

	-- Bleibt nur die Waren-Ansicht übrig, führt der Knopf nirgendwo mehr hin und verschwindet.
	local nextView = self:getNextView(self.viewMode)
	self.viewButton:setVisible(nextView ~= self.viewMode)
	self.viewButton:setText(g_i18n:getText(RevampManageDialog.VIEW_TEXTS[nextView]))

	self:updateButtonRows()

	-- Ohne das behält die Button-Leiste die Breiten der vorherigen Ansicht und lässt Lücken, wo gerade ein Knopf ausgeblendet wurde.
	self.buttonsPC:invalidateLayout()
end

---Bildet section (2 oder 3 Abschnitte, je nachdem ob es überhaupt Input+Output-FillTypes gibt) auf die passende FillType-Liste ab, plus ob die Zeile eine Input-
---bzw. Output-Rolle hat (Modus-Spalte/Umschalten und Verkaufen greifen nur bei Output-Rolle, Kaufen nur bei Input-Rolle - eine reine Input-Zutat hat z.B. keinen Ausgangsmodus).
---@param section number Sektionsindex
---@return table fillTypes FillType-Indizes dieser Sektion
---@return boolean hasInputRole true, wenn die Sektion Input-FillTypes enthält
---@return boolean hasOutputRole true, wenn die Sektion Output-FillTypes enthält
function RevampManageDialog:getSectionFillTypes(section)
	if section == 1 then
		return self.pureInputs, true, false
	end
	if #self.dual > 0 and section == 2 then
		return self.dual, true, true
	end
	return self.pureOutputs, false, true
end

---Liefert die Anzahl Sektionen (2 ohne Dual-Rolle-FillTypes, sonst 3).
---@param list table Liste, deren Sektionsanzahl abgefragt wird
---@return number count Anzahl Sektionen
function RevampManageDialog:getNumberOfSections(list)
	if list ~= self.manageList then
		return 1
	end
	if self.viewMode == RevampManageDialog.VIEW.PRODUCTIONS then
		return 1
	end
	if self.viewMode == RevampManageDialog.VIEW.DISTRIBUTION then
		-- Ohne einen einzigen Abnehmer bleibt eine Sektion übrig, deren Überschrift genau das sagt - eine komplett leere Liste sähe nach einem Fehler aus.
		return math.max(#self.distributionSections, 1)
	end
	if self.viewMode == RevampManageDialog.VIEW.ANIMALS then
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
	if self.viewMode == RevampManageDialog.VIEW.PRODUCTIONS then
		return g_i18n:getText("revamp_manageSectionProductions")
	end
	if self.viewMode == RevampManageDialog.VIEW.DISTRIBUTION then
		local sectionData = self.distributionSections[section]
		if sectionData == nil then
			return g_i18n:getText("revamp_distributionNoTargets")
		end
		return g_fillTypeManager:getFillTypeByIndex(sectionData.fillTypeIndex).title
	end
	if self.viewMode == RevampManageDialog.VIEW.ANIMALS then
		return g_i18n:getText("revamp_manageSectionAnimals")
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
	if self.viewMode == RevampManageDialog.VIEW.PRODUCTIONS then
		return #self.productions
	end
	if self.viewMode == RevampManageDialog.VIEW.DISTRIBUTION then
		local sectionData = self.distributionSections[section]
		return sectionData ~= nil and #sectionData.targets or 0
	end
	if self.viewMode == RevampManageDialog.VIEW.ANIMALS then
		return #self.animals
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

	if self.viewMode == RevampManageDialog.VIEW.PRODUCTIONS then
		self:populateProductionCell(index, cell)
		return
	end

	if self.viewMode == RevampManageDialog.VIEW.DISTRIBUTION then
		self:populateDistributionCell(section, index, cell)
		return
	end

	if self.viewMode == RevampManageDialog.VIEW.ANIMALS then
		self:populateAnimalCell(index, cell)
		return
	end

	local fillTypes, _, hasOutputRole = self:getSectionFillTypes(section)
	local fillType = fillTypes[index]
	local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillType)

	cell:getAttribute("icon"):setImageFilename(fillTypeDesc.hudOverlayFilename)
	cell:getAttribute("name"):setText(fillTypeDesc.title)

	local fillLevel = self.productionPoint:getFillLevel(fillType)
	local capacity = self.productionPoint:getCapacity(fillType)
	local amountText = g_i18n:formatVolume(fillLevel, 0) .. " / " .. g_i18n:formatVolume(capacity, 0)
	-- Kennzeichen für Waren, die sich ihren Lagerplatz teilen und deren Kapazität sich deshalb mit dem Bestand der übrigen Waren ändert. Erklärt wird es in der Fußnote unter der Liste.
	if Revamp.getIsSharedStorageMarked(self.productionPoint, fillType) then
		amountText = amountText .. Revamp.SHARED_STORAGE_MARK
	end
	cell:getAttribute("amount"):setText(amountText)

	local modeText = cell:getAttribute("mode")
	if hasOutputRole then
		modeText:setText(Revamp.getOutputModeText(self.productionPoint, fillType))
	else
		modeText:setText("")
	end
end

---Befüllt eine Zeile der Produktionslinien-Ansicht mit Name und den aktuell eingestellten Auswahlmodi.
---Eine Linie ohne jede Wahlmöglichkeit bleibt in der Modus-Spalte leer, statt einen Modus anzuzeigen, der bei ihr nichts bewirkt.
---@param index number Zeilenindex
---@param cell table Zu befüllende Zelle
function RevampManageDialog:populateProductionCell(index, cell)
	local production = self.productions[index]
	if production == nil then
		return
	end

	-- Ein Name ist in der Placeable-XML optional, die id dagegen Pflicht - ohne diesen Rückfall stünde die Zeile im Extremfall ganz ohne Beschriftung da.
	cell:getAttribute("name"):setText(production.name or production.id)

	local modes = {}
	if production.hasMixChoice then
		table.insert(modes, string.format("%s: %s", g_i18n:getText("revamp_mixModeLabel"), Revamp.getSelectionModeText(production.mixMode, false)))
	end
	if production.hasBoostChoice then
		table.insert(modes, string.format("%s: %s", g_i18n:getText("revamp_boostModeLabel"), Revamp.getSelectionModeText(production.boostMode, true)))
	end
	cell:getAttribute("modes"):setText(table.concat(modes, "   "))
end

---Befüllt eine Zeile der Tier-Ansicht mit Rasse, den Bedingungen und dem, was ein Tier einbringt.
---@param index number Zeilenindex
---@param cell table Zu befüllende Zelle
function RevampManageDialog:populateAnimalCell(index, cell)
	local row = self.animals[index]
	if row == nil then
		return
	end

	cell:getAttribute("icon"):setImageFilename(row.imageFilename)
	cell:getAttribute("name"):setText(row.title)

	-- Eine Produktion ohne Höchstalter nimmt Tiere jeden Alters ab dem Mindestalter, dort stünde sonst eine Monatszahl, die kein Tier je erreicht.
	if row.maxAge >= Revamp.ANIMAL_DEFAULT_MAX_AGE then
		cell:getAttribute("age"):setText(string.format(g_i18n:getText("revamp_animalAgeFrom"), g_i18n:formatNumMonth(row.minAge)))
	else
		cell:getAttribute("age"):setText(string.format("%s - %s", row.minAge, g_i18n:formatNumMonth(row.maxAge)))
	end

	cell:getAttribute("health"):setText(string.format("%d - %d %%", row.minHealth, row.maxHealth))

	local fillType = g_fillTypeManager:getFillTypeByIndex(row.fillTypeIndex)
	local unitShort = fillType.unitShort
	if unitShort == "" then
		unitShort = g_i18n:getText("unit_literShort")
	end

	-- Nur eine Menge anzeigen, wenn das Alter an der Liefermenge nichts ändert - "1000 l - 1000 l" sähe nach einer Spanne aus, die es nicht gibt.
	local amountText = g_i18n:formatVolume(row.biggestAmount, 0, unitShort)
	if math.floor(row.smallestAmount) ~= math.floor(row.biggestAmount) then
		amountText = string.format("%s - %s", g_i18n:formatVolume(row.smallestAmount, 0), amountText)
	end
	cell:getAttribute("result"):setText(string.format("%s %s", amountText, fillType.title))
end

---Liefert das Verteilziel einer Zeile der Verteilen-Ansicht.
---@param section number Sektionsindex (ein Erzeugnis je Sektion)
---@param index number Zeilenindex innerhalb der Sektion
---@return table|nil target Ziel-Eintrag aus Revamp.getDistributionSections, nil wenn es die Zeile nicht gibt
---@return table|nil sectionData Sektion, zu der die Zeile gehört
function RevampManageDialog:getDistributionTargetAt(section, index)
	local sectionData = self.distributionSections[section]
	if sectionData == nil then
		return nil, nil
	end
	return sectionData.targets[index], sectionData
end

---Befüllt eine Zeile der Verteilen-Ansicht mit Ziel, Obergrenze, Kostenvorschau und Verteilstufe.
---@param section number Sektionsindex
---@param index number Zeilenindex innerhalb der Sektion
---@param cell table Zu befüllende Zelle
function RevampManageDialog:populateDistributionCell(section, index, cell)
	local target = self:getDistributionTargetAt(section, index)
	if target == nil then
		return
	end

	cell:getAttribute("icon"):setImageFilename(target.productionPoint.owningPlaceable:getImageFilename())
	cell:getAttribute("name"):setText(target.productionPoint:getName())

	if target.limit ~= nil then
		cell:getAttribute("limit"):setText(string.format(g_i18n:getText("revamp_distributionLimitValue"), g_i18n:formatVolume(target.limit, 0)))
	else
		cell:getAttribute("limit"):setText(g_i18n:getText("revamp_distributionNoLimit"))
	end

	if target.costsPerHour ~= nil then
		-- Zwei Nachkommastellen, weil ein einzelnes nahes Ziel durchaus unter einem Euro je Stunde kostet und dort sonst nur "0" stünde.
		cell:getAttribute("costs"):setText(string.format(g_i18n:getText("revamp_distributionCostsPerHour"), g_i18n:formatMoney(target.costsPerHour, 2)))
	else
		-- Ein Ziel, das bei der aktuellen Einstellung gar nicht an der Reihe ist, zeigt einen Strich statt eines Betrags, den es nie zahlt.
		cell:getAttribute("costs"):setText("-")
	end
	cell:getAttribute("level"):setText(Revamp.getDistributionLevelText(target.level))
end

---Schaltet die Verteilstufe des gewählten Ziels eine Stufe weiter.
---Gleiches Bedienmuster wie beim Ausgangsmodus und den Auswahlmodi: bei vier Möglichkeiten ist ein eigener Auswahl-Dialog mehr Weg als Nutzen.
function RevampManageDialog:onClickChangeLevel()
	if self.viewMode ~= RevampManageDialog.VIEW.DISTRIBUTION then
		return
	end

	local target, sectionData = self:getDistributionTargetAt(self.manageList.selectedSectionIndex, self.manageList.selectedIndex)
	if target == nil or sectionData == nil then
		return
	end

	self.productionPoint:setDistributionTarget(sectionData.fillTypeIndex, target.productionPoint, Revamp.getNextDistributionLevel(target.level), target.limit)
	self:updateDistributionRows()
end

---Öffnet den Mengen-Dialog für die Obergrenze des gewählten Ziels.
function RevampManageDialog:onClickChangeLimit()
	if self.viewMode ~= RevampManageDialog.VIEW.DISTRIBUTION then
		return
	end

	local target, sectionData = self:getDistributionTargetAt(self.manageList.selectedSectionIndex, self.manageList.selectedIndex)
	if target == nil or sectionData == nil or target.level == "NEVER" then
		return
	end

	RevampDistributionLimitDialog.show(self.productionPoint, sectionData.fillTypeIndex, target)
end

---Rechnet die Verteilziele neu durch und lädt die Liste neu - nach jeder Änderung nötig, weil sich mit der Stufe eines Ziels
---auch die Kostenvorschau aller übrigen Ziele derselben Stufe ändert.
function RevampManageDialog:updateDistributionRows()
	self.distributionSections = Revamp.getDistributionSections(self.productionPoint)
	self.manageList:reloadData()
	self:onListSelectionChanged(self.manageList, self.manageList.selectedSectionIndex, self.manageList.selectedIndex)
end

---Schaltet den Mix- oder Booster-Modus der aktuell gewählten Rezeptlinie eine Stufe weiter.
---Zyklisch weiterschalten statt Auswahl-Dialog: dasselbe Bedienmuster wie beim Ausgangsmodus eine Ansicht weiter, und bei vier Möglichkeiten ist ein eigener Dialog mehr Weg als Nutzen.
---@param isMix boolean true für den Mix-Modus, false für den Booster-Modus
function RevampManageDialog:changeSelectionMode(isMix)
	if self.viewMode ~= RevampManageDialog.VIEW.PRODUCTIONS then
		return
	end

	local production = self.productions[self.manageList.selectedIndex]
	if production == nil then
		return
	end

	if isMix then
		if not production.hasMixChoice then
			return
		end
		self.productionPoint:setRecipeSelectionModes(production.id, Revamp.getNextSelectionMode(production.mixMode), nil)
	else
		if not production.hasBoostChoice then
			return
		end
		self.productionPoint:setRecipeSelectionModes(production.id, nil, Revamp.getNextSelectionMode(production.boostMode))
	end

	self.manageList:reloadData()
end

---Schaltet den Mix-Modus der gewählten Rezeptlinie weiter.
function RevampManageDialog:onClickChangeMixMode()
	self:changeSelectionMode(true)
end

---Schaltet den Booster-Modus der gewählten Rezeptlinie weiter.
function RevampManageDialog:onClickChangeBoostMode()
	self:changeSelectionMode(false)
end

---Schaltet den Ausgangsmodus der aktuell gewählten Zeile weiter (Klick auf "Ausgangsmodus ändern").
function RevampManageDialog:onClickChangeMode()
	local section = self.manageList.selectedSectionIndex
	local index = self.manageList.selectedIndex
	if section == nil or index == nil then
		return
	end

	local fillTypes, _, hasOutputRole = self:getSectionFillTypes(section)
	local fillType = fillTypes[index]
	if fillType == nil or not hasOutputRole then
		return
	end

	self.productionPoint:toggleOutputDistributionMode(fillType)
	self.manageList:reloadData()
end

---Öffnet RevampBuyGoodsDialog im Kauf-Modus für die aktuell gewählte Zeile.
function RevampManageDialog:onClickBuy()
	local section = self.manageList.selectedSectionIndex
	local index = self.manageList.selectedIndex
	if section == nil or index == nil then
		return
	end

	local fillTypes, hasInputRole = self:getSectionFillTypes(section)
	local fillType = fillTypes[index]
	if fillType == nil or not hasInputRole then
		return
	end

	RevampBuyGoodsDialog.show(self.productionPoint, self.productionPoint:getName(), {fillTypeIndex = fillType}, 1)
end

---Öffnet RevampBuyGoodsDialog im Verkauf-Modus für die aktuell gewählte Zeile.
function RevampManageDialog:onClickSell()
	local section = self.manageList.selectedSectionIndex
	local index = self.manageList.selectedIndex
	if section == nil or index == nil then
		return
	end

	local fillTypes, _, hasOutputRole = self:getSectionFillTypes(section)
	local fillType = fillTypes[index]
	if fillType == nil or not hasOutputRole then
		return
	end

	RevampBuyGoodsDialog.show(self.productionPoint, self.productionPoint:getName(), {fillTypeIndex = fillType}, 2)
end

---Ordnet beide Knopfreihen neu an, nachdem sich die Sichtbarkeit einzelner Knöpfe geändert hat.
---Ohne diesen Aufruf behält jeder Knopf die Stelle, an der er beim Aufbau des Dialogs gelandet ist - die Reihe rückt dann nicht nach und steht nicht mehr rechtsbündig.
function RevampManageDialog:updateButtonRows()
	self.buttonsRow:invalidateLayout()
	self.buttonsPC:invalidateLayout()
end

---Lagert Waren aus, genau wie der gleichnamige Knopf in der Menü-Button-Leiste (revamp_spawner.lua).
---Hier steht er zusätzlich, weil er aus der Leiste weichen muss, sobald ein anderer Mod dort ebenfalls einen Knopf einträgt (revamp_menuButtons.lua).
function RevampManageDialog:onClickSpawn()
	self.productionPoint.activatable:run(true)
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

---Nimmt Vanillas Deaktivieren-Knopf aus der Leiste, solange eine Linie gewählt ist, die laut Produktion von selbst laufen soll.
---Sie lässt sich ohnehin nicht mehr abschalten (siehe Revamp.setProductionState in revamp_production.lua) - ein Knopf, der nichts bewirkt, sieht für den Spieler nach einem Fehler aus.
---@param self table InGameMenuProductionFrame-Instanz
function Revamp.removeActivateButtonForAutoStart(self)
	local production = self:getSelectedProduction()

	if production ~= nil and (production.autoStart or production.hideFromMenu) then
		table.removeElement(self.menuButtonInfo, self.activateButtonInfo)
	end
end

---Fügt den "Verwalten"-Button in die Menü-Button-Leiste ein, sobald eine eigene Produktionsstätte gewählt ist - gleiches Muster wie PSCs eigener "Spawn"-Button (updateMenuButtonsAppend),
---Feste eigene InputAction (MENU_EXTRA_2), damit es nicht mit Vanillas bestehendem Ausgangsmodus-Button (MENU_ACTIVATE) kollidiert.
---Bewusst fest und nicht je nach Lage gewählt: ein Knopf, der mal auf der einen und mal auf der anderen Taste liegt, lässt sich nicht einprägen.
---@param self table InGameMenuProductionFrame-Instanz
function Revamp.addManageButton(self)
	Revamp.removeVanillaOutputModeButton(self)
	Revamp.removeActivateButtonForAutoStart(self)
	if self.pointsSelector:getState() == InGameMenuProductionFrame.POINTS_OWNED then
		local _, productionPoint = self:getSelectedProduction()
		if productionPoint ~= nil then
			table.insert(self.menuButtonInfo, {
				profile = "buttonOK",
				inputAction = InputAction.MENU_EXTRA_2,
				text = g_i18n:getText("revamp_manageButton"),
				callback = function()
					RevampManageDialog.show(productionPoint)
				end
			})
		end
	end
end

InGameMenuProductionFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuProductionFrame.updateMenuButtons, Revamp.addManageButton)
