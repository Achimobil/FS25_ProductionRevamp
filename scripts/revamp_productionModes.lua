-- Wetter- und zeitabhängige Produktion.
-- Eine Rezeptlinie bekommt über modes="sun hourly ..." eine Liste von Modi, die pro Produktionstakt entweder den Durchsatz skalieren (Wetter-Modi) oder die Linie ganz anhalten (Zeit-Modi).
-- Alle Modi einer Linie wirken zusammen: die Wetter-Faktoren multiplizieren sich, ein einziger blockierender Zeit-Modus hält die ganze Linie an.
--
-- Der Naturfaktor eines Wetter-Modus wird auf minPower..maxPower begrenzt und danach einmal mit weatherFactor skaliert, die Höchstleistung einer Linie ist also maxPower * weatherFactor.
-- minPower ist die Grundlast, die auch bei schlechtestem Wetter noch läuft.
-- maxPower verhindert, dass Wind und Temperatur nach oben ausbrechen: die Windgeschwindigkeit liegt bei normalem Wetter zwischen 4 und 28, im Sturm bei 68 und beim Tornado bei 120, der Naturfaktor damit beim 8-fachen.
--
-- Die Sonnen- und Mond-Modi lesen die Helligkeitskurve der Map und normieren sie auf deren eigenen Höchstwert, statt durch einen festen Wert zu teilen.
-- Die Kurve ist eine reine Map-Eigenschaft (die Vanilla-Maps erreichen mittags 8), ein fester Teiler würde auf einer Map mit anderer Kurve entweder nie 1 erreichen oder ständig darüber liegen.
-- Die Bewölkung kommt dabei nicht aus den Wolkendaten selbst: deren densityScale liegt nur zwischen 0,01 und 0,125 und taugt damit nicht als Dämpfung, während es lightDamping in FS25 gar nicht mehr gibt.
-- Stattdessen dämpft die aktuelle Wetterlage von Sonne bis Gewitter den Wert.

-- Dämpfung des Sonnen-/Mondanteils je Wetterlage.
Revamp.WEATHER_TYPE_DAMPING = {
	[WeatherType.SUN]              = 1,
	[WeatherType.PARTIALLY_CLOUDY] = 0.75,
	[WeatherType.CLOUDY]           = 0.45,
	[WeatherType.RAIN]             = 0.2,
	[WeatherType.SNOW]             = 0.2,
	[WeatherType.HAIL]             = 0.2,
	[WeatherType.TWISTER]          = 0.2,
	[WeatherType.THUNDER]          = 0.2
}

-- Windgeschwindigkeit, ab der ein windabhängiger Modus seine volle Leistung erreicht.
Revamp.WIND_FULL_POWER = 15
-- Temperatur, ab der ein wärmeabhängiger Modus seine volle Leistung erreicht.
Revamp.TEMPERATURE_FULL_POWER = 25
-- Temperatur, ab der ein kälteabhängiger Modus zu arbeiten beginnt, seine volle Leistung erreicht er bei 0 Grad.
Revamp.TEMPERATURE_COLD_START = 20

-- Modi, die den Durchsatz skalieren, statt die Linie anzuhalten, mit ihrem Text für die Rezeptanzeige.
Revamp.WEATHER_MODES = {
	SUN          = "revamp_ui_production_modeSun",
	NIGHT        = "revamp_ui_production_modeNight",
	RAIN         = "revamp_ui_production_modeRain",
	WIND         = "revamp_ui_production_modeWind",
	TEMP         = "revamp_ui_production_modeTemp",
	TEMPNEGATIVE = "revamp_ui_production_modeTempNegative"
}

-- Alle gültigen Modus-Namen einer Rezeptlinie, für die Prüfung beim Laden.
Revamp.PRODUCTION_MODES = {
	HOURLY        = true,
	SEASONAL      = true,
	MONTHLY       = true,
	LIMITBOOSTERS = true,
	SUN           = true,
	NIGHT         = true,
	RAIN          = true,
	WIND          = true,
	TEMP          = true,
	TEMPNEGATIVE  = true
}

