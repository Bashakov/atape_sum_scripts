require "luacom"

-- итератор по нодам xml
local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end

local function xml_attr(node, name, def)
	if type(name) == 'table' then
		local res = {}
		for i, n in ipairs(name) do
			res[i] = xml_attr(node, n, def)
		end
		return table.unpack(res)
	else
		local a = node.attributes:getNamedItem(name)
		return a and a.nodeValue or def
	end
end


-- получить номера установленных битов, вернуть массив с номерами
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

-- =================== ШИРИНА ЗАЗОРА ===================

-- получить все ширины из отметки
-- возвращает таблицу [тип][номер канала] = ширина
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
	
	if ext.RAWXMLDATA and dom:loadXML(ext.RAWXMLDATA) then
	
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
-- возвращает ширину, и номер откуда взята
local function SelectWidthFromChannelsWidths(channel_widths, mark)
	if channel_widths then 
		-- сначала проверим известные каналы
		for _, n in ipairs{19, 20, 17, 18} do
			if channel_widths[n] then 
				return channel_widths[n], n
			end
		end
		
		-- а потом хоть какой нибудь
		for n, width in pairs(channel_widths) do
			if n == 0 and mark then
				n = mark_helper.GetSelectedBits(mark.prop.ChannelMask)
				n = n and n[1]
				return width, n
			end
		end
	end
	return nil
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
			return SelectWidthFromChannelsWidths(widths[name], mark)
		end
	end
	-- ничего не нашли
	return nil
end

-- получить конкретную ширину зазора ('inactive', 'active', 'thread', 'user', nil)
local function GetGapWidthName(mark, name)
	if not name then
		return GetGapWidth(mark)
	end
	
	local widths = GetAllGapWidth(mark)
	
	if name == 'inactive' then -- нерабочая: боковая по 19,20 каналу
		local w = widths.CalcRailGap_Head_Side
		if w then
			if w[19] then return w[19], 19 end
			if w[20] then return w[20], 20 end
		end
	elseif name == 'active' then -- рабочая: боковая по 17,18 каналу
		local w = widths.CalcRailGap_Head_Side
		if w then
			if w[19] then return w[19], 19 end
			if w[20] then return w[20], 20 end
			if w[0] then 
				local video_channel = mark_helper.GetSelectedBits(mark.prop.ChannelMask)
				video_channel = video_channel and video_channel[1]
				return w[0], video_channel 
			end
		end
	elseif name == 'thread' then -- поверх катания: 
		local w = widths.CalcRailGap_Head_Top
		return SelectWidthFromChannelsWidths(w, mark)
	elseif name == 'user' then -- поверх катания: 
		for _, n in ipairs{'CalcRailGap_User', 'VIDEOIDENTGWS', 'VIDEOIDENTGWT'} do
			if widths[n] then
				return SelectWidthFromChannelsWidths(widths[n], mark)
			end
		end
		return nil
	end
	return nil
end

-- ================================= БОЛТЫ ====================================

-- получить массив с качествами болтов
local function GetCrewJointArray(mark)
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom)
	
	local ext = mark.ext
	if not ext.RAWXMLDATA or not xmlDom:loadXML(ext.RAWXMLDATA)	then
		return nil
	end
	
	local req_safe = '\z
		PARAM[@name="FrameNumber" and @value]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="JointNumber" and @value]\z
		/PARAM[@name="CrewJointSafe" and @value]/@value'

	local res = {}

	for nodeCrewJoint in SelectNodes(xmlDom, '/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="CrewJoint"]') do
		local video_channel = nodeCrewJoint:SelectSingleNode("@channel")
		video_channel = video_channel and tonumber(video_channel.nodeValue) or 0
		
		local cur_safe = {}
		for node in SelectNodes(nodeCrewJoint, req_safe) do
			local safe = tonumber(node.nodeValue)
			cur_safe[#cur_safe+1] = safe
		end
		res[video_channel] = cur_safe
	end

	res = res[17] or res[18] or res[19] or res[20] or res[0]
	return res
end


-- посчитать количество нормальных и дефектных болтов в массиве в заданном диапазоне
local function CalcJointDefectInRange(joints, first, last)
	local defects, valid = 0, 0
	for i = first or 1, last or #joints do
		local safe = joints[i]
		if safe > 0 then
			valid = valid + 1
		else
			defects = defects + 1
		end
	end
	return valid, defects
end


-- извлечь количество и качество болтов из xml (если распз по неск каналам, то данные берутся последовательно из 17/18 потом из 19/20)
local function GetCrewJointCount(mark)
	local joints = GetCrewJointArray(mark)
	if joints then
		local valid, defects = CalcJointDefectInRange(joints)
		return #joints, defects
	end
end

-- проверить стык на дефектность по наличие болтов (не больше одного млохого в половине накладки)
local function CalcValidCrewJointOnHalf(mark)
	local joints = mark_helper.GetCrewJointArray(mark)
	
	local valid_on_half = nil
	if not joints or #joints == 0 then
		-- no action
	elseif #joints == 6 then
		local l = CalcJointDefectInRange(joints, 1, 3)
		local r = CalcJointDefectInRange(joints, 4, 6)
		valid_on_half = math.min(l, r)
	elseif #joints == 4 then
		local l = CalcJointDefectInRange(joints, 1, 2)
		local r = CalcJointDefectInRange(joints, 3, 4)
		valid_on_half = math.min(l, r)
	else
		valid_on_half = 0
	end
	
	return valid_on_half
end

-- =================== Скрепления ===================

local function IsFastenerDefect(mark)
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom)
	
	local ext = mark.ext
	if ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) then
		local node = xmlDom:SelectSingleNode('/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Fastener"]//PARAM[@name="FastenerFault" and @value]/@value')
		if node then
			node = tonumber(node.nodeValue)
			return node ~= 0
		end
	end
