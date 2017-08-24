-- итератор по нодам xml

local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end

-- получить номера установленных битов
local function GetSelectedBits(mask)
	local res = {}
	for i = 1, 32 do
		local t = bit32.lshift(1, i)
		if bit32.btest(mask, t) then
			table.insert(res, i)
		end
	end
	return res
end

-- получить все ширины из отметки
local function GetAllGapWidth(mark)
	local dom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(dom)
	local res = {}
	
	local ext = mark.ext
	for _, name in pairs{"VIDEOIDENTGWT", "VIDEOIDENTGWS"} do
		local w = name and ext[name]
		if w then
			res[name] = {[0] = tonumber(w)}
		end
	end
	
	if ext.RAWXMLDATA then
		dom:loadXML(ext.RAWXMLDATA)	
		
		local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and starts-with(@value, "CalcRailGap")]\z
		/PARAM[@name="FrameNumber" and @value="0" and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="RailGapWidth_mkm" and @value]/@value'
		
		for node in SelectNodes(dom, req) do
			local node_gap_type =  node:SelectSingleNode("../../../../@value").nodeValue
			local width = tonumber(node.nodeValue) / 1000
			
			local node_channel = node:SelectSingleNode("../../../../@channel")
			local channel = node_channel and tonumber(node_channel.nodeValue) or 0
			
			if not res[node_gap_type] then
				res[node_gap_type] = {}
			end
			res[node_gap_type][channel] = width
		end
	end
	
	return res
end


-- выбрать ширину зазора из таблицы {номер_канала:ширина} в соответствии с приоритетами каналов, 
-- сначала 19,20 (внешняя камера), потом 17,18 (внутренняя), остальные (в тч. непромаркированные)
local function SelectWidthFromChannelsWidths(channel_widths)
	if not channel_widths then 
		return nil
	end
	local width = 
		channel_widths[19] or channel_widths[20] or
		channel_widths[17] or channel_widths[18]
		
	if not width then
		_, width = next(channel_widths)
	end
	return width
end

-- получить результирующую ширину зазора
local function GetGapWidth(mark)
	local widths = GetAllGapWidth(mark)
	
	-- сначала проверим установленные пользователем ширины
	-- если их нет, то сначала проверим ширину по боковой грани, потом по пов. катания
	local src_names = {
		'CalcRailGap_User', 
		'VIDEOIDENTGWS', 
		'VIDEOIDENTGWT',
		'CalcRailGap_Head_Side',
		'CalcRailGap_Head_Top',
	}
	for _, name in ipairs(src_names) do
		if widths[name] then
			return SelectWidthFromChannelsWidths(widths[name])
		end
	end
	-- ничего не нашли
	return nil
end

-- получить конкретную ширину зазора ('inactive', 'active', 'thread', 'user')
local function GetGapWidthName(mark, name)
	local widths = GetAllGapWidth(mark)
	
	if name == 'inactive' then -- нерабочая: боковая по 19,20 каналу
		local w = widths.CalcRailGap_Head_Side
		return w and (w[19] or w[20])
	elseif name == 'active' then -- рабочая: боковая по 17,18 каналу
		local w = widths.CalcRailGap_Head_Side
		return w and (w[17] or w[18] or w[0])
	elseif name == 'thread' then -- поверх катания: 
		local w = widths.CalcRailGap_Head_Top
		return SelectWidthFromChannelsWidths(w)
	elseif name == 'user' then -- поверх катания: 
		for _, n in ipairs{'CalcRailGap_User', 'VIDEOIDENTGWS', 'VIDEOIDENTGWT'} do
			if widths[n] then
				return SelectWidthFromChannelsWidths(widths[n])
			end
		end
		return nil
	end
	return nil
end


-- извлечь количество и качество болтов из xml (если распз по неск каналам, то данные берутся последовательно из 17/18 потом из 19/20)
local function GetCrewJointCount(mark)
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom)
	
	local ext = mark.ext
	if not ext.RAWXMLDATA or not xmlDom:loadXML(ext.RAWXMLDATA)	then
		return nil
	end
	
	local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="CrewJoint"]\z
		/PARAM[@name="FrameNumber" and @value]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="JointNumber" and @value]\z
		/PARAM[@name="CrewJointSafe" and @value]/@value'

	local res = {}

	for node in SelectNodes(xmlDom, req) do
		local video_channel = node:SelectSingleNode("../../../../../@channel")
		video_channel = video_channel and tonumber(video_channel.nodeValue) or 0
		
		if not res[video_channel] then
			res[video_channel] = {0, 0}
		end
		
		res[video_channel][1] = res[video_channel][1] + 1
		local safe = tonumber(node.nodeValue)
		if safe < 1 then
			res[video_channel][2] = res[video_channel][2] + 1
		end
	end

	res = res[17] or res[18] or res[19] or res[20] or res[0]
	if res then
		return table.unpack(res)
	end
end


local function CheckCrewJointDefect(mark)
	local cnt, defect = GetCrewJointCount(mark)
	
	local is_defect = false
	if not cnt or cnt == 0 then
		-- no action
	elseif cnt == 6 then
		is_defect = defect >= 3
	elseif cnt == 4 then
		is_defect = defect >= 2
	else
		is_defect = true
	end
	
	return is_defect
end


return{
	SelectNodes = SelectNodes,
	GetAllGapWidth = GetAllGapWidth,
	GetGapWidth = GetGapWidth,
	GetSelectedBits = GetSelectedBits,
	GetGapWidthName = GetGapWidthName,
	GetCrewJointCount = GetCrewJointCount,
	CheckCrewJointDefect = CheckCrewJointDefect,
}
