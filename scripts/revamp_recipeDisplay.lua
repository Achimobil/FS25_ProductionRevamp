-- Rezept-Anzeige für Mix-Gruppen und Booster/Master-Booster.
--
-- Laut Architektur.md gehört die Anzeige einer Funktion zum Bau der Funktion selbst statt in ein
-- eigenes, späteres Ticket. Vanilla zeigt Rezept-Inputs als flache Liste (ein Icon+Menge+Name pro
-- Input, ProductionFrame.xml "recipeItemTemplate"), ohne jedes Konzept von Mix-Gruppen. Diese
-- Datei baut den Input-Teil der Rezeptzeile (cell.name == "recipeCell") neu auf: pro Mix-Gruppe
-- (input.mix in 1..97) eine Überschriftzeile + die zugehörigen Zutaten-Zeilen, mit alternierendem
-- Hintergrund pro Gruppen-Block. Jede Zeile wird direkt in inputLayout geklont (recipeItemTemplate),
-- dessen eigener vertikaler Auto-Flow übernimmt die Positionierung; der Hintergrund kommt dabei als
-- zusätzliches Bitmap-Kind-Element pro Zeile, nicht über einen eigenen Wrapper-Container.
--
-- Welche einzelne Zutat einer Mix-Gruppe gerade aktiv verbraucht wird, wird bewusst NICHT markiert
-- (mit Achim abgestimmt) - das ergibt sich für den Spieler aus dem mixMode-Hinweis im Rezept-Titel
-- plus den ohnehin sichtbaren Füllständen. Nur die Gesamt-Erfüllbarkeit der Gruppe wird farblich
-- markiert (weiß=genug, rot=Gruppe komplett leer).
--
-- Booster/Master-Booster (input.mix == Revamp.MIX_BOOST/MIX_MASTER) bekommen eigene Blöcke nach
-- den Mix-Gruppen und den normalen Zutaten. Sie blockieren die Produktion nie (rein optional),
-- deshalb keine rote Fehlfarbe wie bei einer leeren Mix-Gruppe, sondern ein gedimmter Grauton für
-- "gerade nicht aktiv" (Revamp.RECIPE_INACTIVE_COLOR). Da bei Booster/Master jede Zutat unabhängig
-- für sich zählt (kein Sieger wie bei einer Mix-Gruppe), wird jede Zeile einzeln nach ihrem eigenen
-- input.boostSatisfied gefärbt und zeigt zusätzlich ihren eigenen festen boostFactor. Die
-- Gruppenüberschrift zeigt den aktuell wirksamen Gesamt-Faktor (mehrere gleichzeitig aktive Booster
-- multiplizieren sich) nur, wenn er von 1 abweicht. Revamp.updateRecipeCellOutputs() (weiter unten)
-- ergänzt am Output analog die tatsächlich geboostete Menge neben der Basis-Menge.

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

-- Findet alle Fülltypen, die per Vanilla-fillTypeConversion (UnloadTrigger.lua, an den
-- productionPoint.unloadingStation.unloadTriggers hängend) auf fillTypeIndex abgebildet werden -
-- z.B. wenn ein community Rezept ROGGEN als WEIZEN-Ersatz akzeptiert. Rein informativ für die
-- Anzeige, keine eigene XML-Struktur nötig - die Konvertierung selbst passiert schon beim Abladen,
-- im Lager zählt danach nur noch fillTypeIndex.
function Revamp.getInputConverterAlternatives(productionPoint, fillTypeIndex)
	local result = {}
	local unloadingStation = productionPoint.unloadingStation
	if unloadingStation == nil or unloadingStation.unloadTriggers == nil then
		return result
	end
	-- Dieselbe Konvertierung taucht oft in mehreren Trigger-Objekten am selben Produktionspunkt
	-- auf (z.B. identisch sowohl im unloadTrigger als auch im palletTrigger hinterlegt, damit
	-- sowohl per Anhänger als auch per Palette abgeladen werden kann) - pro Ziel-Fülltyp deshalb
	-- nur einmal aufnehmen, sonst erscheint dieselbe Alternative mehrfach im Rezept.
	local seenIncomingFillTypes = {}
	for _, trigger in ipairs(unloadingStation.unloadTriggers) do
		if trigger.fillTypeConversions ~= nil then
			for incomingFillType, conversion in pairs(trigger.fillTypeConversions) do
				if conversion.outgoingFillType == fillTypeIndex and not seenIncomingFillTypes[incomingFillType] then
					seenIncomingFillTypes[incomingFillType] = true
					table.insert(result, {type = incomingFillType, ratio = conversion.ratio})
				end
			end
		end
	end
	return result