Revamp.SEASON_L10N = {
	[Season.SPRING] = "revamp_ui_season_spring",
	[Season.SUMMER] = "revamp_ui_season_summer",
	[Season.AUTUMN] = "revamp_ui_season_autumn",
	[Season.WINTER] = "revamp_ui_season_winter"
}

---Liest die Öffnungszeiten einer Rezeptlinie.
---Mehrere Zeitfenster sind erlaubt, startHours und endHours müssen dafür gleich viele Einträge haben.
---@param production table Rezeptlinie
---@param xmlFile table XMLFile der Placeable-XML
---@param productionKey string XML-Pfad der Produktionslinie
---@param defaults table Vorgabewerte vom übergeordneten productions-Element
function Revamp.loadProductionHours(production, xmlFile, productionKey, defaults)
	production.hoursTable = {}
	production.hoursText = ""

	local startHours = string.split(xmlFile:getValue(productionKey .. "#startHours", defaults.startHours), " ")
	local endHours = string.split(xmlFile:getValue(productionKey .. "#endHours", defaults.endHours), " ")
	if #startHours ~= #endHours then
		Logging.xmlError(xmlFile, "Production Revamp: startHours and endHours for '%s' must have the same number of entries", productionKey)
		startHours = {}
		endHours = {}
	end

	local texts = {}
	local hourCount = 0
	for i = 1, #startHours do
		local startHour = tonumber(startHours[i])
		local endHour = tonumber(endHours[i])
		if startHour == nil or endHour == nil or startHour >= endHour or startHour < 0 or endHour > 24 then
			Logging.xmlError(xmlFile, "Production Revamp: opening hours '%s - %s' for '%s' are invalid - start must be lower than end, within 0 to 24", tostring(startHours[i]), tostring(endHours[i]), productionKey)
		else
			for hour = startHour, endHour - 1 do
				if not production.hoursTable[hour] then
					production.hoursTable[hour] = true
					hourCount = hourCount + 1
				end
			end
			table.insert(texts, string.format("%d - %d", startHour, endHour))
		end
	end

	-- Ohne ein einziges gültiges Zeitfenster liefe die Linie nie, das ist mit Sicherheit nicht gewollt und wäre für den Spieler auch nicht als Fehler erkennbar.
	if hourCount == 0 then
		for hour = 0, 23 do
			production.hoursTable[hour] = true
		end
		return
	end

	-- Ein Zeitfenster über den ganzen Tag ist keine Einschränkung und braucht deshalb auch keinen Hinweis in der Rezeptanzeige.
	if hourCount < 24 then
		production.hoursText = table.concat(texts, ", ")
	end
end

---Liest die Jahreszeiten einer Rezeptlinie.
---@param production table Rezeptlinie
---@param xmlFile table XMLFile der Placeable-XML
---@param productionKey string XML-Pfad der Produktionslinie
---@param defaults table Vorgabewerte vom übergeordneten productions-Element
function Revamp.loadProductionSeasons(production, xmlFile, productionKey, defaults)
	production.seasonsList = {}

	for _, entry in ipairs(string.split(xmlFile:getValue(productionKey .. "#seasons", defaults.seasons), " ")) do
		local season = tonumber(entry)
		if season == nil or season < Season.SPRING or season > Season.WINTER then
			Logging.xmlError(xmlFile, "Production Revamp: invalid season '%s' for '%s' - allowed are 1 (spring) to 4 (winter)", tostring(entry), productionKey)
		else
			production.seasonsList[season] = true
		end
	end

	local texts = {}
	for season = Season.SPRING, Season.WINTER do
		if production.seasonsList[season] then
			table.insert(texts, g_i18n:getText(Revamp.SEASON_L10N[season]))
		end
	end

	-- Alle Jahreszeiten sind keine Einschränkung und brauchen deshalb auch keinen Hinweis in der Rezeptanzeige.
	if #texts == Season.WINTER then
		production.seasonText = ""
	else
		production.seasonText = table.concat(texts, ", ")
	end
