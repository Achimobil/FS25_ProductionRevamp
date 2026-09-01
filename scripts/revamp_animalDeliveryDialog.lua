-- Liefer-Dialog am Tier-Trigger (siehe revamp_animals.lua): oben wird eine Tiergruppe aus dem Transporter gewählt, darunter die Anzahl.
-- Angezeigt wird immer, was diese Tiere der Produktionsstätte einbringen - einmal pro Tier und einmal für die gewählte Anzahl.
--
-- Eine Gruppe, die hier nicht abgegeben werden kann, bleibt trotzdem in der Auswahl stehen und nennt den Grund: sonst wäre für den Spieler
-- nicht erkennbar, warum von seinen drei Tiergruppen nur eine auftaucht.

RevampAnimalDeliveryDialog = {}
local RevampAnimalDeliveryDialog_mt = Class(RevampAnimalDeliveryDialog, YesNoDialog)

RevampAnimalDeliveryDialog.ICON_ACCEPTED = g_currentModDirectory .. "gui/revamp_animalAccepted.dds"
RevampAnimalDeliveryDialog.ICON_NOT_ACCEPTED = g_currentModDirectory .. "gui/revamp_animalNotAccepted.dds"

---Lädt die Dialog-XML und registriert die Dialoginstanz beim GUI-System.
function RevampAnimalDeliveryDialog.register()
	local dialog = RevampAnimalDeliveryDialog.new()
	local path = Utils.getFilename("gui/revamp_animalDeliveryDialog.xml", g_currentModDirectory)
	g_gui:loadGui(path, "RevampAnimalDeliveryDialog", dialog)
	RevampAnimalDeliveryDialog.INSTANCE = dialog
end

---Öffnet den Liefer-Dialog für den Transporter an einem Tier-Trigger.
---@param trigger table RevampAnimalTrigger-Instanz, an der abgegeben wird
---@param items table Tiergruppen im Transporter (siehe RevampAnimalTrigger:getDeliveryItems)
function RevampAnimalDeliveryDialog.show(trigger, items)
	if RevampAnimalDeliveryDialog.INSTANCE ~= nil then
		local dialog = RevampAnimalDeliveryDialog.INSTANCE
		dialog.trigger = trigger
		dialog:setItems(items)
		g_gui:showDialog("RevampAnimalDeliveryDialog")
	end
end

---Erzeugt eine neue Dialoginstanz.
---@param target? table Ziel-Objekt für die GUI-Elemente (siehe YesNoDialog.new)
---@param custom_mt? table Metatable, falls von einer abgeleiteten Klasse aufgerufen
---@return table self Neue RevampAnimalDeliveryDialog-Instanz
function RevampAnimalDeliveryDialog.new(target, custom_mt)
	local self = YesNoDialog.new(target, custom_mt or RevampAnimalDeliveryDialog_mt)
	self.items = {}
	self.selectedIndex = 1
	return self
end

---Setzt beim Öffnen den Fokus auf die Auswahl der Tiergruppe.
function RevampAnimalDeliveryDialog:onOpen()
	RevampAnimalDeliveryDialog:superClass().onOpen(self)
	FocusManager:setFocus(self.itemsElement)
end

---Übernimmt die Tiergruppen des Transporters in die Auswahl.
---@param items table Tiergruppen im Transporter
function RevampAnimalDeliveryDialog:setItems(items)
	self.items = items

	local titles = {}
	for _, item in ipairs(items) do
		table.insert(titles, item.title)
	end

	self.itemsElement:setTexts(titles)
	-- Beim Öffnen immer die erste Gruppe: welche Gruppe zuletzt gewählt war, sagt nach dem Abgeben nichts mehr über die neue Ladung aus.
	self.selectedIndex = 1
	self.itemsElement:setState(self.selectedIndex, true)
end

---Wechselt die gewählte Tiergruppe: Bild, Mengenauswahl und Mengenanzeige gehören alle zur Gruppe und werden mitgewechselt.
---@param state number Nummer der gewählten Gruppe
function RevampAnimalDeliveryDialog:onClickItems(state)
	self.selectedIndex = state

	local item = self.items[state]
	if item == nil then
		return
	end

	self.animalIcon:setImageFilename(item.imageFilename)
	self.acceptedIcon:setImageFilename(item.rejectText == nil and RevampAnimalDeliveryDialog.ICON_ACCEPTED or RevampAnimalDeliveryDialog.ICON_NOT_ACCEPTED)

	self:updateQuantities()
end

---Baut die Mengenauswahl für die gewählte Tiergruppe neu auf.
---Vorausgewählt ist immer die höchste Anzahl: wer an einem Schlachter vorbeifährt, will in der Regel die ganze Gruppe abgeben.
function RevampAnimalDeliveryDialog:updateQuantities()
	local item = self.items[self.selectedIndex]
	if item == nil then
		return
	end

	local quantities = {}
	for count = 1, item.maxAnimals do
		local text = count == 1 and g_i18n:getText("revamp_animalCountSingular") or g_i18n:getText("revamp_animalCount")
		table.insert(quantities, string.format(text, count))
	end

	local canDeliver = #quantities > 0
	self.yesButton:setDisabled(not canDeliver)
	self.quantityElement:setDisabled(not canDeliver)

	if not canDeliver then
		-- Statt einer leeren Auswahl steht der Ablehnungsgrund an der Stelle, an der sonst die Anzahl stünde.
		table.insert(quantities, item.rejectText or g_i18n:getText("revamp_animalNoSpace"))
	end

	self.quantityElement:setTexts(quantities)
	self.quantityElement:setState(#quantities, true)

	self:updateAmounts()
end

---Zeigt an, was die gewählte Anzahl Tiere der Produktionsstätte einbringt.
function RevampAnimalDeliveryDialog:updateAmounts()
	local item = self.items[self.selectedIndex]
	local fillType = item ~= nil and item.fillTypeIndex ~= nil and g_fillTypeManager:getFillTypeByIndex(item.fillTypeIndex) or nil

	if fillType == nil then
		self.amountPerAnimalText:setText("-")
		self.amountTotalText:setText("-")
		return
	end

	local unitShort = fillType.unitShort
	if unitShort == "" then
		unitShort = g_i18n:getText("unit_literShort")
	end

	local numAnimals = self.quantityElement:getState()
	self.amountPerAnimalText:setText(string.format("%s %s", g_i18n:formatVolume(item.amountPerAnimal, 0, unitShort), fillType.title))
	self.amountTotalText:setText(string.format("%s %s", g_i18n:formatVolume(item.amountPerAnimal * numAnimals, 0, unitShort), fillType.title))
end

---Aktualisiert die Mengenanzeige, wenn die Anzahl verändert wird.
---@param state number Neue Anzahl
function RevampAnimalDeliveryDialog:onClickQuantity(state) ---@diagnostic disable-line: unused-local
	self:updateAmounts()
end

---Gibt die gewählte Anzahl Tiere der gewählten Gruppe ab.
function RevampAnimalDeliveryDialog:onClickOk()
	local item = self.items[self.selectedIndex]

	if item == nil or item.maxAnimals < 1 then
		return
	end

	self.trigger:deliverAnimals(item.clusterId, self.quantityElement:getState())
	self:close()
end

---Schließt den Dialog, ohne Tiere abzugeben.
function RevampAnimalDeliveryDialog:onClickBack()
	self:close()
end
