--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

-- Revamp ersetzt einige Engine-Funktionen vollständig und reicht superFunc dort nicht weiter, weil Vanilla an diesen Stellen keinen Erweiterungspunkt bietet.
-- Ein fremder Mod, der dieselben Funktionen genauso vollständig ersetzt und nach Revamp geladen wird, hebelt Revamp dort komplett aus - ohne Fehlermeldung, das Feature fehlt einfach.
-- Deshalb wird die tatsächlich gesetzte Funktion beim Laden gemerkt und nach dem Laden aller Mods dagegen verglichen.
--
-- Bewusst wird dabei nichts zurückgesetzt: ein fremder Hook, der superFunc korrekt weiterreicht, ist genauso "nicht mehr die äußerste Schicht", funktioniert aber einwandfrei.
-- Ein Zurücksetzen würde so einen Mod grundlos aus der Kette werfen.
-- Ob ein Hook weiterreicht, ist der gesetzten Funktion nicht ansehbar, deshalb bleibt es bei der Meldung im Log.
Revamp.watchedHooks = {
	{ name = "ProductionChainManager.distributeGoods", class = ProductionChainManager, key = "distributeGoods" },
	{ name = "ProductionPoint.updateProduction", class = ProductionPoint, key = "updateProduction" },
	{ name = "ProductionPoint.load", class = ProductionPoint, key = "load" },
	{ name = "ProductionPoint.loadFromXMLFile", class = ProductionPoint, key = "loadFromXMLFile" },
	{ name = "ProductionPoint.setProductionState", class = ProductionPoint, key = "setProductionState" },
	{ name = "ProductionPointActivatable.run", class = ProductionPointActivatable, key = "run" },
	{ name = "PalletSpawner.update", class = PalletSpawner, key = "update" },
	{ name = "PalletSpawner.getSupportedFillTypes", class = PalletSpawner, key = "getSupportedFillTypes" },
	{ name = "Storage.load", class = Storage, key = "load" },
	{ name = "StorageSystem.addUnloadingStation", class = StorageSystem, key = "addUnloadingStation" },
	{ name = "FillTypeDesc.loadFromXMLFile", class = FillTypeDesc, key = "loadFromXMLFile" },
	{ name = "FinanceStats.new", class = FinanceStats, key = "new" },

	{ name = "InGameMenuProductionFrame.getNumberOfSections", class = InGameMenuProductionFrame, key = "getNumberOfSections" },
	{ name = "InGameMenuProductionFrame.getNumberOfItemsInSection", class = InGameMenuProductionFrame, key = "getNumberOfItemsInSection" },
	{ name = "InGameMenuProductionFrame.getCellTypeForItemInSection", class = InGameMenuProductionFrame, key = "getCellTypeForItemInSection" },
	{ name = "InGameMenuProductionFrame.getTitleForSectionHeader", class = InGameMenuProductionFrame, key = "getTitleForSectionHeader" },
	{ name = "InGameMenuProductionFrame.populateCellForItemInSection", class = InGameMenuProductionFrame, key = "populateCellForItemInSection" },
	{ name = "SmoothListElement.updateView", class = SmoothListElement, key = "updateView" }
}

---Merkt zu jeder überwachten Funktion, welche Funktion nach dem Laden von Revamp tatsächlich gesetzt ist.
---Muss laufen, nachdem alle Hooks von Revamp gesetzt sind, also am Ende dieser Datei, die ihrerseits als letzte geladen wird.
function Revamp.snapshotHooks()
	for _, hook in ipairs(Revamp.watchedHooks) do
		hook.loaded = hook.class[hook.key]
	end
end

---Prüft nach dem Laden aller Mods, ob die überwachten Funktionen noch die beim Laden von Revamp gesetzten sind.
---@param mission table Laufende Mission
function Revamp.checkHooks(mission) ---@diagnostic disable-line: unused-local
	for _, hook in ipairs(Revamp.watchedHooks) do
		local current = hook.class[hook.key]
		if current ~= hook.loaded then
			Logging.warning("Production Revamp: '%s' was replaced after Revamp by another mod. "
				.. "If that mod does not pass the original call on, the Revamp features using it stop working without any further error.", hook.name)
		end
	end
end

---Prüft nach dem Laden aller Fülltypen, ob Revamp die Paletten je Mod-Umgebung sammeln konnte.
---Hat ein Fülltyp eine Palette, aber keine Sammlung, hat ein anderer Mod FillTypeDesc.loadFromXMLFile ersetzt, ohne weiterzureichen.
---Der Auslagern-Dialog bietet dann keine Paletten an, statt abzustürzen, und weist beim Öffnen darauf hin.
---@param mission table Laufende Mission
function Revamp.checkFillTypePallets(mission) ---@diagnostic disable-line: unused-local
	Revamp.fillTypePalletsMissing = false
	for _, fillType in ipairs(g_fillTypeManager:getFillTypes()) do
		if fillType.palletFilename ~= nil and fillType.pallets == nil then
			Revamp.fillTypePalletsMissing = true
			break
		end
	end

	if Revamp.fillTypePalletsMissing then
		-- Der bekannte Auslöser wird beim Namen genannt, weil der Spieler sonst nur Revamp als Ursache sieht: der Fehler zeigt sich erst im Auslagern-Dialog.
		Logging.error("Production Revamp: Another mod replaces 'FillTypeDesc.loadFromXMLFile' without passing the call on. "
			.. "Pallets therefore cannot be spawned from productions and silos. "
			.. "Known cause: FS25_ZYX_FillTypesPatch (FillType Conflict Resolver). "
			.. "The base game fixes that issue itself since game version 1.17.0.0, so that mod can be removed.")
	end
end

Revamp.snapshotHooks()

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, Revamp.checkHooks)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, Revamp.checkFillTypePallets)
