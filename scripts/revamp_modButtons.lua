--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- Anmeldestelle für Knöpfe fremder Mods im Verwalten-Dialog.
-- Die Menü-Button-Leiste des Produktionsmenüs hat sechs feste Plätze und ist mit Vanilla und Revamp zusammen bereits voll (siehe revamp_menuButtons.lua):
-- ein fremder Mod, der dort einen Knopf einträgt, fällt hinten heraus. Im Verwalten-Dialog ist dagegen in beiden Knopfreihen je ein Platz frei.
-- Auch die Tasten reichen: MENU_PAGE_PREV und MENU_PAGE_NEXT wertet ScreenElement:inputEvent nur bei einem Dialog mit pageSelector aus, den der Verwalten-Dialog nicht hat.
--
-- Der fremde Mod meldet seinen Knopf selbst an, Revamp sucht nicht bei ihm - so braucht Revamp kein Wissen über fremde Mods.
-- Erreichbar ist die Anmeldung über die Tabelle ProductionRevampApi am Ende dieser Datei, nicht über Revamp selbst: jeder Mod läuft in einer eigenen Umgebung,
-- in der die Tabellen fremder Mods gar nicht vorkommen.

-- Worauf sich ein angemeldeter Knopf bezieht. Daraus folgt seine Reihe, der Modder muss den Aufbau des Dialogs also nicht kennen:
-- FILLTYPE gilt für die markierte Ware und steht damit in der oberen Reihe bei Kaufen und Verkaufen, PRODUCTION_POINT gilt für die ganze Stätte und steht unten bei Auslagern.
Revamp.MOD_BUTTON_SCOPE = {
	FILLTYPE = "fillType",
	PRODUCTION_POINT = "productionPoint"
}

-- Je Bereich genau ein angemeldeter Knopf, denn je Reihe ist genau ein Platz frei.
Revamp.modButtons = {}

---Meldet den Knopf eines fremden Mods für den Verwalten-Dialog an.
---@param config table Anmeldung mit den Feldern modName (string), text (string, fertig übersetzt), scope (ein Wert aus Revamp.MOD_BUTTON_SCOPE), callback (function) und optional isVisible (function)
---@return boolean registered true, wenn der Knopf angenommen wurde
function Revamp.registerManageButton(config)
	if type(config) ~= "table" then
		Logging.error("Production Revamp: registerManageButton needs a table.")
		return false
	end

	if type(config.modName) ~= "string" or type(config.text) ~= "string" or type(config.callback) ~= "function" then
		Logging.error("Production Revamp: registerManageButton needs modName, text and callback.")
		return false
	end

	if config.isVisible ~= nil and type(config.isVisible) ~= "function" then
		Logging.error("Production Revamp: '%s' passed an isVisible that is not a function.", config.modName)
		return false
	end

	if config.scope ~= Revamp.MOD_BUTTON_SCOPE.FILLTYPE and config.scope ~= Revamp.MOD_BUTTON_SCOPE.PRODUCTION_POINT then
		Logging.error("Production Revamp: '%s' passed an unknown scope. Use '%s' or '%s'.", config.modName, Revamp.MOD_BUTTON_SCOPE.FILLTYPE, Revamp.MOD_BUTTON_SCOPE.PRODUCTION_POINT)
		return false
	end

	-- Der zuerst angemeldete Knopf bleibt stehen: ein später angemeldeter würde ihn sonst verdrängen, ohne dass der erste Mod davon je erfährt.
	local taken = Revamp.modButtons[config.scope]
	if taken ~= nil then
		Logging.error("Production Revamp: '%s' wants the manage dialog button for scope '%s', but '%s' already has it. Only one button per scope can be shown.", config.modName, config.scope, taken.modName)
		return false
	end

	Revamp.modButtons[config.scope] = config
	return true
end

---Liefert den angemeldeten Knopf eines Bereichs.
---@param scope string Ein Wert aus Revamp.MOD_BUTTON_SCOPE
---@return table config Anmeldung des Mods, nil wenn für diesen Bereich keiner angemeldet ist
function Revamp.getManageButton(scope)
	return Revamp.modButtons[scope]
end

-- Zugang für fremde Mods. Jeder Mod läuft in einer eigenen Umgebung, die die Engine unter seinem Modnamen in der echten globalen Tabelle ablegt (siehe mods.lua).
-- Innerhalb eines Mods zeigt _G auf genau diese eigene Umgebung, eine Zuweisung hier ist also für andere Mods nur über _G[<Modname von Revamp>] zu sehen.
-- Der Modname taugt nicht als fester Zugriffsweg, weil der Ordner in einer Testinstallation anders heißt als im ModHub.
-- Ein fremder Mod sucht deshalb die Umgebung, die diese Tabelle enthält, statt einen Namen zu raten - der Suchschnipsel steht im Wiki.
_G.ProductionRevampApi = {
	SCOPE = Revamp.MOD_BUTTON_SCOPE,
	registerManageButton = Revamp.registerManageButton
}
