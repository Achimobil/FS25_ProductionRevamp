-- Spawn-Assistent für den Auslagern-Button (siehe revamp_spawner.lua) - FillType->Paket->Menge->Hof->
-- Farbe, byte-nah portiert aus PSCs productionStorageControl_storageDialog.lua (Logik geprüft, keine
-- funktionalen Denkfehler gefunden). Zwei kleine Bereinigungen gegenüber dem Original:
-- setFillTypePackages setzte maxUnloadAmount bisher in einer Schleife für JEDE Paket-Option statt nur
-- die des tatsächlich per setState(1,true) ausgewählten ersten Pakets - hat durch den dadurch
-- ausgelösten onClickPackages-Callback zufällig trotzdem funktioniert, ist hier aber direkt korrekt
-- für Paket 1 gesetzt statt über die Schleifen-Nebenwirkung.

RevampStorageDialog = {}
local RevampStorageDialog_mt = Class(RevampStorageDialog, YesNoDialog)

---Lädt die Dialog-XML und registriert die Dialoginstanz beim GUI-System.
function RevampStorageDialog.register()
	local dialog = RevampStorageDialog.new()
	local path = Utils.getFilename("gui/revamp_storageDialog.xml", g_currentModDirectory)
	g_gui:loadGui(path, "RevampStorageDialog", dialog)
	RevampStorageDialog.INSTANCE = dialog
end

---Öffnet den Auslagern-Dialog mit den auslagerbaren FillTypes einer Produktionsstätte oder eines Silos.
---@param farmList table Liste auswählbarer Farmen (Empfänger der gespawnten Objekte)
---@param title string Dialogtitel (Name der Produktionsstätte bzw. des Silos)
---@param options table Auswahlbare FillType-Einträge inkl. ihrer Verpackungsoptionen (siehe Revamp.buildSpawnOptions)
---@param spawnTarget table Spawn-Ziel, aus dem ausgelagert wird
function RevampStorageDialog.show(farmList, title, options, spawnTarget)
	if RevampStorageDialog.INSTANCE ~= nil then
		local dialog = RevampStorageDialog.INSTANCE
		dialog.spawnTarget = spawnTarget
		dialog:setTitle(title)
		dialog:setFillTypes(options)
		dialog:setFarmList(farmList)
		dialog:setFoilColor(1)
		g_gui:showDialog("RevampStorageDialog")
	end
end

---Erzeugt eine neue Dialoginstanz mit den Standard-Auswahlwerten.
---@param target? table Ziel-Objekt für die GUI-Elemente (siehe YesNoDialog.new)
---@param custom_mt? table Metatable, falls von einer abgeleiteten Klasse aufgerufen
---@return table self Neue RevampStorageDialog-Instanz
function RevampStorageDialog.new(target, custom_mt)
	local self = YesNoDialog.new(target, custom_mt or RevampStorageDialog_mt)
	self.selectedFillType = 1
	self.selectedPackage = 1
	self.selectedAmount = 0
	self.selectedFarm = 1
	self.maxUnloadAmount = math.huge
	return self
end

---Setzt beim Öffnen den Fokus auf die FillType-Auswahl.
function RevampStorageDialog:onOpen()
	RevampStorageDialog:superClass().onOpen(self)
	FocusManager:setFocus(self.fillTypeElement)
end

---Bestätigt die aktuelle Auswahl und je nach Zustand wird
---- das Produktionsmenü (Pseudo-Eintrag "Produktion verwalten"/"Lager ist leer") geöffnet
---- das eigentliche Spawn-Event mit der gewählten Menge ausgelöst
function RevampStorageDialog:onClickOk()
	if self.selectedOption.openmenu ~= nil then
		-- Ein Silo hat kein Produktionsmenü: dort ist der Pseudo-Eintrag nur die Zeile "Lager ist leer", und die schließt den Dialog einfach.
		if self.spawnTarget.openMenu ~= nil then
			self.spawnTarget:openMenu()
		else
			self:close()
		end
	else
		local selectedPackage = self.selectedOption.packages[self.selectedPackage]
		local state = self.amountElement:getState()

		local amount, pendingLiters
		if self.hasRemainder and state == self.fullPalletCount + 2 then
			-- "Alles"-Eintrag: bewusst nicht capacity*amount (würde die letzte Palette randvoll
			-- annehmen), sondern der komplette restliche Lagerbestand als letzte, angefangene Palette.
			amount = self.fullPalletCount + 1
			pendingLiters = self.selectedOption.fillLevel
		else
			amount = state - 1
			pendingLiters = selectedPackage.capacity * amount
		end

		Revamp_EventSpawn.sendEvent(self.spawnTarget, self.farmList[self.selectedFarm].farmId, self.selectedFillType, pendingLiters, selectedPackage.width, selectedPackage.height, selectedPackage.length, selectedPackage.capacity, selectedPackage.type, selectedPackage.customEnvironment, selectedPackage.treeId, amount, self.selectedColor[1], self.selectedColor[2], self.selectedColor[3])
		self:close()
	end
