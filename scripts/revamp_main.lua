Revamp = {}
Revamp.Debug = false

function Revamp.DebugText(text, ...)
	if not Revamp.Debug then return end
	print("RevampDebug: " .. string.format(text, ...))
end

function Revamp.DebugTable(text, myTable, maxDepth)
	if not Revamp.Debug then return end
	if myTable == nil then
		print("RevampDebug: " .. text .. " is nil")
	else
		print("RevampDebug: " .. text)
		DebugUtil.printTableRecursively(myTable, "_", 0, maxDepth or 2)
	end
end

---Legt einen Text des Mods zusätzlich in der globalen Textliste ab und liefert den Schlüssel, unter dem er dort erreichbar ist.
---Die Texte eines Mods liegen in einer eigenen Textliste, die nur Skripte dieses Mods sehen.
---Vanilla-Code fragt dagegen immer die globale Liste ab und würde stattdessen "Missing '<Schlüssel>' in l10n_<Sprache>.xml" anzeigen - das betrifft alles, was nicht der Mod selbst zeichnet, also die Statuszeile im Produktionsmenü und die Info-Box am Gebäude.
---@param key string Schlüssel aus den l10n-Dateien des Mods
---@return string globalKey Schlüssel für die globale Textliste
function Revamp.registerGlobalText(key)
	g_i18n:setGlobalText(key, g_i18n:getText(key))
	return g_currentModName .. "." .. key
end

-- Vanilla kennt nur INACTIVE/RUNNING/MISSING_INPUTS/NO_OUTPUT_SPACE.
-- Wetter- und zeitabhängige Rezepte brauchen zusätzlich einen Grund, warum eine eingeschaltete Linie gerade nichts produziert, sonst stünde im Dialog weiterhin "läuft".
ProductionPoint.PROD_STATUS.OUTSIDE_OF_SEASONS = 4
ProductionPoint.PROD_STATUS.OUTSIDE_OF_MONTHS = 5
ProductionPoint.PROD_STATUS.OUTSIDE_OF_HOURS = 6
ProductionPoint.PROD_STATUS.NO_WEATHER = 7

-- Der Status geht per streamWriteUIntN mit dieser Bit-Anzahl über die Leitung (ProductionPoint:writeStream und ProductionPointProductionStatusEvent).
-- Durch Vanillas 2 Bit passen nur die Werte 0 bis 3, die neuen Status kämen beim Client also als völlig andere Status an.
ProductionPoint.PROD_STATUS_NUM_BITS = 3

ProductionPoint.PROD_STATUS_TO_L10N[ProductionPoint.PROD_STATUS.OUTSIDE_OF_SEASONS] = Revamp.registerGlobalText("revamp_ui_production_statusOutsideOfSeasons")
ProductionPoint.PROD_STATUS_TO_L10N[ProductionPoint.PROD_STATUS.OUTSIDE_OF_MONTHS] = Revamp.registerGlobalText("revamp_ui_production_statusOutsideOfMonths")
ProductionPoint.PROD_STATUS_TO_L10N[ProductionPoint.PROD_STATUS.OUTSIDE_OF_HOURS] = Revamp.registerGlobalText("revamp_ui_production_statusOutsideOfHours")
ProductionPoint.PROD_STATUS_TO_L10N[ProductionPoint.PROD_STATUS.NO_WEATHER] = Revamp.registerGlobalText("revamp_ui_production_statusNoWeather")

Revamp.icons = {
	sharedThroughputCapacityTrue = g_currentModDirectory .. "gui/icon_sharedThroughputCapacity_true.dds",
	sharedThroughputCapacityFalse = g_currentModDirectory .. "gui/icon_sharedThroughputCapacity_false.dds"
}

g_gui:loadProfiles(g_currentModDirectory .. "gui/guiProfiles.xml")
