-- Ticket #8: Rezept-Anzeige für Mix-Gruppen.
--
-- Laut Architektur.md gehört die Anzeige einer Funktion zum Bau der Funktion selbst statt in ein
-- eigenes, späteres Ticket. Vanilla zeigt Rezept-Inputs als flache Liste (ein Icon+Menge+Name pro
-- Input, ProductionFrame.xml "recipeItemTemplate"), ohne jedes Konzept von Mix-Gruppen. Diese
-- Datei baut nur den Input-Teil der Rezeptzeile (cell.name == "recipeCell") neu auf: pro
-- Mix-Gruppe (input.mix in 1..97) eine Überschriftzeile + die zugehörigen Zutaten-Zeilen; nicht
-- gruppierte Zutaten (mix=0) bleiben unverändert darunter stehen.
--
-- Der alternierende Hintergrund pro Gruppen-Block (siehe Plan/Absprache mit Achim) ist in diesem
-- Durchgang bewusst noch nicht umgesetzt: ein erster Versuch über eine eigene, manuell
-- positionierte BoxLayoutElement-Wrapper-Konstruktion (nach Vorbild des unfertigen FS25-WIP) blieb
-- unsichtbar, vermutlich weil das GUI-Element-Verhalten dabei falsch angenommen wurde. Diese
-- Fassung nutzt nur die im Projekt bereits nachweislich funktionierende Technik (direktes Klonen
-- von recipeItemTemplate in inputLayout, dessen eigener Auto-Flow positioniert). Hintergrundfarbe
-- pro Gruppe ist ein Folgeschritt, sobald die reine Struktur bestätigt sichtbar ist.
--
-- Ausdrücklich nicht Teil dieses Tickets: ein eigener Block für Booster/Master-Booster
-- (input.mix == Revamp.MIX_BOOST/MIX_MASTER) – die Backend-Auswertung dafür kommt erst mit #9,
-- vorher gibt es keinen aktiv/inaktiv-Zustand zum Anzeigen. Solche Inputs laufen hier wie mix=0
-- einfach unverändert mit durch. outputLayout/arrowLayout werden nicht angefasst.
--
-- Wichtig: welche einzelne Zutat einer Mix-Gruppe gerade aktiv verbraucht wird, wird bewusst
-- NICHT markiert (mit Achim abgestimmt) – das ergibt sich für den Spieler aus dem mixMode-Hinweis
-- im Rezept-Titel plus den ohnehin sichtbaren Füllständen. Nur die Gesamt-Erfüllbarkeit der
-- Gruppe wird farblich markiert (weiß=genug, rot=Gruppe komplett leer).

Revamp.RECIPE_ITEM_HEIGHT = 35

function Revamp.getProductionMixGroups(production)
	local groups = {}
	local order = {}
	for _, input in ipairs(production.inputs) do
		-- input.mix ist nur bei echten ProductionPoint-Rezepten gesetzt (unser Loader in
		-- revamp_production.lua). Die "Factory"-Spezialisierung (PlaceableFactory.lua, eigene
		-- Klasse, z.B. Sägewerk-Placeable) baut ihre eigenen Production-Objekte mit anderer
		-- Struktur (.fillType statt .type) und läuft nie durch unseren Loader - dort bleibt
		-- input.mix nil. Solche Inputs hier einfach wie "keine Mix-Gruppe" behandeln.
		if input.mix ~= nil and input.mix ~= 0 and input.mix ~= Revamp.MIX_BOOST and input.mix ~= Revamp.MIX_MASTER then
			if groups[input.mix] == nil then
				groups[input.mix] = {}
				table.insert(order, input.mix)
			end
			table.insert(groups[input.mix], input)
		end
	end
	table.sort(order)
	return groups, order
end

function Revamp.getMixModeL10nKey(mixMode)
	if mixMode == "DESC" then
		return "revamp_ui_production_mixModeDesc"
	elseif mixMode == "MOST" then
		return "revamp_ui_production_mixModeMost"
	elseif mixMode == "LEAST" then
		return "revamp_ui_production_mixModeLeast"
	end
	return "revamp_ui_production_mixModeAsc"
end

Revamp.RECIPE_TITLE_PREFIX = nil

