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

-- Mindestabstand zwischen zwei Meldungen über einen Überlauf. Wer die Lage kennt und trotzdem weiterspielt,
-- soll den Hinweis nicht bei jedem Öffnen des Produktionsmenüs erneut wegklicken müssen.
Revamp.MENU_BUTTON_OVERFLOW_INTERVAL = 15 * 60 * 1000

Revamp.menuButtonOverflowLastShown = nil

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

---Meldet einen Überlauf, der sich nicht mehr auflösen lässt.
---Das Menü bleibt offen und der überzählige Knopf fehlt - stillschweigend ginge das auch, dann fehlt er aber ohne jeden Hinweis,
---und welcher Knopf es trifft, hängt allein an der Ladereihenfolge der Mods.
---g_time ist die Echtzeit seit Programmstart, nicht die Spielzeit: die Meldung soll in echten Minuten Abstand halten und nicht im Zeitraffer mitlaufen.
---@param numButtons number Tatsächliche Zahl der Einträge
function Revamp.reportMenuButtonOverflow(numButtons)
	if Revamp.menuButtonOverflowLastShown ~= nil and g_time - Revamp.menuButtonOverflowLastShown < Revamp.MENU_BUTTON_OVERFLOW_INTERVAL then
		return
	end

	Revamp.menuButtonOverflowLastShown = g_time
	-- Bewusst nur eine Warnung: Der Spieler bekommt den Hinweis schon als Meldung im Menü, und wer das Log bei einem Fehler automatisch öffnen lässt, hätte dieselbe Sache sonst zweimal vor sich.
	Logging.warning("Production Revamp: %d buttons registered for the production menu, only %d of them can be displayed.", numButtons, Revamp.MENU_BUTTON_SLOTS)
	InfoDialog.show(g_i18n:getText("revamp_menuButtonOverflow"), nil, nil, DialogElement.TYPE_WARNING)
end

---Hängt die Begrenzung erst an, wenn alle Mods geladen sind.
---Beim Laden von Revamp selbst hängt sich jeder später geladene Mod hinter uns, seine Einträge wären zum Zeitpunkt unserer Prüfung also noch gar nicht da.
---@param mission table Laufende Mission
function Revamp.registerMenuButtonLimit(mission) ---@diagnostic disable-line: unused-local
	InGameMenuProductionFrame.updateMenuButtons = Utils.appendedFunction(InGameMenuProductionFrame.updateMenuButtons, Revamp.enforceMenuButtonLimit)
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, Revamp.registerMenuButtonLimit)