end

local function GetFastenetParams(mark)
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom)
	
	local ext = mark.ext
	if ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA)	then
		local res = {}
		for node_frame in SelectNodes(xmlDom, '/ACTION_RESULTS/PARAM[@value="Fastener"]/PARAM[@name="FrameNumber" and @value="0" and @coord]') do
			res['frame_coord'] = tonumber(node_frame:SelectSingleNode('@coord').nodeValue)
			for node_param in SelectNodes(node_frame, 'PARAM/PARAM[@name and @value]') do
				local name, value = xml_attr(node_param, {'name', 'value'})
				res[name] = tonumber(value) or value
			end
		end
		
		local roc = 'RecogObjCoord'
		local node = xmlDom:SelectSingleNode('//PARAM[@name="' .. roc .. '" and @value]/@value')
		if node then
			res[roc] = tonumber(node.nodeValue)
		end
		
		return res
	end
end


-- =================== Вспомогательные ===================

-- фильтрация отметок
local function filter_marks(marks, fn, progress_callback)
	if not fn then
		return marks
	end
	
	local res = {}
	for i = 1, #marks do
		local mark = marks[i]
		if fn(mark) then
			res[#res+1] = mark
		end
		if progress_callback then
			progress_callback(#marks, i, #res)
		end
	end
	return res
end


-- сортировка отметок 
local function sort_marks(marks, fn, inc, progress_callback)
	local start_time = os.clock()
	
	local keys = {}	-- массив ключей, который будем сортировать
	for i = 1, #marks do
		local mark = marks[i]
		local key = fn(mark)	-- создадим ключ (каждый ключ - массив), с сортируемой характеристикой
		key[#key+1] = i 		-- добавим текущий номер отметки номер последним элементом, для стабильности сортировки
		keys[#keys+1] = key 	-- и вставим в таблицу ключей 
		if progress_callback then
			progress_callback(#marks, i)
		end
	end
	
	assert(#keys == #marks)
	local fetch_time = os.clock()

	local compare_fn = function(t1, t2)  -- функция сравнения массивов, поэлементное сравнение 
		if inc and inc ~= 0 then 
			t1, t2 = t2, t1
		end
		for i = 1, #t1 do
			local a, b = t1[i], t2[i]
			if a < b then return true end
			if b < a then return false end
		end
		return false
	end
	table.sort(keys, compare_fn)  -- сортируем массив с ключами
	local sort_time = os.clock()

	local tmp = {}	-- сюда скопируем отметки в нужном порядке
	for i, key in ipairs(keys) do
		local mark_pos = key[#key] -- номер отметки в изначальном списке мы поместили последним элементом ключа
		tmp[i] = marks[mark_pos] -- берем эту отметку и помещаем на нужное место
	end
	-- print(inc, #marks, #tmp)
	-- printf('fetch: %.2f,  sort = %.2f', fetch_time - start_time, sort_time-fetch_time)
	return tmp
end


-- =================== ЭКПОРТ ===================



return{
	sort_marks = sort_marks,
	filter_marks = filter_marks,
	SelectNodes = SelectNodes,
	GetSelectedBits = GetSelectedBits,
	
	GetAllGapWidth = GetAllGapWidth,
	GetGapWidth = GetGapWidth,
	GetGapWidthName = GetGapWidthName,
	
	IsFastenerDefect = IsFastenerDefect,
	GetFastenetParams = GetFastenetParams,
	
	GetCrewJointArray = GetCrewJointArray,
	GetCrewJointCount = GetCrewJointCount,
	CalcValidCrewJointOnHalf = CalcValidCrewJointOnHalf,
}