function Revamp.getTitleForSectionHeader(self, superFunc, list, section)
	local title = superFunc(self, list, section)
	if list == self.detailsList then
		Revamp.RECIPE_TITLE_PREFIX = Revamp.RECIPE_TITLE_PREFIX or (g_i18n:getText("ui_productions_recipe") .. ":")
		if title ~= nil and title:sub(1, #Revamp.RECIPE_TITLE_PREFIX) == Revamp.RECIPE_TITLE_PREFIX then
			local production = self:getSelectedProduction()
			if production ~= nil then
				local _, order = Revamp.getProductionMixGroups(production)
				if #order > 0 then
					title = title .. " (" .. g_i18n:getText(Revamp.getMixModeL10nKey(production.mixMode)) .. ")"
				end
			end
		end
	end
	return title
end

InGameMenuProductionFrame.getTitleForSectionHeader = Utils.overwrittenFunction(InGameMenuProductionFrame.getTitleForSectionHeader, Revamp.getTitleForSectionHeader)

function Revamp.clearRecipeInputElements(inputLayout)
	-- Anders als Revamp.removeRevampElements: hier werden ALLE Kind-Elemente gelöscht, auch die
	-- von Vanilla selbst geklonten (unmarkierten) Zeilen, weil wir den kompletten Input-Bereich
	-- durch unsere eigene, gruppierte Darstellung ersetzen.
	for i = #inputLayout.elements, 1, -1 do
		inputLayout.elements[i]:delete()
	end
end

function Revamp.addRecipeItemRow(parent, input, isSatisfied)
	local row = Revamp.recipeItemTemplate:clone(parent)
	row.revampLine = true
	local fillType = g_fillTypeManager:getFillTypeByIndex(input.type)
	row:getDescendantByName("icon"):setImageFilename(fillType.hudOverlayFilename)
	local amount = row:getDescendantByName("amount")
	amount:setText(g_i18n:formatNumber(input.amount, 2))
	local name = row:getDescendantByName("name")
	name:setText("x " .. fillType.title)
	if not isSatisfied then
		name:setTextColor(1, 0, 0, 1)
		amount:setTextColor(1, 0, 0, 1)
	end
	return row
end

function Revamp.addRecipeGroupHeaderRow(parent, mixGroupIndex, isSatisfied)
	local row = Revamp.recipeItemTemplate:clone(parent)
	row.revampLine = true
	row:getDescendantByName("icon"):delete()
	row:getDescendantByName("amount"):delete()
	local name = row:getDescendantByName("name")
	name:applyProfile("Revamp_recipeGroupHeaderName") -- volle Zeilenbreite statt nur des rechten Teils (kein Icon/Menge in dieser Zeile)
	name.textBold = true
	name:setText(g_i18n:getText("revamp_ui_production_mixGroup"):format(mixGroupIndex))
	if not isSatisfied then
		name:setTextColor(1, 0, 0, 1)
	end
	return row
end

function Revamp.updateRecipeCellMixGroups(self, cell)
	local production = self:getSelectedProduction()
	if production == nil then
		return
	end

	local groups, order = Revamp.getProductionMixGroups(production)
	if #order == 0 then
		return -- keine Mix-Gruppe in diesem Rezept, Vanilla-Darstellung von superFunc bleibt unangetastet
	end

	-- Kein eigener Wrapper/Hintergrund-Block in diesem Durchgang (siehe Kommentar am Dateikopf) -
	-- jede Zeile (Überschrift oder Zutat) wird direkt in inputLayout geklont, exakt dieselbe
	-- Technik, mit der Vanilla selbst die Output-Seite (arrowLayout/outputLayout) füllt. Das lässt
	-- inputLayouts eigenen vertikalen Auto-Flow die Positionierung übernehmen, statt sie selbst
	-- nachzurechnen.
	local inputLayout = cell:getAttribute("inputLayout")
	Revamp.clearRecipeInputElements(inputLayout)

	for _, mixGroupIndex in ipairs(order) do
		local isSatisfied = production.mixGroupSatisfied ~= nil and production.mixGroupSatisfied[mixGroupIndex]
		Revamp.addRecipeGroupHeaderRow(inputLayout, mixGroupIndex, isSatisfied)

		for _, input in ipairs(groups[mixGroupIndex]) do
			Revamp.addRecipeItemRow(inputLayout, input, isSatisfied)
		end
	end

	-- Nicht gruppierte Zutaten (mix=0) sowie Booster/Master-Booster (#9, hier noch unstyled)
	-- unverändert im bisherigen Stil darunter anhängen
	for _, input in ipairs(production.inputs) do
		if input.mix == 0 or input.mix == Revamp.MIX_BOOST or input.mix == Revamp.MIX_MASTER then
			Revamp.addRecipeItemRow(inputLayout, input, true)
		end
	end

	inputLayout:invalidateLayout()

	-- SmoothListElement:buildSectionInfo() (Vanilla) klemmt den aktuellen Scroll-Offset auf die neu
	-- berechnete Gesamthöhe der Liste - bei jeder Neuberechnung (z.B. beim periodischen 5s-Refresh
	-- des Menüs) sprang der Scrollbalken dadurch zurück. Nur neu berechnen, wenn sich die Höhe
	-- tatsächlich geändert hat, und den Scroll-Wert danach explizit wiederherstellen.
	if inputLayout.size[2] ~= cell.size[2] then
		local viewOffset = self.detailsList.viewOffset
		local targetViewOffset = self.detailsList.targetViewOffset
		Revamp.DebugText("updateRecipeCellMixGroups(): %s Zellgroesse %s -> %s, viewOffset vorher %s", production.id, tostring(cell.size[2]), tostring(inputLayout.size[2]), tostring(viewOffset))
		cell:setSize(cell.size[1], inputLayout.size[2])
		self.detailsList.cellDatabase.recipeCell.size[2] = cell.size[2]
		cell:updateAnchorDeltas(true)
		self.detailsList:buildSectionInfo()
		Revamp.DebugText("updateRecipeCellMixGroups(): %s viewOffset nach buildSectionInfo %s, stelle %s wieder her", production.id, tostring(self.detailsList.viewOffset), tostring(viewOffset))
		self.detailsList.viewOffset = viewOffset
		self.detailsList.targetViewOffset = targetViewOffset
	end
end

function Revamp.getIsSharedThroughputCapacityUniform(productionPoint)
	local firstValue = nil
	for _, production in ipairs(productionPoint.sortedProductions) do
		if firstValue == nil then
			firstValue = production.sharedThroughputCapacity
		elseif production.sharedThroughputCapacity ~= firstValue then
			return false
		end
	end
	return true
end

function Revamp.updateProductsListRow(self, cell, production, productionPoint)
	Revamp.removeRevampElements(cell)

	if Revamp.getIsSharedThroughputCapacityUniform(productionPoint) then
		return -- alle Rezeptlinien gleich, keine Ausnahme zu zeigen
	end

	local icon = BitmapElement.new()
	cell:addElement(icon)
	icon:applyProfile("Revamp_pointsListSharedIcon")
	icon.revampLine = true
	icon:setVisible(true)
	if production.sharedThroughputCapacity then
		icon:setImageFilename(Revamp.icons.sharedThroughputCapacityTrue)
	else
		icon:setImageFilename(Revamp.icons.sharedThroughputCapacityFalse)
	end
	icon:updateAnchorDeltas()
	icon:updateAbsolutePosition()
	icon.getIsSelected = function()
		-- upvalues: (copy) cell
		return cell:getIsSelected()
	end
end

function Revamp.populateRecipeCellForItemInSection(self, superFunc, list, section, index, cell)
	superFunc(self, list, section, index, cell)

	if list == self.productsList then
		local _, productionPoint = self:getSelectedProduction()
		local production = productionPoint.sortedProductions[index]
		Revamp.updateProductsListRow(self, cell, production, productionPoint)
	elseif list == self.detailsList and cell.name == "recipeCell" then
		if Revamp.recipeItemTemplate == nil then
			Revamp.recipeItemTemplate = self.recipeItemTemplate
		end
		Revamp.updateRecipeCellMixGroups(self, cell)
	end
end

InGameMenuProductionFrame.populateCellForItemInSection = Utils.overwrittenFunction(InGameMenuProductionFrame.populateCellForItemInSection, Revamp.populateRecipeCellForItemInSection)
