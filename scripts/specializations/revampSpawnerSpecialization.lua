-- Auslagern an einem Silo: ein Auslöser am Gebäude, der denselben Auslagern-Dialog öffnet wie eine Produktionsstätte.
-- Die Produktionsstätte braucht dafür keine Spezialisierung, sie bringt mit ProductionPointActivatable längst einen Auslöser mit, an den sich Revamp hängt (siehe revamp_spawner.lua).
-- Ein Silo hat nichts Vergleichbares, deshalb hier ein eigener Trigger samt Aktivierbarem.
--
-- Das Spawnen selbst ist für beide dieselbe Sache und steht in revamp_spawner.lua. Diese Spezialisierung hängt die Funktionen nur an die Placeable
-- und stellt bereit, was sie von ihrem Träger erwarten: einen Palettenspawner und die Angaben zum Ablegen von Stämmen.

RevampSpawnerActivatable = {}
local RevampSpawnerActivatable_mt = Class(RevampSpawnerActivatable)

---@param placeable table Placeable, an der der Auslöser hängt
---@return table self Neues Aktivierbares
function RevampSpawnerActivatable.new(placeable)
	local self = setmetatable({}, RevampSpawnerActivatable_mt)
	self.placeable = placeable
	self.activateText = g_i18n:getText("revamp_storageButtonSpawn")
	return self
end

---@return boolean isActivatable true, wenn die eigene Farm auf dieses Silo zugreifen darf
function RevampSpawnerActivatable:getIsActivatable()
	-- Ohne die Lager-Erweiterung soll der Auslöser gar nicht erst erscheinen, statt einen Dialog zu öffnen, der nichts kann.
	return Revamp.settings.storageActive and g_currentMission.accessHandler:canFarmAccess(g_currentMission:getFarmId(), self.placeable)
end

---@param x number Position des Spielers
---@param y number Position des Spielers
---@param z number Position des Spielers
---@return number distance Abstand zum Auslöser, math.huge wenn es keinen gibt
function RevampSpawnerActivatable:getDistance(x, y, z)
	local spec = self.placeable.spec_revampSpawner
	if spec.triggerNode == nil then
		return math.huge
	end

	local triggerX, triggerY, triggerZ = getWorldTranslation(spec.triggerNode)
	return MathUtil.vector3Length(x - triggerX, y - triggerY, z - triggerZ)
end

function RevampSpawnerActivatable:run()
	Revamp.showSiloSpawnDialog(self.placeable)
end

RevampSpawnerSpecialization = {}

---@param specializations table Spezialisierungen des Placeable-Typs
---@return boolean present true, wenn die Placeable ein Silo ist
function RevampSpawnerSpecialization.prerequisitesPresent(specializations)
	return SpecializationUtil.hasSpecialization(PlaceableSilo, specializations)
end

---@param placeableType table Placeable-Typ, an dem die Spezialisierung hängt
function RevampSpawnerSpecialization.registerEventListeners(placeableType)
	SpecializationUtil.registerEventListener(placeableType, "onLoad", RevampSpawnerSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", RevampSpawnerSpecialization)
	SpecializationUtil.registerEventListener(placeableType, "onDelete", RevampSpawnerSpecialization)
end

---@param placeableType table Placeable-Typ, an dem die Spezialisierung hängt
function RevampSpawnerSpecialization.registerFunctions(placeableType)
	SpecializationUtil.registerFunction(placeableType, "onRevampSpawnerTriggerCallback", RevampSpawnerSpecialization.onRevampSpawnerTriggerCallback)
	-- Dieselben Funktionen wie an der Produktionsstätte: das Spawn-Event schickt die Placeable als Empfänger über das Netz und ruft sie dort auf.
	SpecializationUtil.registerFunction(placeableType, "ReceiveSpawnEvent", Revamp.receiveSpawnEvent)
	SpecializationUtil.registerFunction(placeableType, "getPalletCallback", Revamp.spawnPalletCallback)
end

---@param schema XMLSchema Schema der Placeable-XML
---@param basePath string Basis-Pfad des placeable-Knotens
function RevampSpawnerSpecialization.registerXMLPaths(schema, basePath) ---@diagnostic disable-line: unused-local
	Revamp.registerSpawnerXMLPaths(schema)
end

---@param savegame? table Spielstanddaten, nil bei einer neu gebauten Placeable
function RevampSpawnerSpecialization:onLoad(savegame) ---@diagnostic disable-line: unused-local
	self.spec_revampSpawner = {}
	local spec = self.spec_revampSpawner
	local xmlFile = self.xmlFile

	if not xmlFile:hasProperty("placeable.revampSpawner") then
		return
	end

	spec.triggerNode = xmlFile:getValue("placeable.revampSpawner#triggerNode", nil, self.components, self.i3dMappings)
	if spec.triggerNode == nil then
		Logging.xmlError(xmlFile, "Production Revamp: 'placeable.revampSpawner' needs a triggerNode, nothing can be taken out of this storage")
		return
	end

	-- Ohne dieses Bit im Modell bemerkt der Trigger den Spieler nie, und der Auslöser bliebe unerklärlich stumm.
	if not CollisionFlag.getHasMaskFlagSet(spec.triggerNode, CollisionFlag.PLAYER) then
		Logging.xmlWarning(xmlFile, "Production Revamp: trigger node of 'placeable.revampSpawner' is missing the collision mask bit 'PLAYER' (%d)", CollisionFlag.getBit(CollisionFlag.PLAYER))
	end

	Revamp.loadSpawnerConfig(self, xmlFile, self.components, self.i3dMappings)

	-- Der Palettenspawner hängt bewusst direkt an der Placeable und nicht nur im spec: die gemeinsamen Spawn-Funktionen greifen bei Produktionsstätte wie Silo unter demselben Namen darauf zu.
	self.palletSpawner = PalletSpawner.new(self.baseDirectory)
	self.palletSpawner:load(self.components, xmlFile, "placeable.revampSpawner.palletSpawner", self.customEnvironment, self.i3dMappings)
	Revamp.prepareSpawnBookkeeping(self.palletSpawner)

	spec.activatable = RevampSpawnerActivatable.new(self)
end

---@param savegame? table Spielstanddaten, nil bei einer neu gebauten Placeable
function RevampSpawnerSpecialization:onFinalizePlacement(savegame) ---@diagnostic disable-line: unused-local
	local spec = self.spec_revampSpawner
	if spec.triggerNode ~= nil then
		addTrigger(spec.triggerNode, "onRevampSpawnerTriggerCallback", self)
	end
end

function RevampSpawnerSpecialization:onDelete()
	local spec = self.spec_revampSpawner
	if spec.activatable ~= nil then
		-- Steht der Spieler beim Abreißen gerade im Trigger, bliebe der Eintrag sonst in der Liste der Aktivierbaren stehen.
		g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
	end

	if spec.triggerNode ~= nil then
		removeTrigger(spec.triggerNode)
		spec.triggerNode = nil
	end
end

---@param triggerId number Auslösender Trigger
---@param otherId number Knoten, der den Trigger betreten oder verlassen hat
---@param onEnter boolean true beim Betreten
---@param onLeave boolean true beim Verlassen
---@param onStay boolean true, solange sich etwas darin befindet
function RevampSpawnerSpecialization:onRevampSpawnerTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay) ---@diagnostic disable-line: unused-local
	if (onEnter or onLeave) and (g_localPlayer ~= nil and g_localPlayer.rootNode == otherId) then
		local spec = self.spec_revampSpawner
		if onEnter then
			g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
		else
			g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
		end
	end
end