end

---Schließt den Dialog ohne zu spawnen.
function RevampStorageDialog:onClickBack()
	self:close()
end

---Springt auf die maximale Anzahl voller Paletten (nicht die angefangene Palette dazu, siehe onClickPackages für die Begründung,
---warum "Alles" ein eigener, per +/- nicht erreichbarer Eintrag ist statt einfach das Ende des normalen Bereichs).
function RevampStorageDialog:onClickMax()
	self:updateAmount(math.huge)
end

---Setzt die gewählte Menge auf 0 zurück.
function RevampStorageDialog:onClickNix()
	self.selectedAmount = 0
	self.amountElement:setState(self.selectedAmount, true)
end

---Wählt den kompletten Lagerbestand inklusive der angefangenen (nicht vollen) letzten Palette - bei glatter Teilung (kein Rest) identisch zu onClickMax.
function RevampStorageDialog:onClickAlles()
	if self.hasRemainder then
		self.selectedAmount = self.fullPalletCount + 2
		self.amountElement:setState(self.selectedAmount, true)
	else
		self:onClickMax()
	end
end

---Wechselt den gewählten FillType und aktualisiert die davon abhängige Paketliste.
---@param state number 1-basierter Index in self.options
function RevampStorageDialog:onClickFillType(state)
	local i = 1
	for _, objectInfo in ipairs(self.options) do
		if i == state then
			self.selectedFillType = objectInfo.fillTypeIndex
			self.selectedOption = objectInfo
			self.fillTypeIcon:setImageFilename(objectInfo.fillTypeIcon)
			break
		end
		i = i + 1
	end

	self:setFillTypePackages()
end

---Wechselt das gewählte Verpackungspaket (Palette/Ballengröße) und baut die Mengen-Textliste des Reglers neu auf.
---+1/+10/Max erreichen bewusst nur volle Paletten (self.maxUnloadAmount = fullPalletCount, nicht die angefangene Palette mit dazu) -
---die angefangene Palette (Rest, der keine volle Palette ergibt) ist nur über den eigenen "Alles"-Eintrag erreichbar, siehe onClickOk/onClickAlles.
---Vermeidet, dass man beim Hochzählen "aus Versehen" auch die angefangene Palette mit rausnimmt.
---@param state number 1-basierter Index in self.selectedOption.packages
function RevampStorageDialog:onClickPackages(state)
	self.selectedPackage = state
	local selectedPackage = self.selectedOption.packages[self.selectedPackage]

	self.modIcon:setImageFilename(selectedPackage.modIcon)
	-- "wrapped" (Ballen nur in Folie) wird pro Paket geprüft, nicht nur beim FillType-Wechsel - bei
	-- einem FillType mit sowohl Ballen als auch Paletten soll der Farb-Button nur sichtbar sein, wenn
	-- das aktuell gewählte Paket tatsächlich eingefoliert wird.
	self.changeColorButton:setVisible(selectedPackage.wrapped == true)

	-- selectedPackage.capacity ist 0 bei den Pseudo-Paketen ("Produktion verwalten"/"Lager ist leer") -
	-- Division vermeiden, für die wird ohnehin keine Menge gebraucht (onClickOk geht dort direkt in
	-- self.spawnTarget:openMenu()).
	local fullPalletCount = 0
	local hasRemainder = false
	if selectedPackage.capacity > 0 then
		fullPalletCount = math.floor(self.selectedOption.fillLevel / selectedPackage.capacity)
		-- Manche Verpackungen begrenzen zusätzlich, wie viele auf einmal herauskommen dürfen (Stammholz). Bei allen anderen entspricht max ohnehin dem Bestand.
		fullPalletCount = math.min(fullPalletCount, selectedPackage.max)
		-- Eine angefangene Palette ergibt Sinn, ein angefangener Stamm nicht - solche Verpackungen bekommen keinen "Alles"-Eintrag.
		hasRemainder = not selectedPackage.noRemainder and (self.selectedOption.fillLevel - fullPalletCount * selectedPackage.capacity) >= 1
	end

	local amountTexts = {}
	if self.selectedOption.openmenu == nil then
		for i = 0, fullPalletCount do
			table.insert(amountTexts, string.format("%d / %d", i, fullPalletCount) .. " (" .. g_i18n:formatVolume(i * selectedPackage.capacity, 0, self.selectedOption.unitShort) .. ")")
		end
		if hasRemainder then
			table.insert(amountTexts, g_i18n:getText("revamp_storageAll") .. " (" .. g_i18n:formatVolume(self.selectedOption.fillLevel, 0, self.selectedOption.unitShort) .. ")")
		end
	end

	self.fullPalletCount = fullPalletCount
	self.hasRemainder = hasRemainder
	self.maxUnloadAmount = fullPalletCount
	self.amountElement:setTexts(amountTexts)
	self.selectedAmount = 0
	self.amountElement:setState(self.selectedAmount, true)
