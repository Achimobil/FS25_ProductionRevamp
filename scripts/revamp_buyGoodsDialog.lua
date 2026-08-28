-- Mengen-Dialog für Kaufen/Verkaufen (siehe revamp_manageDialog.lua), byte-nah portiert aus dem bereits
-- veröffentlichten FS25_ProductionSupplyTrader (productionSupplyTrader_buyGoodsDialog.lua).

RevampBuyGoodsDialog = {}
local RevampBuyGoodsDialog_mt = Class(RevampBuyGoodsDialog, YesNoDialog)

---Lädt die Dialog-XML und registriert die Dialoginstanz beim GUI-System.
function RevampBuyGoodsDialog.register()
	local dialog = RevampBuyGoodsDialog.new()
	local path = Utils.getFilename("gui/revamp_buyGoodsDialog.xml", g_currentModDirectory)
	g_gui:loadGui(path, "RevampBuyGoodsDialog", dialog)
	RevampBuyGoodsDialog.INSTANCE = dialog
end

---Öffnet den Kaufen/Verkaufen-Dialog für einen einzelnen FillType eines Produktionspunkts.
---@param productionPoint table ProductionPoint-Instanz
---@param title string Dialogtitel (Name des Produktionspunkts)
---@param fillType table Tabelle mit Feld fillTypeIndex (siehe RevampManageDialog:onClickBuy/:onClickSell)
---@param buySell number 1 = kaufen, alles andere = verkaufen (Konvention aus PST übernommen)
function RevampBuyGoodsDialog.show(productionPoint, title, fillType, buySell)
	if RevampBuyGoodsDialog.INSTANCE ~= nil then
		local dialog = RevampBuyGoodsDialog.INSTANCE
		dialog.productionPoint = productionPoint
		dialog.fillTypeIndex = fillType.fillTypeIndex
		local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(dialog.fillTypeIndex)

		if buySell == 1 then
			dialog.mode = true
			dialog:setText(g_i18n:getText("revamp_descBuy"))
			dialog.pricePerLiter = fillTypeDesc.pricePerLiter * 2 * EconomyManager.getPriceMultiplier()
			dialog.max = productionPoint.storage:getFreeCapacity(dialog.fillTypeIndex)
		else
			dialog.mode = false
			dialog:setText(g_i18n:getText("revamp_descSell"))
			dialog.pricePerLiter = fillTypeDesc.pricePerLiter * EconomyManager.getPriceMultiplier() * Revamp.settings.directSellingPriceFactor
			dialog.max = productionPoint.storage:getFillLevel(dialog.fillTypeIndex)
		end
		dialog:setTitle(title)

		dialog.fillTypeIcon:setImageFilename(fillTypeDesc.hudOverlayFilename)
		dialog.unitShort = fillTypeDesc.unitShort
		if dialog.unitShort == "" then
			dialog.unitShort = g_i18n:getText("unit_literShort")
		end

		dialog.fillTypeText:setText(fillTypeDesc.title)
		dialog.fillTypePrice:setText(g_i18n:formatMoney(math.round(dialog.pricePerLiter * 1000), 0) .. " / " .. g_i18n:formatVolume(1000, 0, dialog.unitShort))

		dialog:setLimit()

		g_gui:showDialog("RevampBuyGoodsDialog")
	end
end

---Erzeugt eine neue Dialoginstanz.
---@param target? table Ziel-Objekt für die GUI-Elemente (siehe YesNoDialog.new)
---@param custom_mt? table Metatable, falls von einer abgeleiteten Klasse aufgerufen
---@return table self Neue RevampBuyGoodsDialog-Instanz
function RevampBuyGoodsDialog.new(target, custom_mt)
	local self = YesNoDialog.new(target, custom_mt or RevampBuyGoodsDialog_mt)
	self.selectedAmount = 0
	return self
end

---Setzt beim Öffnen den Fokus auf den Mengenregler.
function RevampBuyGoodsDialog:onOpen()
	RevampBuyGoodsDialog:superClass().onOpen(self)
	FocusManager:setFocus(self.amountElement)
end