end

---Kurzname des Monats einer Spielperiode.
---Die Perioden beginnen im März, die Monatsnamen der Oberfläche im Januar.
---@param period number Spielperiode von 1 bis 12
---@return string text Kurzname des Monats
function Revamp.getMonthNameText(period)
	local month = period + 2
	if month > 12 then
		month = month - 12
	end
	return g_i18n:getText("ui_month" .. month .. "_short")
end

---Text für eine zusammenhängende Folge von Monaten.
---@param fromPeriod number Erste Spielperiode der Folge
---@param toPeriod number Letzte Spielperiode der Folge
---@return string text Einzelner Monat oder Bereich
function Revamp.getMonthRangeText(fromPeriod, toPeriod)
	if fromPeriod == toPeriod then
		return Revamp.getMonthNameText(fromPeriod)
	end
	return Revamp.getMonthNameText(fromPeriod) .. " - " .. Revamp.getMonthNameText(toPeriod)
end

---Liest die Monate einer Rezeptlinie.
---Aufeinander folgende Monate werden für die Anzeige zu einem Bereich zusammengefasst.
---@param production table Rezeptlinie
---@param xmlFile table XMLFile der Placeable-XML
---@param productionKey string XML-Pfad der Produktionslinie
---@param defaults table Vorgabewerte vom übergeordneten productions-Element
function Revamp.loadProductionMonths(production, xmlFile, productionKey, defaults)
	production.monthsList = {}

	for _, entry in ipairs(string.split(xmlFile:getValue(productionKey .. "#months", defaults.months), " ")) do
		local month = tonumber(entry)
		if month == nil or month < 1 or month > 12 then
			Logging.xmlError(xmlFile, "Production Revamp: invalid month '%s' for '%s' - allowed are 1 (march) to 12 (february)", tostring(entry), productionKey)
		else
			production.monthsList[month] = true
		end
	end

	local texts = {}
	local runStart = 0
	local runEnd = 0
	local monthCount = 0
	for period = 1, 12 do
		if production.monthsList[period] then
			monthCount = monthCount + 1
			if runStart == 0 then
				runStart = period
			end
			runEnd = period
		elseif runStart ~= 0 then
			table.insert(texts, Revamp.getMonthRangeText(runStart, runEnd))
			runStart = 0
			runEnd = 0
		end
	end
	if runStart ~= 0 then
		table.insert(texts, Revamp.getMonthRangeText(runStart, runEnd))
	end

	-- Alle Monate sind keine Einschränkung und brauchen deshalb auch keinen Hinweis in der Rezeptanzeige.
	if monthCount == 12 then
		production.monthsText = ""
	else
		production.monthsText = table.concat(texts, ", ")
	end
end

---Liest die Modi einer Rezeptlinie samt ihrer Parameter.
---@param production table Rezeptlinie
---@param xmlFile table XMLFile der Placeable-XML
---@param productionKey string XML-Pfad der Produktionslinie
---@param defaults table Vorgabewerte vom übergeordneten productions-Element
function Revamp.loadProductionModes(production, xmlFile, productionKey, defaults)
	production.modes = {}
	production.limitBoosters = false

	for _, entry in ipairs(string.split(xmlFile:getValue(productionKey .. "#modes", defaults.modes):upper(), " ")) do
		if entry ~= "" then
			if Revamp.PRODUCTION_MODES[entry] then
				table.insert(production.modes, entry)
				if entry == "LIMITBOOSTERS" then
					production.limitBoosters = true
				end
			else
				Logging.xmlError(xmlFile, "Production Revamp: unknown production mode '%s' for '%s'", entry, productionKey)
			end
		end
	end

	production.weatherFactor = xmlFile:getValue(productionKey .. "#weatherFactor", defaults.weatherFactor)
	production.minPower = xmlFile:getValue(productionKey .. "#minPower", defaults.minPower)
	production.maxPower = xmlFile:getValue(productionKey .. "#maxPower", defaults.maxPower)
	if production.maxPower < production.minPower then
		Logging.xmlError(xmlFile, "Production Revamp: maxPower for '%s' is lower than minPower, using minPower as both", productionKey)
		production.maxPower = production.minPower
	end

	Revamp.loadProductionHours(production, xmlFile, productionKey, defaults)
	Revamp.loadProductionSeasons(production, xmlFile, productionKey, defaults)
	Revamp.loadProductionMonths(production, xmlFile, productionKey, defaults)

	Revamp.DebugText("loadProductionModes(): %s modes=%s hours=%s seasons=%s months=%s minPower=%s maxPower=%s weatherFactor=%s", production.id, table.concat(production.modes, ","), production.hoursText, production.seasonText, production.monthsText, tostring(production.minPower), tostring(production.maxPower), tostring(production.weatherFactor))
