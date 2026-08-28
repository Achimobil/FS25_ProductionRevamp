-- Mengen-Dialog für die Obergrenze eines Verteilziels (siehe revamp_distribution.lua).
-- Bedienung wie im Kaufen-Dialog: Regler mit Sprungtasten, dazu "Nix" und "Voll" an den Enden.
--
-- Der Regler läuft in Hundert-Liter-Schritten statt literweise: eine Obergrenze wird in groben Größenordnungen gewählt, und ein
-- Eintrag je Liter wären bei einem großen Ziellager mehrere hunderttausend Texte, die bei jedem Öffnen des Dialogs neu entstünden.
--
-- Der letzte Schritt ist die volle Kapazität des Ziellagers und steht für "keine Obergrenze" - mehr als voll kann ein Lager nicht werden,
-- eine Obergrenze in Höhe der Kapazität wäre also nur eine Zahl, die dasselbe bedeutet und bei jeder Lagererweiterung nachgezogen werden müsste.

RevampDistributionLimitDialog = {}
local RevampDistributionLimitDialog_mt = Class(RevampDistributionLimitDialog, YesNoDialog)

-- Schrittweite des Reglers in Litern. Passt zu den Sprungtasten: ein Schritt entspricht -100/+100, zehn Schritte -1000/+1000.
RevampDistributionLimitDialog.STEP_SIZE = 100

---Lädt die Dialog-XML und registriert die Dialoginstanz beim GUI-System.
function RevampDistributionLimitDialog.register()
	local dialog = RevampDistributionLimitDialog.new()
	local path = Utils.getFilename("gui/revamp_distributionLimitDialog.xml", g_currentModDirectory)
	g_gui:loadGui(path, "RevampDistributionLimitDialog", dialog)
	RevampDistributionLimitDialog.INSTANCE = dialog
end

---Öffnet den Dialog für die Obergrenze eines einzelnen Verteilziels.
---@param productionPoint table Verteilende ProductionPoint-Instanz
---@param fillTypeIndex number FillType-Index des Erzeugnisses
---@param target table Ziel-Eintrag aus Revamp.getDistributionSections
function RevampDistributionLimitDialog.show(productionPoint, fillTypeIndex, target)
	if RevampDistributionLimitDialog.INSTANCE == nil then
		return
	end

	local dialog = RevampDistributionLimitDialog.INSTANCE
	dialog.productionPoint = productionPoint
	dialog.fillTypeIndex = fillTypeIndex
	dialog.targetPoint = target.productionPoint
	dialog.level = target.level
	dialog.maxLimit = target.productionPoint:getCapacity(fillTypeIndex)

	local fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
	dialog.unitShort = fillTypeDesc.unitShort
	if dialog.unitShort == "" then
		dialog.unitShort = g_i18n:getText("unit_literShort")
	end

	dialog:setTitle(target.productionPoint:getName())
	dialog:setText(g_i18n:getText("revamp_descDistributionLimit"))
	dialog.fillTypeIcon:setImageFilename(fillTypeDesc.hudOverlayFilename)
	dialog.fillTypeText:setText(fillTypeDesc.title)
	dialog.targetCapacityText:setText(string.format(g_i18n:getText("revamp_distributionTargetCapacity"), g_i18n:formatVolume(dialog.maxLimit, 0, dialog.unitShort)))

	dialog:setLimit(target.limit)

	g_gui:showDialog("RevampDistributionLimitDialog")
end

---Erzeugt eine neue Dialoginstanz.
---@param target? table Ziel-Objekt für die GUI-Elemente (siehe YesNoDialog.new)
---@param custom_mt? table Metatable, falls von einer abgeleiteten Klasse aufgerufen
---@return table self Neue RevampDistributionLimitDialog-Instanz
function RevampDistributionLimitDialog.new(target, custom_mt)
	return YesNoDialog.new(target, custom_mt or RevampDistributionLimitDialog_mt)
end

---Setzt beim Öffnen den Fokus auf den Mengenregler.
function RevampDistributionLimitDialog:onOpen()
	RevampDistributionLimitDialog:superClass().onOpen(self)
	FocusManager:setFocus(self.amountElement)
end