---Bestätigt die gewählte Menge und schickt das Kauf/Verkauf-Event an den Server.
function RevampBuyGoodsDialog:onClickOk()
	local amount = self.amountElement:getState() - 1
	Revamp_EventBuySell.sendEvent(self.productionPoint, self.fillTypeIndex, amount, self.mode)
	self:close()

	-- RevampManageDialog bleibt beim Öffnen dieses Dialogs im Hintergrund offen und hätte sonst weiter die Menge von vor dem Kauf/Verkauf angezeigt.
	if RevampManageDialog.INSTANCE ~= nil then
		RevampManageDialog.INSTANCE:updateRows()
	end
end

---Schließt den Dialog ohne zu kaufen/verkaufen.
function RevampBuyGoodsDialog:onClickBack()
	self:close()
end

---Baut die Mengen-Textliste des Reglers von 0 bis self.max neu auf (Menge inkl. Gesamtpreis je Schritt) und setzt die Auswahl auf 0 zurück.
function RevampBuyGoodsDialog:setLimit()
	local amountTexts = {}
	for i = 0, self.max do
		local price = math.round(self.pricePerLiter * i)
		table.insert(amountTexts, g_i18n:formatVolume(i, 0, self.unitShort) .. " - " .. g_i18n:formatMoney(price, 0))
	end

	self.amountElement:setTexts(amountTexts)
	self.selectedAmount = 0
	self.amountElement:setState(self.selectedAmount, true)
end

---Merkt sich den aktuellen Regler-Zustand (Klick/Ziehen direkt auf dem OptionSlider).
---@param state number Neuer Reglerzustand
function RevampBuyGoodsDialog:onClickAmount(state)
	self.selectedAmount = state
end

---Setzt den Dialogtitel.
---@param title string Neuer Dialogtitel
function RevampBuyGoodsDialog:setTitle(title)
	RevampBuyGoodsDialog:superClass().setTitle(self, title)
	self.dialogTitle = title
end

---Verringert die gewählte Menge um 100 Liter.
function RevampBuyGoodsDialog:onClickLeft100()
	self:updateAmount(-100)
end

---Verringert die gewählte Menge um 1000 Liter.
function RevampBuyGoodsDialog:onClickLeft1000()
	self:updateAmount(-1000)
end

---Erhöht die gewählte Menge um 100 Liter.
function RevampBuyGoodsDialog:onClickRight100()
	self:updateAmount(100)
end

---Erhöht die gewählte Menge um 1000 Liter.
function RevampBuyGoodsDialog:onClickRight1000()
	self:updateAmount(1000)
end

---Springt auf die maximale Menge (self.max).
function RevampBuyGoodsDialog:onClickMax()
	self:updateAmount(self.max + 1, true)
end

---Setzt die gewählte Menge auf 0 zurück.
function RevampBuyGoodsDialog:onClickNull()
	self:updateAmount(1, true)
end

---Leerer onCreate-Handler für die Button-Gruppen (-100/-1000/+100/+1000/Max/0) - die GUI-XML verlangt onCreate an jedem GuiElement-Wrapper, hier gibt es aber nichts zu initialisieren.
---@diagnostic disable-line: unused-local
function RevampBuyGoodsDialog:onCreateButten()
end

---Verändert die gewählte Menge um einen Schritt und klemmt sie auf den gültigen Bereich (0 bis self.max).
---@param amount number Schrittweite (positiv oder negativ), bzw. bei force=true die neue Menge direkt
---@param force? boolean true, wenn amount die neue Menge direkt vorgibt statt eine Schrittweite zu sein (Max/0-Buttons)
function RevampBuyGoodsDialog:updateAmount(amount, force)
	local oldAmount = self.amountElement:getState()
	local newAmount = oldAmount + amount
	if force == true then
		newAmount = amount
	else
		if oldAmount == 0 then
			newAmount = newAmount + 1
		end
		if newAmount > self.max + 1 then
			newAmount = self.max + 1
		end
	end

	self.selectedAmount = newAmount
	self.amountElement:setState(self.selectedAmount, true)
end