end

Revamp.curveMaxima = {}

---Höchstwert einer Tageskurve, einmal je Kurve ermittelt und gemerkt.
---Wird die Beleuchtung neu geladen, entsteht ein neues Kurven-Objekt und damit automatisch auch ein neuer Eintrag.
---@param curve AnimCurve Kurve über den Tagesverlauf, Zeitachse in Minuten
---@return number maximum Höchstwert der Kurve
function Revamp.getCurveMaximum(curve)
	local maximum = Revamp.curveMaxima[curve]
	if maximum == nil then
		maximum = curve:getMaximum() or 0
		Revamp.curveMaxima[curve] = maximum
		Revamp.DebugText("getCurveMaximum(): Helligkeitskurve ausgewertet, Hoechstwert=%s", tostring(maximum))
	end
	return maximum
end

---Aktueller Wert einer Helligkeitskurve, normiert auf 0 bis 1.
---@param curve AnimCurve Kurve über den Tagesverlauf
---@return number factor Helligkeit von 0 bis 1
function Revamp.getBrightnessFactor(curve)
	if curve == nil then
		return 0
	end
	local maximum = Revamp.getCurveMaximum(curve)
	if maximum <= 0 then
		return 0
	end
	return math.clamp(curve:get(g_currentMission.environment.dayTime / 60000) / maximum, 0, 1)
end

---Dämpfung des Sonnen- und Mondlichts durch die aktuelle Wetterlage.
---@return number damping Dämpfung von 0 bis 1
function Revamp.getWeatherTypeDamping()
	local weather = g_currentMission.environment.weather
	-- Solange die erste Wettervorhersage fehlt (frisch verbundener Client), gibt es noch keine Wetterlage und getCurrentWeatherType() würde über einen leeren Eintrag stolpern.
	if weather == nil or weather.forecastItems == nil or #weather.forecastItems == 0 then
		return 1
	end
	return Revamp.WEATHER_TYPE_DAMPING[weather:getCurrentWeatherType()] or 1
end

---Naturfaktor eines Wetter-Modus, noch ohne minPower/maxPower/weatherFactor.
---Nur die Sonnen-, Mond- und Regen-Modi sind von sich aus auf 1 begrenzt, Wind und Temperatur können darüber liegen.
---@param mode string Modus in Großschreibung
---@return number|nil factor Naturfaktor oder nil, wenn der Modus kein Wetter-Modus ist
function Revamp.getWeatherModeFactor(mode)
	local environment = g_currentMission.environment
	local weather = environment.weather

	if mode == "SUN" then
		return Revamp.getBrightnessFactor(environment.baseLighting.sunBrightnessScaleCurve) * Revamp.getWeatherTypeDamping()
	elseif mode == "NIGHT" then
		return Revamp.getBrightnessFactor(environment.baseLighting.moonBrightnessScaleCurve) * Revamp.getWeatherTypeDamping()
	elseif mode == "RAIN" then
		-- Schnee und Hagel zählen wie Regen: für ein Wasserrad oder einen Regensammler ist jeder Niederschlag Niederschlag.
		return math.max(weather:getRainFallScale(), weather:getSnowFallScale(), weather:getHailFallScale())
	elseif mode == "WIND" then
		return weather.windUpdater.currentVelocity / Revamp.WIND_FULL_POWER
	elseif mode == "TEMP" then
		return math.max(weather:getCurrentTemperature(), 0) / Revamp.TEMPERATURE_FULL_POWER
	elseif mode == "TEMPNEGATIVE" then
		-- Je kälter desto besser: ab TEMPERATURE_COLD_START wird der Wert negativ und damit von der Begrenzung auf minPower hochgezogen.
		return (Revamp.TEMPERATURE_COLD_START - weather:getCurrentTemperature()) / Revamp.TEMPERATURE_COLD_START
	end

	return nil