end

---Merkt sich den aktuellen Regler-Zustand (Klick/Ziehen direkt auf dem OptionSlider).
---@param state number Neuer Reglerzustand
function RevampStorageDialog:onClickAmount(state)
	self.selectedAmount = state
end

---Setzt den Dialogtitel und merkt ihn für spätere Zugriffe zusätzlich am Objekt.
---@param title string Neuer Dialogtitel
function RevampStorageDialog:setTitle(title)
	RevampStorageDialog:superClass().setTitle(self, title)
	self.dialogTitle = title
end

---Befüllt die FillType-Auswahl mit den übergebenen Optionen und wählt die erste aus.
---@param options table Auswahlbare FillType-Einträge inkl. ihrer Verpackungsoptionen
function RevampStorageDialog:setFillTypes(options)
	self.options = options
	local objectInfoTable = {}

	self.selectedFillType = nil
	for _, objectInfo in ipairs(options) do
		table.insert(objectInfoTable, objectInfo.title)
		if self.selectedFillType == nil then
			self.selectedFillType = objectInfo.fillTypeIndex
			self.selectedOption = objectInfo
			self.fillTypeIcon:setImageFilename(objectInfo.fillTypeIcon)
		end
	end

	self.fillTypeElement:setTexts(objectInfoTable)
	self.fillTypeElement:setState(1, true)
	self:setFillTypePackages()
end

---Befüllt die Hof-Auswahl und wählt standardmäßig die eigene Farm.
---@param farmList table Liste auswählbarer Farmen
function RevampStorageDialog:setFarmList(farmList)
	self.farmList = farmList
	local state = 1
	local objectInfoTable = {}
	for id, farm in ipairs(farmList) do
		table.insert(objectInfoTable, farm.name)
		if g_localPlayer:getFarmId() == farm.farmId then
			state = id
		end
	end

	local color = Farm.COLORS[1]
	if not g_currentMission.missionDynamicInfo.isMultiplayer then
		color = Farm.COLOR_SINGLEPLAYER
		self.farmIcon:setImageFilename(Revamp.emptyIcon)
	end

	self.farmIDElement:setTexts(objectInfoTable)
	self.farmIDElement.textElement:setTextColor(color[1], color[2], color[3], color[4])
	self.farmIDElement:setState(state, true)
end

---Wechselt die gewählte Empfänger-Farm und aktualisiert Farbe/Icon der Anzeige entsprechend.
---@param state number 1-basierter Index in self.farmList
function RevampStorageDialog:onClickIDElement(state)
	self.selectedFarm = state
	local selectedFarm = self.farmList[self.selectedFarm]
	local color = Farm.COLORS[selectedFarm.color]
	if not g_currentMission.missionDynamicInfo.isMultiplayer then
		color = Farm.COLOR_SINGLEPLAYER
		self.farmIcon:setImageFilename(Revamp.emptyIcon)
	else
		self.farmIcon:setImageSlice(nil, Farm.ICON_SLICE_IDS[selectedFarm.color])
	end
	self.farmIDElement.textElement:setTextColor(color[1], color[2], color[3], color[4])
end

---Befüllt die Paket-Auswahl des aktuell gewählten FillTypes und wählt das erste Paket aus.
function RevampStorageDialog:setFillTypePackages()
	local objectInfoTable = {}
	for _, objectInfo in ipairs(self.selectedOption.packages) do
		table.insert(objectInfoTable, objectInfo.title)
	end

	self.fillTypePackageElement:setTexts(objectInfoTable)
	self.fillTypePackageElement:setState(1, true) -- löst onClickPackages(1) aus, setzt maxUnloadAmount/changeColorButton korrekt für Paket 1
end

