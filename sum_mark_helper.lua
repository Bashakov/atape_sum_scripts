require "luacom"

function printf (s,...) return print(s:format(...)) end


local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
if not xmlDom then
	error("no Msxml2.DOMDocument: " .. luacom.config.last_error)
end


-- итератор по нодам xml
local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end


function math.round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
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
	local res = {}
	
	local ext = mark.ext
	for _, name in pairs{"VIDEOIDENTGWT", "VIDEOIDENTGWS"} do
		local w = name and ext[name]
		if w then
			res[name] = {[0] = tonumber(w)}
		end
	end
	
	if ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) then
		local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and starts-with(@value, "CalcRailGap")]\z
		/PARAM[@name="FrameNumber" and @value="0" and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="RailGapWidth_mkm" and @value]/@value'
		
		for node in SelectNodes(xmlDom, req) do
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
			if w[17] then return w[17], 17 end
			if w[18] then return w[18], 18 end
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

-- получить высоты ступеньки на стыке
local function GetRailGapStep(mark)
	local ext = mark.ext
	if not ext.RAWXMLDATA or not xmlDom:loadXML(ext.RAWXMLDATA) then 
		return nil
	end 
	local node = xmlDom:SelectSingleNode('\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="CalcRailGapStep"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="RailGapStepWidth" and @value]/@value')
	return node and math.round(tonumber(node.nodeValue)/1000, 0)
end


-- ================================= Маячные отметки ====================================

--получить смещенеи маячной отметки
local function GetBeaconOffset(mark)
	local ext = mark.ext
	local node = ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) and xmlDom:SelectSingleNode('\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="Beacon_Web"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="Shift_mkm" and @value]/@value')
	return node and tonumber(node.nodeValue)/1000
end

-- ================================= БОЛТЫ ====================================

-- получить массив с качествами болтов
local function GetCrewJointArray(mark)
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

-- =================== Накладка ===================

local function GetFishplateState(mark)
	local res = -1
	
	local ext = mark.ext
	if ext and ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) then
	
		local req = '\z
			ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and @value="Fishplate"]\z
			/PARAM[@name="FrameNumber" and @value]\z
			/PARAM[@name="Result" and @value="main"]\z
			/PARAM[@name="FishplateState"]\z
			/PARAM[@name="FishplateFault" and @value]/@value'

		for nodeFault in SelectNodes(xmlDom, req) do
			local fault = tonumber(nodeFault.nodeValue)
			res = math.max(res, fault)
		end
	end
	return res
end

-- =================== Скрепления ===================

local function IsFastenerDefect(mark)
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

-- =================== Поверхностные дефекты ===================

local function GetSurfDefectPrm(mark)
	local res = {}
	
	local ext = mark.ext
	if ext and ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) then
		local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@value="Surface"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name and @value]'
		for node_param in SelectNodes(xmlDom, req) do
			local name, value = xml_attr(node_param, {'name', 'value'})
			if value and name and name:find('Surface') then 
				value = tonumber(value)
			end
			res[name] = value
		end
				
		return res
	end
end

-- =================== Коннекторы ===================

-- получить массив коннекторов болтов (если распз по неск каналам, то данные берутся последовательно из 17/18 потом из 19/20)
local function GetConnectorsArray(mark)
	local ext = mark.ext
	if not ext.RAWXMLDATA or not xmlDom:loadXML(ext.RAWXMLDATA)	then
		return nil
	end
	
	local req = '\z
		/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Connector"]\z
		/PARAM[@name="FrameNumber" and @value]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="ConnectorFault" and @value]/@value'

	local res = {}

	for node in SelectNodes(xmlDom, req) do
		local video_channel = node:SelectSingleNode("../../../../@channel")
		video_channel = video_channel and tonumber(video_channel.nodeValue) or 0
		local fault = tonumber(node.nodeValue)
		
		if not res[video_channel] then
			res[video_channel] = {}
		end
		table.insert(res[video_channel], fault)
	end

	res = res[17] or res[18] or res[19] or res[20] or res[0]
	return res
end

-- получить полное количество, колич. дефектных
local function GetConnectorsCount(mark)
	local arr = GetConnectorsArray(mark)
	if not arr then
		return nil
	end
	local all, fault = #arr, 0
	for _, f in ipairs(arr) do
		if f ~= 0 then
			fault = fault + 1
		end
	end
	return all, fault
end

-- =================== Шпалы ===================

-- получить параметры шпалы
local function GetSleeperParam(mark)
	
	local ext = mark.ext
	if not ext.RAWXMLDATA or not xmlDom:loadXML(ext.RAWXMLDATA)	then
		return nil
	end
	
	local req = '\z
		/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Sleepers"]\z
		/PARAM[@name and @value]'

	local res = {}

	for node in SelectNodes(xmlDom, req) do
		local name = node:SelectSingleNode("@name").nodeValue
		local val = node:SelectSingleNode("@value").nodeValue
		res[name] = tonumber(val)
	end
	
	return res
end

-- получить разворот шпалы
local function GetSleeperAngle(mark)
	local ext = mark.ext
	
	if ext.SLEEPERS_ANGLE then
		return ext.SLEEPERS_ANGLE
	end
	
	if ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) then
		local req = '\z
			/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Sleepers"]\z
			/PARAM[@name="Angle_mrad" and @value]'
		local node = xmlDom:SelectSingleNode(req)
		return node and tonumber(node.nodeValue)
	end
