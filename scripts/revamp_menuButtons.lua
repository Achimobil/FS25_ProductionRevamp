--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- Die Button-Leiste des Produktionsmenüs hat sechs feste Plätze (menuButton[1] bis menuButton[6] in InGameMenu.xml).
-- TabbedMenu:assignMenuButtonInfo läuft mit ipairs über diese Elemente, alles ab dem siebten Eintrag wird nie gelesen und verschwindet kommentarlos.
-- Vanilla belegt bis zu fünf davon, Revamp trägt Verwalten und Auslagern ein - ein Mod, der danach noch etwas einträgt, fällt damit hinten heraus.
Revamp.MENU_BUTTON_SLOTS = 6

Revamp.menuButtonOverflowReported = false

---Hält die Zahl der Einträge in der Button-Leiste innerhalb der darstellbaren Plätze.
---Es weicht Revamps eigener Auslagern-Knopf, denn der ist über den Verwalten-Dialog weiterhin erreichbar - ein fremder Mod hat keinen solchen Ersatzweg.
---@param self table InGameMenuProductionFrame-Instanz
function Revamp.enforceMenuButtonLimit(self)
	if #self.menuButtonInfo > Revamp.MENU_BUTTON_SLOTS and self.revampSpawnButtonInfo ~= nil then
		table.removeElement(self.menuButtonInfo, self.revampSpawnButtonInfo)
	end

	if #self.menuButtonInfo > Revamp.MENU_BUTTON_SLOTS then
		Revamp.reportMenuButtonOverflow(#self.menuButtonInfo)
	end

end

---Meldet einen Überlauf, der sich nicht mehr auflösen lässt, und verlässt den Spielstand.
---Stillschweigend weiterspielen ginge auch, dann fehlt aber ein Knopf irgendeines Mods ohne jeden Hinweis, und welcher das ist, hängt allein an der Ladereihenfolge.
---@param numButtons number Tatsächliche Zahl der Einträge
function Revamp.reportMenuButtonOverflow(numButtons)
	if Revamp.menuButtonOverflowReported then
		return
	end

	Revamp.menuButtonOverflowReported = true
	Logging.error("Production Revamp: %d buttons registered for the production menu, only %d of them can be displayed. Leaving the savegame.", numButtons, Revamp.MENU_BUTTON_SLOTS)
	InfoDialog.show(g_i18n:getText("revamp_menuButtonOverflow"), OnInGameMenuMenu, nil, DialogElement.TYPE_WARNING)
end

---Hängt die Begrenzung erst an, wenn alle Mods geladen sind.
---Beim Laden von Revamp selbst hängt sich jeder später geladene Mod hinter uns, seine Einträge wären zum Zeitpunkt unserer Prüfung also noch gar nicht da.
---@param mission table Laufende Mission
function Revamp.registerMenuButtonLimit(mission) ---@diagnostic disable-line: unused-local
	InGameMenuProductionFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuProductionFrame.updateMenuButtons, Revamp.enforceMenuButtonLimit)
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, Revamp.registerMenuButtonLimit)
