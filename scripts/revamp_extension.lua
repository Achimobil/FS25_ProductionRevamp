-- Anmeldung fremder Mods bei Revamp, rein über XML.
--
-- Ein Mod, der eine Placeable mit einem Revamp-Typ mitbringt, kann sie nicht einfach in seine eigene modDesc schreiben:
-- ohne Revamp kennt das Spiel den Typ nicht und schreibt beim Laden eine Fehlerzeile ins Log, die jeden Spieler dieses Mods trifft.
-- Stattdessen legt der fremde Mod eine Anmelde-Datei ins Wurzelverzeichnis, die nur Revamp liest - ohne Revamp existiert die Placeable für das Spiel schlicht nicht.
--
-- Bewusst rein deklarativ, ohne eine einzige Lua-Datei im fremden Mod: sobald ein Mod Skriptcode enthält, ist er nicht mehr konsolenfähig.
-- Ein reiner Placeable-Mod würde damit alle Konsolenspieler verlieren, nur um sich hier anzumelden.

-- Name der Anmelde-Datei, gesucht wird sie im Wurzelverzeichnis jedes geladenen Mods.
Revamp.EXTENSION_FILENAME = "revamp_extension.xml"

-- Die Anmeldung darf nur einmal je Sitzung laufen: die eingereihten Store-Items bleiben über einen Kartenwechsel hinweg bestehen,
-- ein zweiter Durchlauf würde dieselben Einträge ein weiteres Mal in den Laden legen.
Revamp.extensionsLoaded = false

---Liefert das Schema der Anmelde-Datei und legt es beim ersten Aufruf an.
---Bewusst erst bei Bedarf statt beim Laden des Mods: dann steht fest, dass die XML-Verwaltung des Spiels bereits vollständig hochgefahren ist.
---@return XMLSchema schema Schema der Anmelde-Datei
function Revamp.getExtensionSchema()
	if Revamp.extensionSchema == nil then
		Revamp.extensionSchema = XMLSchema.new("revampExtension")
		Revamp.extensionSchema:register(XMLValueType.STRING, "revampExtension.storeItems.storeItem(?)#xmlFilename", "Pfad zur Store-Item-XML, relativ zum Wurzelverzeichnis des anmeldenden Mods")
	end

	return Revamp.extensionSchema
end

---Liest die Anmelde-Datei eines Mods und meldet die darin genannten Store-Items an.
---@param mod table Eintrag aus g_modManager:getActiveMods()
---@param filename string Vollständiger Pfad der Anmelde-Datei
---@return number numStoreItems Anzahl der tatsächlich angemeldeten Store-Items
function Revamp.loadExtensionFile(mod, filename)
	local xmlFile = XMLFile.load("revampExtensionXML", filename, Revamp.getExtensionSchema())
	if xmlFile == nil then
		Logging.error("Production Revamp: unable to read extension file '%s'", filename)
		return 0
	end

	local numStoreItems = 0

	xmlFile:iterate("revampExtension.storeItems.storeItem", function(_, key)
		local storeItemFilename = xmlFile:getValue(key .. "#xmlFilename")
		if storeItemFilename == nil then
			Logging.xmlError(xmlFile, "Production Revamp: '%s' needs an 'xmlFilename'", key)
			return
		end

		-- Lieber hier melden als das Spiel später über eine fehlende Datei stolpern zu lassen: der Modder sieht dann, welcher Eintrag gemeint ist.
		if not fileExists(Utils.getFilename(storeItemFilename, mod.modDir)) then
			Logging.xmlError(xmlFile, "Production Revamp: store item '%s' does not exist in mod '%s'", storeItemFilename, mod.modName)
			return
		end

		-- Angemeldet wie ein Eintrag aus der modDesc des fremden Mods, mit dessen Umgebung: nur so greifen seine eigenen Texte, Bilder und Typen.
		g_storeManager:addModStoreItem(storeItemFilename, mod.modDir, mod.modName, true, false, mod.title)
		numStoreItems = numStoreItems + 1
	end)

	xmlFile:delete()

	return numStoreItems
end

---Sucht in allen geladenen Mods nach Anmelde-Dateien und trägt deren Store-Items ein.
---Läuft direkt bevor das Spiel die eingereihten Store-Items tatsächlich lädt - zu diesem Zeitpunkt sind alle Mods durch, und die Liste ist noch nicht abgearbeitet.
function Revamp.loadExtensions()
	if Revamp.extensionsLoaded then
		return
	end
	Revamp.extensionsLoaded = true

	local numStoreItems = 0
	local numMods = 0

	for _, mod in ipairs(g_modManager:getActiveMods()) do
		local filename = mod.modDir .. Revamp.EXTENSION_FILENAME
		if fileExists(filename) then
			local numAdded = Revamp.loadExtensionFile(mod, filename)
			if numAdded > 0 then
				numMods = numMods + 1
				numStoreItems = numStoreItems + numAdded
				Revamp.DebugText("loadExtensions(): %s meldet %d Store-Items an", mod.modName, numAdded)
			end
		end
	end

	-- Eine Zeile im Log, damit ein Modder ohne Debug-Schalter sieht, dass seine Anmeldung angekommen ist.
	if numStoreItems > 0 then
		Logging.info("Production Revamp: added %d store items from %d mods", numStoreItems, numMods)
	end
end

StoreManager.loadMapData = Utils.prependedFunction(StoreManager.loadMapData, Revamp.loadExtensions)