---Verringert die gewählte Menge um eine Palette/einen Ballen.
function RevampStorageDialog:onClickLeft1()
	self:updateAmount(-1)
end

---Verringert die gewählte Menge um 10 Paletten/Ballen.
function RevampStorageDialog:onClickLeft10()
	self:updateAmount(-10)
end

---Erhöht die gewählte Menge um eine Palette/einen Ballen.
function RevampStorageDialog:onClickRight1()
	self:updateAmount(1)
end

---Erhöht die gewählte Menge um 10 Paletten/Ballen.
function RevampStorageDialog:onClickRight10()
	self:updateAmount(10)
end

---Leerer onCreate-Handler für die Button-Gruppen (-1/-10/+1/+10/Max/Nix/Alles) - die GUI-XML verlangt onCreate an jedem GuiElement-Wrapper, hier gibt es aber nichts zu initialisieren.
---@diagnostic disable-line: unused-local
function RevampStorageDialog:onCreateButten()
end

---Verändert die gewählte Menge um einen Palettenschritt und klemmt sie auf den gültigen Bereich (0 bis maxUnloadAmount volle Paletten, die angefangene Palette bleibt onClickAlles vorbehalten).
---@param amount number Schrittweite (positiv oder negativ, math.huge für "auf Maximum springen")
function RevampStorageDialog:updateAmount(amount)
	local oldAmount = self.amountElement:getState()
	local newAmount = oldAmount + amount
	if oldAmount == 0 then
		newAmount = newAmount + 1
	end
	if newAmount > self.maxUnloadAmount + 1 then
		newAmount = self.maxUnloadAmount + 1
	end

	self.selectedAmount = newAmount
	self.amountElement:setState(self.selectedAmount, true)
end

---Öffnet den Farbwähler für einfoliert spawnende Ballen (nur sichtbar/klickbar, wenn das Mod FS25_unlimitedColorConfigurations mehr als eine Farbe zulässt oder Vanillas Standardfarben reichen).
function RevampStorageDialog:onClickChangeColor()
	if #self.colors > 1 then
		local unlimited = g_modIsLoaded.FS25_unlimitedColorConfigurations == true
		local currentColor = self.currentColorIndex == nil and self.selectedColor or nil
		ColorPickerDialog.show(self.setFoilColor, self, nil, self.colors, self.currentColorIndex, "calibratedMatPaint", currentColor, unlimited, nil, false)
	end
end

---Callback des Farbwählers - initialisiert beim ersten Aufruf die Standardfarbpalette (plus modeigene Farben, falls FS25_unlimitedColorConfigurations geladen ist) und übernimmt die Auswahl.
---@param selectedIndex? number Index in self.colors, wenn eine Standardfarbe gewählt wurde
---@param empty? any Von ColorPickerDialog durchgereicht, hier ungenutzt
---@param selectedColor? table Freie Farbwahl (customColor), wenn FS25_unlimitedColorConfigurations aktiv ist
---@diagnostic disable-line: unused-local
function RevampStorageDialog:setFoilColor(selectedIndex, empty, selectedColor)
	if self.colors == nil then
		self.colors = {
			{name = g_i18n:getText("ui_colorWhite"), color = {0.8500, 0.8500, 0.8500}},
			{name = g_i18n:getText("ui_colorBlack"), color = {0.0500, 0.0500, 0.0500}},
			{name = g_i18n:getText("ui_colorPink"),  color = {0.6662, 0.3839, 0.5481}},
			{name = g_i18n:getText("ui_colorGreen"), color = {0.3910, 0.5210, 0.3660}},
			{name = g_i18n:getText("ui_colorBlue"),  color = {0.1845, 0.5520, 0.5972}}
		}

		if g_modIsLoaded.FS25_unlimitedColorConfigurations then
			for _, configuration in pairs(PlaceableConfigurationItemColor.DEFAULT_COLORS) do
				local name, color = g_vehicleMaterialManager:getMaterialTemplateColorAndTitleByName(configuration)
				if name ~= nil then
					table.insert(self.colors, {name = color, color = name})
				end
			end
		end
	end

	if selectedColor ~= nil then
		self.selectedColor = selectedColor.customColor
		self.currentColorIndex = nil
	elseif selectedIndex ~= nil then
		self.currentColorIndex = selectedIndex
		self.selectedColor = self.colors[self.currentColorIndex].color
	end

	if self.selectedColor ~= nil then
		self.changeColorButtonImage:setImageColor(nil, self.selectedColor[1], self.selectedColor[2], self.selectedColor[3], 1)
	end
end