end

---Wertet die Modi einer Rezeptlinie für den aktuellen Takt aus.
---Der Wetteranteil landet in production.weatherFactorCurrent, damit ihn die Rezeptanzeige live zeigen kann, und bleibt nil, solange die Linie gar keine Wetter-Modi hat.
---@param production table Rezeptlinie
---@return number|nil status Status, mit dem die Linie gerade angehalten ist, oder nil wenn sie laufen darf
function Revamp.processProductionModes(production)
	production.weatherFactorCurrent = nil

	-- Abgeschaltet läuft jede Linie mit voller Leistung, egal was ihr Rezept an Wetter und Uhrzeit vorgibt.
	if not Revamp.settings.weatherModesActive then
		return nil
	end

	if production.modes == nil or #production.modes == 0 then
		return nil
	end

	local environment = g_currentMission.environment
	local status = nil
	local weatherFactor = nil

	for _, mode in ipairs(production.modes) do
		if mode == "HOURLY" then
			if not production.hoursTable[environment.currentHour] then
				status = status or ProductionPoint.PROD_STATUS.OUTSIDE_OF_HOURS
			end
		elseif mode == "SEASONAL" then
			if not production.seasonsList[environment.currentSeason] then
				status = status or ProductionPoint.PROD_STATUS.OUTSIDE_OF_SEASONS
			end
		elseif mode == "MONTHLY" then
			if not production.monthsList[environment.currentPeriod] then
				status = status or ProductionPoint.PROD_STATUS.OUTSIDE_OF_MONTHS
			end
		else
			local modeFactor = Revamp.getWeatherModeFactor(mode)
			if modeFactor ~= nil then
				weatherFactor = (weatherFactor or 1) * math.clamp(modeFactor, production.minPower, production.maxPower)
			end
		end
	end

	if weatherFactor ~= nil then
		weatherFactor = weatherFactor * production.weatherFactor
		production.weatherFactorCurrent = weatherFactor

		-- Ohne diesen Stopp liefe die Linie mit Faktor 0 einfach weiter: sie würde nichts verbrauchen und nichts erzeugen, im Dialog aber weiterhin "läuft" anzeigen.
		if status == nil and weatherFactor <= 0 then
			status = ProductionPoint.PROD_STATUS.NO_WEATHER
		end
	end

	return status
end

