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

-- Zwei Farben wie in der PRICES-Liste (fs25_pricesProductListItem: Grundfarbe fs25_colorGrey,
-- Wechselfarbe fs25_colorGreyDark_50) - genau der Mechanismus, den Vanilla selbst für
-- abwechselnde Listenzeilen benutzt.
Revamp.RECIPE_GROUP_COLORS = {
	{0.04231, 0.04231, 0.04231, 1}, -- fs25_colorGrey
	{0.02956, 0.02956, 0.02956, 0.5}, -- fs25_colorGreyDark_50
}

function Revamp.addRecipeRowBackground(row, color)
	-- BitmapElement.new() + applyProfile() rendert bei einem zur Laufzeit erzeugten Element
	-- nicht richtig (bestätigt per Test, wiederholt). Stattdessen ein bereits vorhandenes,
	-- nachweislich funktionierendes Bitmap-Element klonen (row hat durch recipeItemTemplate
	-- immer ein "icon") und zum Hintergrund umbauen, statt eins neu zu erzeugen.
	local background = row:getDescendantByName("icon"):clone(row)
	background.revampLine = true
	background.name = nil -- sonst kollidiert es mit getDescendantByName("icon") an anderer Stelle
	table.remove(row.elements) -- clone() hängt hinten an, für den Hintergrund muss es aber vorne (hinter Icon/Menge/Name) stehen
	table.insert(row.elements, 1, background)
	background:applyProfile("Revamp_recipeGroupBox")
	background:setImageColor(GuiOverlay.STATE_NORMAL, color[1], color[2], color[3], color[4])
	background:updateAnchorDeltas()
	background:updateAbsolutePosition()
end

function Revamp.addRecipeItemRow(parent, input, isSatisfied, groupColor)
	local row = Revamp.recipeItemTemplate:clone(parent)
	row.revampLine = true
	if groupColor ~= nil then
		Revamp.addRecipeRowBackground(row, groupColor)
	end
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

function Revamp.addRecipeGroupHeaderRow(parent, mixGroupIndex, isSatisfied, groupColor)
	local row = Revamp.recipeItemTemplate:clone(parent)
	row.revampLine = true
	if groupColor ~= nil then
		Revamp.addRecipeRowBackground(row, groupColor)
	end
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

	-- Hier nicht versuchen, den Neuaufbau bei "unveränderten" Daten zu überspringen: superFunc()
	-- baut inputLayout bei JEDEM Aufruf sowieso immer flach neu auf (unsere Gruppen-Struktur wird
	-- dabei gelöscht), bevor dieser Code hier überhaupt läuft - ein Überspringen lässt genau
	-- diesen flachen Vanilla-Zwischenstand stehen.

	-- Jede Zeile (Überschrift oder Zutat) wird direkt in inputLayout geklont, exakt dieselbe
	-- Technik, mit der Vanilla selbst die Output-Seite (arrowLayout/outputLayout) füllt. Das lässt
	-- inputLayouts eigenen vertikalen Auto-Flow die Positionierung übernehmen, statt sie selbst
	-- nachzurechnen. Ein farbiger Hintergrund pro Block kommt dabei nicht über einen eigenen
	-- Wrapper-Container (siehe gescheiterter erster Versuch, Memory-Notiz dazu), sondern als
	-- zusätzliches Bitmap-Kind-Element pro einzelner Zeile - sieht bei lückenlos aneinander
	-- stoßenden Zeilen wie ein durchgehender Block aus.
	local inputLayout = cell:getAttribute("inputLayout")
	Revamp.clearRecipeInputElements(inputLayout)

	for groupPosition, mixGroupIndex in ipairs(order) do
		local isSatisfied = production.mixGroupSatisfied ~= nil and production.mixGroupSatisfied[mixGroupIndex]
		local groupColor = Revamp.RECIPE_GROUP_COLORS[(groupPosition - 1) % #Revamp.RECIPE_GROUP_COLORS + 1]
		Revamp.addRecipeGroupHeaderRow(inputLayout, mixGroupIndex, isSatisfied, groupColor)

		for _, input in ipairs(groups[mixGroupIndex]) do
			Revamp.addRecipeItemRow(inputLayout, input, isSatisfied, groupColor)
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

	-- Größe/buildSectionInfo() hier NICHT mehr selbst sichern/wiederherstellen - superFunc() hat
	-- VOR diesem Code schon seine eigene (zu kleine, weil ohne Gruppen-Überschriften berechnete)
	-- Größe gesetzt und dabei bereits Vanillas eigenes buildSectionInfo() mit dieser zu kleinen
	-- Höhe aufgerufen. Das klemmt den echten Scroll-Wert schon, bevor dieser Code hier überhaupt
	-- anfängt - ein "vorher" ab hier zu sichern rettet also nur den bereits falschen Wert. Die
	-- eigentliche Sicherung/Wiederherstellung passiert jetzt eine Ebene höher, um superFunc()
	-- herum, siehe Revamp.populateRecipeCellForItemInSection.
	cell:setSize(cell.size[1], inputLayout.size[2])
	self.detailsList.cellDatabase.recipeCell.size[2] = cell.size[2]
	cell:updateAnchorDeltas(true)
	self.detailsList:buildSectionInfo()
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
	-- Der echte, vom Spieler gesetzte Scroll-Wert muss VOR superFunc() gesichert werden: superFunc
	-- berechnet für die Rezeptzelle selbst schon eine (zu kleine, weil ohne unsere Gruppen-
	-- Überschriften ermittelte) Höhe und ruft dabei bereits Vanillas eigenes buildSectionInfo()
	-- auf, das den aktuellen Scroll-Wert auf diese zu kleine Höhe klemmt - noch bevor unser Code
	-- überhaupt zum Zug kommt. Erst danach (in Revamp.updateRecipeCellMixGroups) wird die Zelle auf
	-- die korrekte, größere Höhe gebracht. Ohne diese äußere Sicherung/Wiederherstellung bleibt der
	-- Scroll-Wert dauerhaft auf dem von Vanilla vorzeitig geklemmten (meist 0) Stand stehen.
	local isRecipeCell = list == self.detailsList and cell.name == "recipeCell"
	local viewOffset, targetViewOffset
	if isRecipeCell then
		viewOffset = self.detailsList.viewOffset
		targetViewOffset = self.detailsList.targetViewOffset
	end

	superFunc(self, list, section, index, cell)

	if list == self.productsList then
		local _, productionPoint = self:getSelectedProduction()
		local production = productionPoint.sortedProductions[index]
		Revamp.updateProductsListRow(self, cell, production, productionPoint)
	elseif isRecipeCell then
		if Revamp.recipeItemTemplate == nil then
			Revamp.recipeItemTemplate = self.recipeItemTemplate
		end
		Revamp.updateRecipeCellMixGroups(self, cell)
		self.detailsList.viewOffset = viewOffset
		self.detailsList.targetViewOffset = targetViewOffset
	end
end

InGameMenuProductionFrame.populateCellForItemInSection = Utils.overwrittenFunction(InGameMenuProductionFrame.populateCellForItemInSection, Revamp.populateRecipeCellForItemInSection)
