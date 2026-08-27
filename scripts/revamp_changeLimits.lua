-- Vanilla begrenzt FillTypes standardmäßig auf 255 (FillTypeManager.SEND_NUM_BITS = 8, siehe FillTypeManager:addFillType) und Produktionspunkte auf ProductionChainManager.NUM_MAX_PRODUCTION_POINTS.
-- Umfangreiche Produktions-Modpacks überschreiten beides deutlich - überzählige FillTypes werden von Vanilla dann stillschweigend verworfen ("FillTypeManager.addFillType too many fill types. Ignoring '...'").
-- Das führt beim Laden jeder Produktion, die einen dieser FillTypes referenziert, zu Folgefehlern ("Unable to load fillType", fehlende Outputs).
-- Reiner Top-Level-Code statt einer Funktion, damit das so früh wie möglich beim Laden greift - vor der FillType-Registrierung anderer Mods.
SlotSystem.NUM_OBJECT_LIMITS = {
	[SlotSystem.LIMITED_OBJECT_BALE] = {
		[PlatformId.WIN] = math.huge,
		[PlatformId.MAC] = math.huge,
		[PlatformId.PS5] = 200,
		[PlatformId.XBOX_SERIES] = 200,
		[PlatformId.IOS] = 100,
		[PlatformId.ANDROID] = 100,
		[PlatformId.SWITCH] = 100
	},
	[SlotSystem.LIMITED_OBJECT_PALLET] = {
		[PlatformId.WIN] = math.huge,
		[PlatformId.MAC] = math.huge,
		[PlatformId.PS5] = 150,
		[PlatformId.XBOX_SERIES] = 150,
		[PlatformId.IOS] = 50,
		[PlatformId.ANDROID] = 50,
		[PlatformId.SWITCH] = 50
	}
}

ProductionChainManager.NUM_MAX_PRODUCTION_POINTS = 360
FillTypeManager.SEND_NUM_BITS = 10

Logging.info("Revamp: Changed limits - Productions (%s), Pallets (%s), FillTypes (%s)", ProductionChainManager.NUM_MAX_PRODUCTION_POINTS, SlotSystem.NUM_OBJECT_LIMITS[SlotSystem.LIMITED_OBJECT_PALLET][PlatformId.WIN], 2 ^ FillTypeManager.SEND_NUM_BITS)