---Setzt den Dialogtitel.
---@param title string Neuer Dialogtitel
function RevampDistributionLimitDialog:setTitle(title)
	RevampDistributionLimitDialog:superClass().setTitle(self, title)
	self.dialogTitle = title
end

---Baut die Textliste des Reglers neu auf und stellt ihn auf die bisher eingestellte Obergrenze.
---@param limit? number Bisherige Obergrenze in Litern, nil wenn bisher keine eingestellt war
function RevampDistributionLimitDialog:setLimit(limit)
	self.numSteps = math.ceil(self.maxLimit / RevampDistributionLimitDialog.STEP_SIZE)

	local texts = {}
	for step = 0, self.numSteps do
		if step == self.numSteps then
			table.insert(texts, g_i18n:getText("revamp_distributionNoLimit"))
		else
			table.insert(texts, g_i18n:formatVolume(step * RevampDistributionLimitDialog.STEP_SIZE, 0, self.unitShort))
		end
	end
	self.amountElement:setTexts(texts)

	-- Der Regler zählt ab 1, der erste Eintrag ist die Null. Ohne eingestellte Obergrenze steht er ganz rechts auf "keine Obergrenze".
	local state = self.numSteps + 1
	if limit ~= nil then
		state = math.clamp(math.floor(limit / RevampDistributionLimitDialog.STEP_SIZE) + 1, 1, self.numSteps + 1)
	end
	self.amountElement:setState(state, true)
end

---Merkt sich den Reglerzustand beim Klicken oder Ziehen direkt auf dem Regler.
---@param state number Neuer Reglerzustand
function RevampDistributionLimitDialog:onClickAmount(state) ---@diagnostic disable-line: unused-local
end

---Verschiebt den Regler um eine Anzahl Schritte und klemmt ihn auf den gültigen Bereich.
---@param steps number Anzahl Schritte, positiv oder negativ
function RevampDistributionLimitDialog:moveSteps(steps)
	self.amountElement:setState(math.clamp(self.amountElement:getState() + steps, 1, self.numSteps + 1), true)
end

---Verringert die Obergrenze um 100 Liter.
function RevampDistributionLimitDialog:onClickLeft100()
	self:moveSteps(-1)
end

---Verringert die Obergrenze um 1000 Liter.
function RevampDistributionLimitDialog:onClickLeft1000()
	self:moveSteps(-10)
end

---Erhöht die Obergrenze um 100 Liter.
function RevampDistributionLimitDialog:onClickRight100()
	self:moveSteps(1)
end

---Erhöht die Obergrenze um 1000 Liter.
function RevampDistributionLimitDialog:onClickRight1000()
	self:moveSteps(10)
end

---Setzt die Obergrenze auf 0 - das Ziel bekommt damit nichts mehr geliefert.
function RevampDistributionLimitDialog:onClickNull()
	self.amountElement:setState(1, true)
end

---Nimmt die Obergrenze ganz zurück.
function RevampDistributionLimitDialog:onClickFull()
	self.amountElement:setState(self.numSteps + 1, true)
end

---Leerer onCreate-Handler für die Button-Gruppen - die GUI-XML verlangt onCreate an jedem GuiElement-Wrapper, hier gibt es aber nichts zu initialisieren.
function RevampDistributionLimitDialog:onCreateButten()
end

---Übernimmt die eingestellte Obergrenze und schließt den Dialog.
function RevampDistributionLimitDialog:onClickOk()
	local state = self.amountElement:getState()
	local limit = nil
	if state <= self.numSteps then
		limit = (state - 1) * RevampDistributionLimitDialog.STEP_SIZE
	end

	self.productionPoint:setDistributionTarget(self.fillTypeIndex, self.targetPoint, self.level, limit)
	self:close()

	-- Der Verwalten-Dialog bleibt im Hintergrund offen und zeigte sonst weiter die Obergrenze von vorher.
	if RevampManageDialog.INSTANCE ~= nil then
		RevampManageDialog.INSTANCE:updateDistributionRows()
	end
end

---Schließt den Dialog, ohne die Obergrenze zu ändern.
function RevampDistributionLimitDialog:onClickBack()
	self:close()
end