end

function Revamp.getProductionBoostInputs(production, mix)
	local result = {}
	for _, input in ipairs(production.inputs) do
		if input.mix == mix then
			table.insert(result, input)
		end
	end
	return result
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

-- Alternierender Hintergrund für Mix-Gruppen- und Booster/Master-Booster-Blöcke.
Revamp.RECIPE_GROUP_COLORS = {
	{0.15, 0.15, 0.15, 1},
	{0.08, 0.08, 0.08, 1},
}

-- Fehlfarbe für eine komplett unerfüllbare Mix-Gruppe (blockiert die Produktion)
Revamp.RECIPE_MISSING_COLOR = {1, 0, 0, 1}
-- Fehlfarbe für einen gerade nicht aktiven Booster/Master-Booster (rein optional, blockiert nicht) -
-- gedimmter Grauton statt Rot, siehe Kommentar oben.
Revamp.RECIPE_INACTIVE_COLOR = {0.3, 0.3, 0.3, 1}

function Revamp.addRecipeRowBackground(row, color)
	-- BitmapElement.new() + applyProfile() rendert bei einem zur Laufzeit erzeugten Element nicht
	-- richtig. Stattdessen ein bereits vorhandenes Bitmap-Element klonen (row hat durch
	-- recipeItemTemplate immer ein "icon") und zum Hintergrund umbauen, statt eins neu zu erzeugen.
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

function Revamp.addRecipeItemRow(parent, input, isSatisfied, groupColor, unsatisfiedColor)
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
	local nameText = "x " .. fillType.title
	if input.mix == Revamp.MIX_BOOST or input.mix == Revamp.MIX_MASTER then
		-- Zeigt den EIGENEN, festen boostFactor dieser Zutat (nicht den aktuell wirksamen
		-- Gesamtfaktor der Gruppe - der steht in der Gruppenüberschrift) - sonst sieht man nicht,
		-- was diese eine Zutat überhaupt bewirken würde, sobald sie verfügbar ist.
		nameText = nameText .. " (x" .. g_i18n:formatNumber(input.boostFactor, 2) .. ")"
	end
	name:setText(nameText)
	if not isSatisfied then
		local color = unsatisfiedColor or Revamp.RECIPE_MISSING_COLOR
		name:setTextColor(color[1], color[2], color[3], color[4])
		amount:setTextColor(color[1], color[2], color[3], color[4])
	end
	return row
end

-- Eine Converter-Alternative hat keine eigene, aus dem Rezept stammende Menge (siehe
-- getInputConverterAlternatives) - die Menge-Spalte zeigt deshalb statt einer Zahl das
-- Konvertierungsverhältnis (dieselbe multiplikative Konvention wie boostFactor).
function Revamp.addRecipeConverterAltRow(parent, alternative, groupColor)
	local row = Revamp.recipeItemTemplate:clone(parent)
	row.revampLine = true
	if groupColor ~= nil then
		Revamp.addRecipeRowBackground(row, groupColor)
	end
	local fillType = g_fillTypeManager:getFillTypeByIndex(alternative.type)
	row:getDescendantByName("icon"):setImageFilename(fillType.hudOverlayFilename)
	row:getDescendantByName("amount"):setText("")
	row:getDescendantByName("name"):setText(fillType.title .. " (x" .. g_i18n:formatNumber(alternative.ratio, 2) .. ")")
	return row