---Liest die wetterabhängigen Lager eines Produktionspunktes.
---Ein Lager ohne weatherModes taucht in keiner der drei Tabellen auf, damit der Produktionstakt nur über die tatsächlich betroffenen Fülltypen laufen muss.
---@param productionPoint table ProductionPoint-Instanz
---@param xmlFile table XMLFile der Placeable-XML
---@param key string XML-Basispfad des ProductionPoint-Elements
function Revamp.loadWeatherStorage(productionPoint, xmlFile, key)
	productionPoint.weatherModes = {}
	productionPoint.weatherAmounts = {}
	productionPoint.weatherFactors = {}
	productionPoint.hasWeatherStorage = false

	xmlFile:iterate(key .. ".storage.capacity", function(_, storageKey)
		local mode = xmlFile:getValue(storageKey .. "#weatherModes", ""):upper()
		-- "false" ist die Aus-Schreibweise der LS22-Rezepte und bedeutet dasselbe wie ein fehlendes Attribut.
		if mode == "" or mode == "FALSE" then
			return
		end

		local fillType = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getValue(storageKey .. "#fillType"))
		if fillType == nil then
			return -- von Vanilla schon abgelehnt/geloggt
		end

		if Revamp.WEATHER_MODES[mode] == nil then
			Logging.xmlError(xmlFile, "Production Revamp: unknown weather mode '%s' for '%s' - allowed are sun, night, rain, wind, temp and tempNegative", mode, storageKey)
			return
		end

		productionPoint.weatherModes[fillType] = mode
		productionPoint.weatherAmounts[fillType] = xmlFile:getValue(storageKey .. "#weatherAmount", 0)
		productionPoint.weatherFactors[fillType] = xmlFile:getValue(storageKey .. "#weatherFactor", 1)
		productionPoint.hasWeatherStorage = true

		Revamp.DebugText("loadWeatherStorage(): %s mode=%s amount=%s factor=%s", g_fillTypeManager:getFillTypeNameByIndex(fillType), mode, tostring(productionPoint.weatherAmounts[fillType]), tostring(productionPoint.weatherFactors[fillType]))
	end)
end

---Schreibt die wetterabhängige Bestandsänderung aller betroffenen Lager eines Produktionspunktes gut.
---Eine negative Menge ist ausdrücklich erlaubt und beschreibt einen wetterabhängigen Verlust, etwa Verdunstung bei Wärme.
---@param productionPoint table ProductionPoint-Instanz
---@param hours number Vergangene Spielstunden seit dem letzten Takt
function Revamp.processWeatherStorage(productionPoint, hours)
	local storage = productionPoint.storage
	for fillTypeIndex, mode in pairs(productionPoint.weatherModes) do
		local modeFactor = Revamp.getWeatherModeFactor(mode)
		if modeFactor ~= nil then
			modeFactor = math.clamp(modeFactor, 0, 1)
			if modeFactor > 0 then
				local amount = productionPoint.weatherAmounts[fillTypeIndex] * modeFactor * productionPoint.weatherFactors[fillTypeIndex] * hours
				local fillLevel = storage:getFillLevel(fillTypeIndex)
				storage:setFillLevel(math.clamp(fillLevel + amount, 0, storage:getCapacity(fillTypeIndex)), fillTypeIndex)
			end
		end
	end
end

---Beschreibungstexte der Modi einer Rezeptlinie für die Rezeptanzeige, ein Eintrag je Modus.
---Bewusst nicht zu einer einzigen Zeile zusammengefasst: die Zutatenspalte des Produktionsmenüs ist nur 250 Pixel breit und schneidet längeren Text einfach ab.
---@param production table Rezeptlinie
---@return table texts Liste der Beschreibungen, leer wenn die Linie keine wirksamen Modi hat
function Revamp.getProductionModeTexts(production)
	local texts = {}
	-- Abgeschaltet wirken die Modi nicht mehr, dann sollen sie auch nicht mehr im Rezept stehen.
	if production.modes == nil or not Revamp.settings.weatherModesActive then
		return texts
	end

	for _, mode in ipairs(production.modes) do
		if mode == "HOURLY" then
			if production.hoursText ~= "" then
				table.insert(texts, string.format(g_i18n:getText("revamp_ui_production_modeHours"), production.hoursText))
			end
		elseif mode == "SEASONAL" then
			if production.seasonText ~= "" then
				table.insert(texts, string.format(g_i18n:getText("revamp_ui_production_modeSeasons"), production.seasonText))
			end
		elseif mode == "MONTHLY" then
			if production.monthsText ~= "" then
				table.insert(texts, string.format(g_i18n:getText("revamp_ui_production_modeMonths"), production.monthsText))
			end
		elseif mode == "LIMITBOOSTERS" then
			table.insert(texts, g_i18n:getText("revamp_ui_production_modeLimitBoosters"))
		elseif Revamp.WEATHER_MODES[mode] ~= nil then
			table.insert(texts, g_i18n:getText(Revamp.WEATHER_MODES[mode]))
		end
	end

	return texts
end
