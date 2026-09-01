--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- Erweitert den Vanilla-Produktionsdialog um Parallel/Verteilt-Icon und Gebäudekosten (Ticket #2)
-- Beides sind Eigenschaften der Produktionsstätte (nicht der einzelnen Rezeptlinie), daher in der
-- pointsList-Zeile (dort wo Name/Icon der Produktionsstätte stehen), nicht in der Rezept-Detailbox.

function Revamp.removeRevampElements(parent)
	for i = #parent.elements, 1, -1 do
		local element = parent.elements[i]
		if element ~= nil and element.revampLine then
			element:delete()
		end
	end
end

function Revamp.updatePointsListRow(self, cell, index)
	Revamp.removeRevampElements(cell)

	local productionPoint = self.productionPoints[index]
	if self.pointsSelector:getState() == InGameMenuProductionFrame.POINTS_UNOWNED then
		productionPoint = self.unownedProductionPoints[index]
	end

	if productionPoint == nil then
		return
	end

	Revamp.DebugText("updatePointsListRow(): %s sharedThroughputCapacity=%s", productionPoint:getName(), tostring(productionPoint.sharedThroughputCapacity))

	-- Vanilla-Profil "fs25_productionPointsListItemName" lässt sich nicht per eigenem guiProfiles.xml
	-- überschreiben (Ladereihenfolge), daher die Position hier direkt am Element setzen.
	local nameText = cell:getAttribute("name")
	if nameText ~= nil then
		local namePos = GuiUtils.getNormalizedScreenValues("100px -20px", "0px 0px")
		nameText:setPosition(namePos[1], namePos[2])
	end

	-- Beide Anzeigen sind unabhängig voneinander abschaltbar, deshalb je ein eigener Block statt eines gemeinsamen Abbruchs.
	if Revamp.displaySettings.showSharedIcon then
		local icon = BitmapElement.new()
		cell:addElement(icon)
		icon:applyProfile("Revamp_pointsListSharedIcon")
		icon.revampLine = true
		icon:setVisible(true)
		if productionPoint.sharedThroughputCapacity then
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

	if Revamp.displaySettings.showBuildingCosts then
		local buildingCosts = 0
		if productionPoint.owningPlaceable ~= nil then
			buildingCosts = productionPoint.owningPlaceable:getDailyUpkeep()
		end

		Revamp.DebugText("updatePointsListRow(): buildingCosts=%s", tostring(buildingCosts))

		local costsText = TextElement.new()
		cell:addElement(costsText)
		costsText:applyProfile("Revamp_pointsListBuildingCosts")
		costsText.revampLine = true
		costsText:setVisible(true)
		costsText:setText(g_i18n:getText("revamp_ui_production_buildingCostsPerMonth") .. ": " .. g_i18n:formatMoney(buildingCosts, 0, true))
		costsText:updateAnchorDeltas()
		costsText:updateAbsolutePosition()
	end
end

function Revamp.populateCellForItemInSection(self, superFunc, list, section, index, cell)
	superFunc(self, list, section, index, cell)

	if list == self.pointsList then
		Revamp.updatePointsListRow(self, cell, index)
	end
end

InGameMenuProductionFrame.populateCellForItemInSection = Utils.overwrittenFunction(InGameMenuProductionFrame.populateCellForItemInSection, Revamp.populateCellForItemInSection)