end

function Revamp.addRecipeGroupHeaderRow(parent, titleText, isSatisfied, groupColor, unsatisfiedColor)
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
	name:setText(titleText)
	if not isSatisfied then
		local color = unsatisfiedColor or Revamp.RECIPE_MISSING_COLOR
		name:setTextColor(color[1], color[2], color[3], color[4])
	end
	return row
end

function Revamp.updateRecipeCellMixGroups(self, cell)
	local production, productionPoint = self:getSelectedProduction()
	if production == nil then
		return
	end

	local groups, order = Revamp.getProductionMixGroups(production)
	local hasBoostInputs = #Revamp.getProductionBoostInputs(production, Revamp.MIX_BOOST) > 0
		or #Revamp.getProductionBoostInputs(production, Revamp.MIX_MASTER) > 0

	-- Converter-Alternativen nur für normale, nicht gruppierte Inputs (mix=0) - eine
	-- Mix-Gruppen-Zutat bekommt bewusst keine Converter-Anzeige (mit Achim abgestimmt): sonst
	-- könnten Mix-Gruppen- und Converter-Block-Optik für dieselbe Zutat kollidieren. Einmal pro
	-- Input vorab ermittelt statt weiter unten im Anzeige-Loop noch einmal, damit auch der
	-- Früh-Ausstieg direkt darunter weiß, ob es überhaupt etwas zu bauen gibt.
	local converterAlternativesByInput = {}
	local hasConverterInputs = false
	for _, input in ipairs(production.inputs) do
		if input.mix == 0 then
			local alternatives = Revamp.getInputConverterAlternatives(productionPoint, input.type)
			if #alternatives > 0 then
				converterAlternativesByInput[input] = alternatives
				hasConverterInputs = true
			end
		end
	end

	local modeTexts = Revamp.getProductionModeTexts(production)

	if #order == 0 and not hasBoostInputs and not hasConverterInputs and #modeTexts == 0 then
		return -- weder Mix-Gruppe noch Booster/Master-Booster noch Converter-Alternative noch Wetter-/Zeit-Modus in diesem Rezept, Vanilla-Darstellung von superFunc bleibt unangetastet
	end

	-- Hier nicht versuchen, den Neuaufbau bei "unveränderten" Daten zu überspringen: superFunc()
	-- baut inputLayout bei JEDEM Aufruf sowieso immer flach neu auf (unsere Gruppen-Struktur wird
	-- dabei gelöscht), bevor dieser Code hier überhaupt läuft - ein Überspringen lässt genau
	-- diesen flachen Vanilla-Zwischenstand stehen.

	-- Jede Zeile (Überschrift oder Zutat) wird direkt in inputLayout geklont, exakt dieselbe
	-- Technik, mit der Vanilla selbst die Output-Seite (arrowLayout/outputLayout) füllt. Das lässt
	-- inputLayouts eigenen vertikalen Auto-Flow die Positionierung übernehmen, statt sie selbst
	-- nachzurechnen. Ein farbiger Hintergrund pro Block kommt dabei nicht über einen eigenen
	-- Wrapper-Container, sondern als zusätzliches Bitmap-Kind-Element pro einzelner Zeile - sieht
	-- bei lückenlos aneinander stoßenden Zeilen wie ein durchgehender Block aus.
	local inputLayout = cell:getAttribute("inputLayout")
	Revamp.clearRecipeInputElements(inputLayout)

	-- Die Wetter- und Zeit-Bedingungen stehen über allen Zutaten, weil sie für die gesamte Linie gelten und nicht für eine einzelne Zutat.
	-- Jeder Modus bekommt eine eigene Zeile, für zwei Bedingungen nebeneinander reicht die Breite der Zutatenspalte nicht.
	-- Solange die Linie wegen einer dieser Bedingungen steht, werden die Zeilen gedimmt - genau wie ein Booster, der gerade nicht beiträgt.
	for _, modeText in ipairs(modeTexts) do
		Revamp.addRecipeGroupHeaderRow(inputLayout, modeText, production.modeStatus == nil, nil, Revamp.RECIPE_INACTIVE_COLOR)
	end

	local groupPosition = 0
	for _, mixGroupIndex in ipairs(order) do
		groupPosition = groupPosition + 1
		local isSatisfied = production.mixGroupSatisfied ~= nil and production.mixGroupSatisfied[mixGroupIndex]
		local groupColor = Revamp.RECIPE_GROUP_COLORS[(groupPosition - 1) % #Revamp.RECIPE_GROUP_COLORS + 1]
		Revamp.addRecipeGroupHeaderRow(inputLayout, g_i18n:getText("revamp_ui_production_mixGroup"):format(mixGroupIndex), isSatisfied, groupColor)

		for _, input in ipairs(groups[mixGroupIndex]) do
			Revamp.addRecipeItemRow(inputLayout, input, isSatisfied, groupColor)
		end
	end

	-- Nicht gruppierte, nicht optionale Zutaten (mix=0) darunter anhängen - vor Booster/Master-
	-- Booster: Mix-Gruppen stehen automatisch oben, danach die normalen Zutaten, Booster/Master-
	-- Booster erst ganz am Ende. Ein Input mit Converter-Alternativen bekommt denselben
	-- Kopfzeile+Zeilen-Aufbau wie eine Mix-Gruppe (siehe converterAlternativesByInput oben) - der
	-- echte Input bleibt dabei als ganz normale erste Zeile erhalten, nur die alternativ
	-- akzeptierten Fülltypen kommen als zusätzliche Zeilen darunter.
	for _, input in ipairs(production.inputs) do
		if input.mix == 0 then
			local alternatives = converterAlternativesByInput[input]
			if alternatives == nil then
				Revamp.addRecipeItemRow(inputLayout, input, true)
			else
				groupPosition = groupPosition + 1
				local groupColor = Revamp.RECIPE_GROUP_COLORS[(groupPosition - 1) % #Revamp.RECIPE_GROUP_COLORS + 1]
				Revamp.addRecipeGroupHeaderRow(inputLayout, g_i18n:getText("revamp_ui_production_converterGroup"), true, groupColor)
				Revamp.addRecipeItemRow(inputLayout, input, true, groupColor)
				for _, alternative in ipairs(alternatives) do
					Revamp.addRecipeConverterAltRow(inputLayout, alternative, groupColor)
				end
			end
		end
	end

	-- Booster/Master-Booster: eigener Block je Typ, in derselben abwechselnden Gruppenfarbe wie die
	-- Mix-Gruppen oben. isActive/isSatisfied hier ist bewusst NICHT "blockiert die Produktion"
	-- (Booster/Master blockieren nie), sondern "trägt gerade tatsächlich bei". Die Kopfzeile zeigt
	-- den aktuell wirksamen GESAMT-Faktor (mehrere gleichzeitig aktive Booster multiplizieren sich),
	-- die einzelne Zutatenzeile daneben ihren eigenen, festen boostFactor (siehe addRecipeItemRow).
	local boostInputs = Revamp.getProductionBoostInputs(production, Revamp.MIX_BOOST)
	if #boostInputs > 0 then
		groupPosition = groupPosition + 1
		local groupColor = Revamp.RECIPE_GROUP_COLORS[(groupPosition - 1) % #Revamp.RECIPE_GROUP_COLORS + 1]
		local factor = production.boosterFactor or 1
		local isActive = factor ~= 1
		local title = g_i18n:getText("revamp_ui_production_booster")
		if isActive then
			title = title .. " (" .. g_i18n:getText("revamp_ui_production_boostFactorCurrent"):format(g_i18n:formatNumber(factor, 2)) .. ")"
		end
		Revamp.addRecipeGroupHeaderRow(inputLayout, title, isActive, groupColor, Revamp.RECIPE_INACTIVE_COLOR)
		for _, input in ipairs(boostInputs) do
			Revamp.addRecipeItemRow(inputLayout, input, input.boostSatisfied == true, groupColor, Revamp.RECIPE_INACTIVE_COLOR)
		end
	end

	local masterInputs = Revamp.getProductionBoostInputs(production, Revamp.MIX_MASTER)
	if #masterInputs > 0 then
		groupPosition = groupPosition + 1
		local groupColor = Revamp.RECIPE_GROUP_COLORS[(groupPosition - 1) % #Revamp.RECIPE_GROUP_COLORS + 1]
		local factor = production.masterFactor or 1
		local isActive = factor ~= 1
		local title = g_i18n:getText("revamp_ui_production_masterBooster")
		if isActive then
			title = title .. " (" .. g_i18n:getText("revamp_ui_production_boostFactorCurrent"):format(g_i18n:formatNumber(factor, 2)) .. ")"
		end
		Revamp.addRecipeGroupHeaderRow(inputLayout, title, isActive, groupColor, Revamp.RECIPE_INACTIVE_COLOR)
		for _, input in ipairs(masterInputs) do
			Revamp.addRecipeItemRow(inputLayout, input, input.boostSatisfied == true, groupColor, Revamp.RECIPE_INACTIVE_COLOR)
		end
	end

	-- BoxLayoutElement.size wird von der Engine nie an den tatsächlichen Inhalt angepasst (bleibt
	-- immer bei der aus dem GUI-Profil geladenen Größe) - die wirkliche Inhaltshöhe liefert nur der
	-- Rückgabewert von invalidateLayout() (BoxLayoutElement.maxFlowSize). inputLayout.size[2] hier zu
	-- lesen sähe bei kurzen Listen zufällig richtig aus (Profil-Standardhöhe reicht zufällig), lieferte
	-- bei mehr Inhalt aber weiterhin nur die alte Standardhöhe.
	local inputLayoutContentHeight = inputLayout:invalidateLayout()

	-- Größe/buildSectionInfo() hier NICHT mehr selbst sichern/wiederherstellen - superFunc() hat
	-- VOR diesem Code schon seine eigene (zu kleine, weil ohne Gruppen-Überschriften berechnete)
	-- Größe gesetzt und dabei bereits Vanillas eigenes buildSectionInfo() mit dieser zu kleinen
	-- Höhe aufgerufen. Das klemmt den echten Scroll-Wert schon, bevor dieser Code hier überhaupt
	-- anfängt - ein "vorher" ab hier zu sichern rettet also nur den bereits falschen Wert. Die
	-- eigentliche Sicherung/Wiederherstellung passiert jetzt eine Ebene höher, um superFunc()
	-- herum, siehe Revamp.populateRecipeCellForItemInSection.
	cell:setSize(cell.size[1], inputLayoutContentHeight)
	self.detailsList.cellDatabase.recipeCell.size[2] = cell.size[2]
	cell:updateAnchorDeltas(true)
	self.detailsList:buildSectionInfo()
end

-- Zeigt bei einem aktiven Booster/Master-Booster zusätzlich zur Basis-Menge auch die tatsächlich
-- produzierte (geboostete) Menge an, z.B. "5.00 (15.00)" statt nur "5.00". Ohne Boost
-- (Gesamtfaktor 1) bleibt es bei der Basis-Menge. outputLayout wird von superFunc() immer flach neu
-- aufgebaut (ein Element pro production.outputs-Eintrag, in dessen Reihenfolge - siehe
-- InGameMenuProductionFrame:populateCellForItemInSection), deshalb reicht hier ein Nachbearbeiten
-- der bereits vorhandenen Zeilen statt eines eigenen Neuaufbaus wie bei inputLayout.
function Revamp.updateRecipeCellOutputs(self, cell)
	local production = self:getSelectedProduction()
	if production == nil then
		return
	end

	local outputLayout = cell:getAttribute("outputLayout")
	for x = 1, #production.outputs do
		local output = production.outputs[x]
		local row = outputLayout.elements[x]
		if row == nil then
			break -- sollte nicht vorkommen, superFunc() legt für jeden Output genau eine Zeile an
		end

		-- Die Menge-Spalte ist im Original nur 40px breit (fs25_productionDetailsRecipeItemAmount,
		-- textLayoutMode="resize") - für kurze Basiswerte wie "6.00" gedacht. Mit Basis- UND
		-- geboosteter Menge zusammen ("5.00 (15.00)") schrumpft die Schrift sonst winzig. Die Spalte
		-- wird deshalb immer verbreitert statt nur bei aktivem Boost - das hält alle Outputs einer
		-- Produktion gleich breit (auch wenn nur ein Teil der Outputs geboostet wird) und die Breite
		-- springt nicht sichtbar, wenn der Booster-Bestand während des Betrachtens schwankt. Menge
		-- UND Name sind beide "anchorTopRight"
		-- mit festen Pixel-Abständen zum rechten Zeilenrand - wird die ganze Zeile (row) breiter,
		-- verschiebt sich dieser Rand für beide automatisch mit, Name behält seine volle Breite. Die
		-- Zeile selbst ist nur 250px breit, aber outputLayout (der Container) ist 400px breit -
		-- reichlich Platz zum Verbreitern, ohne dass es dort abgeschnitten wird.
		local rowSize = GuiUtils.getNormalizedScreenValues("310px 0px", "0px 0px")
		local amountSize = GuiUtils.getNormalizedScreenValues("100px 0px", "0px 0px")
		row:setSize(rowSize[1], nil)
		local amount = row:getDescendantByName("amount")
		amount:setSize(amountSize[1], nil)
		row:updateAnchorDeltas()
		row:updateAbsolutePosition()
		amount:updateAnchorDeltas()
		amount:updateAbsolutePosition()
		local name = row:getDescendantByName("name")
		name:updateAnchorDeltas()
		name:updateAbsolutePosition()

		local totalMultiplier = production.masterFactor or 1
		if output.boost == true then
			totalMultiplier = totalMultiplier * (production.boosterFactor or 1)
		elseif output.boost == "reverse" then
			totalMultiplier = totalMultiplier / (production.boosterFactor or 1)
		end

		if totalMultiplier ~= 1 then
			amount:setText(g_i18n:formatNumber(output.amount, 2) .. " (" .. g_i18n:formatNumber(output.amount * totalMultiplier, 2) .. ")")
		else
			amount:setText(g_i18n:formatNumber(output.amount, 2))
		end
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

-- Zusätzliche Zeilen unter dem Status/Zyklen/Kosten-Infokasten (cell.name == "detailsCell") für Werte, die sich laufend ändern und die sich der Spieler sonst selbst ausrechnen müsste.
-- Das ist einmal der Gesamt-Boost (Booster und Master-Booster multiplizieren sich) und einmal der aktuelle Wetterfaktor.
-- Wie schon beim Gebäudekosten-Eintrag in der pointsList (siehe revamp_productionDialog.lua) wird dafür kein neues Element per .new() erzeugt (siehe Kommentar bei addRecipeRowBackground - applyProfile() auf frisch erzeugten Elementen rendert nicht zuverlässig).
-- Stattdessen wird der bereits vorhandene "infoCosts"-Text zweimal geklont, einmal als Beschriftung mit umgehängtem Profil und einmal als Wert, und um die passende Anzahl Zeilen nach unten verschoben.
-- Bewusst ohne den Hintergrundbalken der anderen drei Zeilen (fs25_productionDetailsInfoBg) - der hat kein eigenes "name"-Attribut zum sicheren Klonen.

-- Abstand der ersten zusätzlichen Zeile zur Kostenzeile und Höhe einer weiteren Zeile, beides in Pixeln des Vanilla-Rasters.
Revamp.DETAILS_INFO_FIRST_ROW = -96
Revamp.DETAILS_INFO_ROW_HEIGHT = -32

---Hängt eine weitere Beschriftung/Wert-Zeile unter den Infokasten.
---@param infoCosts any Vorhandene Kostenzeile, die als Vorlage geklont wird
---@param infoBox any Container, in dem die Zeilen hängen
---@param rowIndex number Nullbasierte Nummer der zusätzlichen Zeile
---@param labelText string Beschriftung
---@param valueText string Wert
function Revamp.addDetailsInfoLine(infoCosts, infoBox, rowIndex, labelText, valueText)
	local offset = Revamp.DETAILS_INFO_FIRST_ROW + rowIndex * Revamp.DETAILS_INFO_ROW_HEIGHT

	local label = infoCosts:clone(infoBox)
	label.revampLine = true
	label:applyProfile("fs25_productionDetailsInfoName")
	label.textBold = false -- applyProfile setzt das von infoCosts geerbte textBold=true nicht zurück
	label:setText(labelText)
	local labelPos = GuiUtils.getNormalizedScreenValues(string.format("15px %dpx", offset), "0px 0px")
	label:setPosition(labelPos[1], labelPos[2])
	label:updateAnchorDeltas()
	label:updateAbsolutePosition()

	local value = infoCosts:clone(infoBox)
	value.revampLine = true
	value:setText(valueText)
	local valuePos = GuiUtils.getNormalizedScreenValues(string.format("-15px %dpx", offset), "0px 0px")
	value:setPosition(valuePos[1], valuePos[2])
	value:updateAnchorDeltas()
	value:updateAbsolutePosition()
end

function Revamp.updateDetailsCellInfoLines(self, cell)
	local infoCosts = cell:getAttribute("infoCosts")
	local infoBox = infoCosts.parent
	-- Unsere geklonten Zeilen hängen im infoBox-Container (Elternelement von infoCosts), nicht direkt in "cell".
	-- Aufräumen muss deshalb dort ansetzen, sonst bleiben sie bei jedem Produktionswechsel stehen.
	Revamp.removeRevampElements(infoBox)

	local production = self:getSelectedProduction()
	if production == nil then
		return
	end

	local rowIndex = 0

	if production.weatherFactorCurrent ~= nil then
		Revamp.addDetailsInfoLine(infoCosts, infoBox, rowIndex, g_i18n:getText("revamp_ui_production_weatherFactor"), "x" .. g_i18n:formatNumber(production.weatherFactorCurrent, 2))
		rowIndex = rowIndex + 1
	end

	local hasBoostInputs = #Revamp.getProductionBoostInputs(production, Revamp.MIX_BOOST) > 0
		or #Revamp.getProductionBoostInputs(production, Revamp.MIX_MASTER) > 0
	if hasBoostInputs then
		local combinedFactor = (production.boosterFactor or 1) * (production.masterFactor or 1)
		Revamp.addDetailsInfoLine(infoCosts, infoBox, rowIndex, g_i18n:getText("revamp_ui_production_totalBoost"), "x" .. g_i18n:formatNumber(combinedFactor, 2))
		rowIndex = rowIndex + 1
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
		Revamp.updateRecipeCellOutputs(self, cell)
		self.detailsList.viewOffset = viewOffset
		self.detailsList.targetViewOffset = targetViewOffset
	elseif list == self.detailsList and cell.name == "detailsCell" then
		Revamp.updateDetailsCellInfoLines(self, cell)
	end
end

InGameMenuProductionFrame.populateCellForItemInSection = Utils.overwrittenFunction(InGameMenuProductionFrame.populateCellForItemInSection, Revamp.populateRecipeCellForItemInSection)