end


-- получить материал шпалы
local function GetSleeperMeterial(mark)
	local ext = mark.ext
	
	if ext.SLEEPERS_METERIAL then
		return ext.SLEEPERS_METERIAL
	end
	
	if ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) then
		local req = '\z
			/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Sleepers"]\z
			/PARAM[@name="Material" and @value]'
		local node = xmlDom:SelectSingleNode(req)
		return node and tonumber(node.nodeValue)
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

-- фильтрация отметок по USER_ACCEPT. values = {[-1]=true, [0]=false, [1]=true}
local function filter_user_accept(marks, values, progress_callback)
	if not values then
		return marks
	end
	
	local res = {}
	for i = 1, #marks do
		local mark = marks[i]
		local ua = mark.ext.ACCEPT_USER or -1
		
		if values[ua] then
			res[#res+1] = mark
		end
		print(i, mark.prop.dwID, ua, #res)
		if progress_callback then
			progress_callback(#marks, i, #res)
		end
	end
	return res
end

-- сортировка отметок 
local function sort_marks(marks, fn, inc, progress_callback)
	inc = inc and inc ~= 0
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
		for i = 1, #t1 do
			local a, b = t1[i], t2[i]
			if a < b then return inc end
			if b < a then return not inc end
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
	local copy_res_time = os.clock()
	-- print(inc, #marks, #tmp)
	printf('fetch: %.2f,  sort = %.2f, copy_res = %.2f', fetch_time - start_time, sort_time-fetch_time, copy_res_time-sort_time)
	print("mem before KB: ", collectgarbage("count"))
	marks = nil
	key = nil
	collectgarbage()
	print("mem after KB: ", collectgarbage("count"))
	return tmp
end



local function reverse_array(arr)
	local i, j = 1, #arr
	while i < j do
		arr[i], arr[j] = arr[j], arr[i]
		i = i + 1
		j = j - 1
	end
end

-- другой способ сортировки, должен быть быстрее чем sort_marks
local function sort_stable(marks, fn, inc, progress_callback)
	local start_time = os.clock()
	
	local keys = {}	-- массив ключей, который будем сортировать
	local key_nums = {} -- таблица ключ - массив позиций исходных отметок
	
	for i = 1, #marks do
		local mark = marks[i]
		local key = fn(mark) or 0	-- создадим ключ (каждый ключ - массив), с сортируемой характеристикой
		-- if type(key) == 'table' then
			-- assert (#key == 1)
			-- key = key[1] or 0
		-- end
		
		local nms = key_nums[key]
		if not nms then
			nms = {i}
			key_nums[key] = nms
			keys[#keys+1] = key 	-- вставим в таблицу ключей 
		else
			nms[#nms + 1] = i
		end
		
		if progress_callback then
			progress_callback(#marks, i)
		end
	end
	local fetch_time = os.clock()
	
	table.sort(keys)  -- сортируем массив с ключами
	local sort_time = os.clock()

	if not inc or inc == 0 then
		reverse_array(keys)
	end
	local rev_time = os.clock()

	local tmp = {}	-- сюда скопируем отметки в нужном порядке
	for _, key in ipairs(keys) do
		local nums = key_nums[key]
		for _, i in ipairs(nums) do
			tmp[#tmp + 1] = marks[i]
		end
	end
	local copy_res_time = os.clock()
	-- print(inc, #marks, #tmp)
	printf('fetch: %.2f,  sort = %.2f, rev = %.2f copy_res = %.2f', fetch_time - start_time, sort_time-fetch_time, rev_time-sort_time, copy_res_time-rev_time)
	
	print("mem before KB: ", collectgarbage("count"))
	marks = nil
	key = nil
	key_nums = nil
	collectgarbage()
	print("mem after KB: ", collectgarbage("count"))
	return tmp
end

-- =================== ЭКПОРТ ===================



return{
	sort_marks = sort_marks,
	sort_stable = sort_stable,
	filter_marks = filter_marks,
	SelectNodes = SelectNodes,
	GetSelectedBits = GetSelectedBits,
	filter_user_accept = filter_user_accept,
	reverse_array = reverse_array,
	
	GetAllGapWidth = GetAllGapWidth,
	GetGapWidth = GetGapWidth,
	GetGapWidthName = GetGapWidthName,
	GetRailGapStep = GetRailGapStep,
	
	GetFishplateState = GetFishplateState,
	
	GetBeaconOffset = GetBeaconOffset,
	
	IsFastenerDefect = IsFastenerDefect,
	GetFastenetParams = GetFastenetParams,
	
	GetSurfDefectPrm = GetSurfDefectPrm,
	
	GetConnectorsArray = GetConnectorsArray,
	GetConnectorsCount = GetConnectorsCount,
	
	GetCrewJointArray = GetCrewJointArray,
	GetCrewJointCount = GetCrewJointCount,
	CalcValidCrewJointOnHalf = CalcValidCrewJointOnHalf,
	
	GetSleeperParam = GetSleeperParam,
	GetSleeperAngle = GetSleeperAngle,
	GetSleeperMeterial = GetSleeperMeterial,
}
