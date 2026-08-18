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

Revamp.icons = {
	sharedThroughputCapacityTrue = g_currentModDirectory .. "gui/icon_sharedThroughputCapacity_true.dds",
	sharedThroughputCapacityFalse = g_currentModDirectory .. "gui/icon_sharedThroughputCapacity_false.dds"
}

g_gui:loadProfiles(g_currentModDirectory .. "gui/guiProfiles.xml")
