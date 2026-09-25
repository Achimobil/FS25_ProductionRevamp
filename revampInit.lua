--[[
Part of Production Revamp for Farming Simulator 25

Originally created by Braeven for Farming Simulator 22.
Continued for FS25 by Achimobil, with Braeven's explicit permission.

Copyright (C) Achimobil 2026

Copying or republishing parts of this mod without explicit permission is not
allowed. See the repository README for the full terms.
]]

source(g_currentModDirectory .. "scripts/revamp_changeLimits.lua")
source(g_currentModDirectory .. "scripts/revamp_main.lua")
source(g_currentModDirectory .. "scripts/revamp_settings.lua")
source(g_currentModDirectory .. "scripts/revamp_extension.lua")
source(g_currentModDirectory .. "scripts/events/revamp_eventSettings.lua")
source(g_currentModDirectory .. "scripts/events/revamp_eventSettingsChange.lua")
source(g_currentModDirectory .. "scripts/revamp_productionModes.lua")
source(g_currentModDirectory .. "scripts/revamp_production.lua")
source(g_currentModDirectory .. "scripts/revamp_storage.lua")
source(g_currentModDirectory .. "scripts/revamp_demand.lua")
source(g_currentModDirectory .. "scripts/revamp_distribution.lua")
source(g_currentModDirectory .. "scripts/events/revamp_eventDistribution.lua")
source(g_currentModDirectory .. "scripts/revamp_productionDialog.lua")
source(g_currentModDirectory .. "scripts/revamp_recipeDisplay.lua")
source(g_currentModDirectory .. "scripts/revamp_modButtons.lua")
source(g_currentModDirectory .. "scripts/revamp_manageDialog.lua")
source(g_currentModDirectory .. "scripts/events/revamp_eventSpawn.lua")
source(g_currentModDirectory .. "scripts/revamp_storageDialog.lua")
source(g_currentModDirectory .. "scripts/revamp_spawner.lua")
source(g_currentModDirectory .. "scripts/revamp_buySell.lua")
source(g_currentModDirectory .. "scripts/events/revamp_eventBuySell.lua")
source(g_currentModDirectory .. "scripts/revamp_buyGoodsDialog.lua")
source(g_currentModDirectory .. "scripts/revamp_distributionLimitDialog.lua")
source(g_currentModDirectory .. "scripts/revamp_recipeSettings.lua")
source(g_currentModDirectory .. "scripts/events/revamp_eventRecipeSettings.lua")
source(g_currentModDirectory .. "scripts/revamp_animals.lua")
source(g_currentModDirectory .. "scripts/events/revamp_eventMoveAnimals.lua")
source(g_currentModDirectory .. "scripts/revamp_animalDeliveryDialog.lua")
source(g_currentModDirectory .. "scripts/revamp_menuButtons.lua")

-- Muss als letzte Datei geladen werden, weil sie sich die gesetzten Funktionen aller Hooks von Revamp merkt, um sie nach dem Laden aller Mods auf Fremdüberschreibungen zu prüfen.
source(g_currentModDirectory .. "scripts/revamp_hookGuard.lua")

RevampManageDialog.register()
RevampStorageDialog.register()
RevampBuyGoodsDialog.register()
RevampDistributionLimitDialog.register()
RevampAnimalDeliveryDialog.register()
