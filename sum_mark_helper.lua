require "luacom"

local function printf (s,...) return print(s:format(...)) end
local function sprintf (s, ...)
	assert(s)
	local args = {...}
	local ok, res = pcall(string.format, s, table.unpack(args))
	if  not ok then
		assert(false, res)  -- place for setup breakpoint
	end
	return res
end
local function errorf(s,...)  error(string.format(s, ...)) end

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

-- конвертировать MSXML ноду в строку с форматированием
local function msxml_node_to_string(node)
	local oWriter = luacom.CreateObject("Msxml2.MXXMLWriter")
	local oReader =  luacom.CreateObject("Msxml2.SAXXMLReader")
	assert(oWriter)
	assert(oReader)

	oWriter.standalone = 0
    oWriter.omitXMLDeclaration = 1
    oWriter.indent = 1
	oWriter.encoding = 'utf-8'

	oReader:setContentHandler(oWriter)
	oReader:putProperty("http://xml.org/sax/properties/lexical-handler", oWriter)
	oReader:putProperty("http://xml.org/sax/properties/declaration-handler", oWriter)

	local unk1 = luacom.GetIUnknown(node)
    oReader:parse(unk1)

	local res = oWriter.output
	return res
end

local function round(num, idp)
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

-- разбивает массив на переекающиеся отрезки указанной длинны. enum_group({1,2,3,4,5}, 3) ->  {1,2,3}, {2,3,4}, {3,4,5}
local function enum_group(arr, len)
	local i = 0
	return function()
		i = i + 1
		if i + len <= #arr+1 then
			return table.unpack(arr, i, i + len)
		end
	end
end

-- итератор разбивающий входной массив на массив массивов заданной длинны, последний может быть короче
local function split_chunks_iter(chunk_len, arr)
	assert(chunk_len > 0)
	local i = 0
	local n = 0
	return function()
		if i > #arr - 1 then
			return nil
		end
		
		local t = {}
		for j = 1, chunk_len do
			t[j] = arr[j+i]
		end
		i = i + chunk_len
		n = n + 1
		return n, t
	end	
end

 -- разбивает входной массив на массив массивов заданной длинны, последний может быть короче
local function split_chunks(chunk_len, arr)
	assert(chunk_len > 0)
	local res = {}
	for i = 0, #arr - 1, chunk_len do
		local t = {}
		for j = 1, chunk_len do
			t[j] = arr[j+i]
		end
		res[#res + 1] = t
	end
	return res
end

local function lower_bound(array, value, pred)
	if not pred then
		pred = function(a,b) return a < b end
	end
    local count = #array
	local first = 1
    while count > 0 do
        local step = math.floor(count / 2)
		local i = first + step
        if pred(array[i], value) then
            first = i+1
            count = count - (step + 1)
        else
            count = step
		end
    end
    return first
end

local function upper_bound(array, value, pred)
	if not pred then
		pred = function(a,b) return a < b end
	end
    local count = #array
	local first = 1
    while count > 0 do
        local step = math.floor(count / 2)
		local i = first + step
        if not pred(value, array[i]) then
            first = i+1
            count = count - (step + 1)
        else
            count = step
		end
    end
    return first
end

local function equal_range(array, value, pred)
	return lower_bound(array, value, pred), upper_bound(array, value, pred)
end

-- поверхностное копирование
local function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- глубоукое копирование
local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- поиск элемента в таблице
local function table_find(tbl, val)
	for i = 1, #tbl do
		if tbl[i] == val then
			return i
		end
	end
end

-- создать таблицу из переданных аргументов, если аргумент таблица, то она распаковывается рекурсивно
local function table_merge(...)
	local res = {}

	for _, item in ipairs{...} do
		if type(item) == 'table' then
			local v = table_merge(table.unpack(item))
			for _, i in ipairs(v) do
				res[#res+1] = i
			end
		else
			res[#res+1] = item
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
				n = GetSelectedBits(mark.prop.ChannelMask)
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
				local video_channel = GetSelectedBits(mark.prop.ChannelMask)
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
	return node and round(tonumber(node.nodeValue)/1000, 0)
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

-- проверить стык на дефектность по наличие болтов (не больше одного плохого в половине накладки)
local function CalcValidCrewJointOnHalf(mark)
	local joints = GetCrewJointArray(mark)
	local valid_on_half = nil
	local broken_on_half = nil

	if joints and #joints ~= 0 then
		if true then
			--[[ https://bt.abisoft.spb.ru/view.php?id=733
				на картинке выделено синим 5/0
				5 болтов найдено неисправных - 0
				выдано закрытие.
				но один не найден.
				надо добавить его к неисправным.
				тогда результат будет 6/1
				и дальше использовать эти данные.

				для другой строки где 3/0 считать 4/1, хотя это условие более спорное

				т.е. если число болтов 5 - считаем накладку 6-дырной
					если число болтов 3 - считаем накладку 4-дырной (если возможно в коде пометить где его отключать)
			]]
			if joints and (#joints == 3 or #joints == 5) then
				table.insert(joints, -1)
			end
		end

		if #joints == 6 then
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

		broken_on_half = math.ceil(#joints/2) - valid_on_half
	end

	return valid_on_half, broken_on_half, (joints and #joints)
end

-- =================== Накладка ===================

local function GetFishplateState(mark)
	local res = -1
	local cnt = 0
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
			if fault > 0 then
				cnt = cnt + 1
			end
		end
	end
	return res, cnt
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
		/PARAM[starts-with(@value, "Surface")]\z
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
				
		if 1 then
			if res.SurfaceWidth then 
				res.SurfaceWidth = res.SurfaceWidth/10
			end
			
			if res.SurfaceLength then 
				res.SurfaceLength = (res.SurfaceLength/10) or 0
			end

			if not res.SurfaceArea and res.SurfaceWidth and res.SurfaceLength then
				res.SurfaceArea = res.SurfaceWidth * res.SurfaceLength / 100
			end
			if res.SurfaceArea then 
				res.SurfaceArea = res.SurfaceArea / 100
			end
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

-- получить статус конектора (WeldedBond) из описания стыка
local function GetWeldedBondStatus(mark)
	local ext = mark.ext
	if ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) then
		local req = '\z
			/ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and @value="WeldedBond"]\z
			/PARAM[@name="FrameNumber" and @value]\z
			/PARAM[@name="Result" and @value="main"]\z
			/PARAM[@name="ConnectorFault" and @value]\z
			/@value'

		local nodeFault = xmlDom:SelectSingleNode(req)
		return nodeFault and tonumber(nodeFault.nodeValue)
	end
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

-- получить параметры дефекта шпалы
local function GetSleeperFault(mark)
	local res = {}
	local ext = mark.ext

	if ext.RAWXMLDATA and xmlDom:loadXML(ext.RAWXMLDATA) then
		local req = '\z
			/ACTION_RESULTS/PARAM[@name="ACTION_RESULTS" and @value="Sleeper"]\z
			//PARAM[@name="SleeperFault"]\z
			/PARAM[@name and @value]'
		for node in SelectNodes(xmlDom, req) do
			local name, value = xml_attr(node, {'name', 'value'})
			res[name] = tonumber(value) or value
		end
	end
	return res
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
	if inc == nil then inc = true end
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
	--printf('fetch: %.2f,  sort = %.2f, copy_res = %.2f', fetch_time - start_time, sort_time-fetch_time, copy_res_time-sort_time)
	--print("mem before KB: ", collectgarbage("count"))
	marks = nil
	key = nil
	collectgarbage()
	--print("mem after KB: ", collectgarbage("count"))
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
	
	if true and #marks > 0 and marks[1].prop and marks[1].prop.ID then
		-- оптимизация для специальных пользовательских отметок, 
		-- их свойства лучше читать последовательно по ID, тк доп свойства кешируются
		
		local id2mark = {}	-- таблица id-отметка
		local ids = {}		-- id отметок
		for i = 1, #marks do
			local mark = marks[i]
			local mark_id = mark.prop.ID
			id2mark[mark_id] = mark
			ids[#ids + 1] = mark_id
		end
		table.sort(ids)		-- сортируем ID отметок
		local id2val = {}	
		for _, mark_id in ipairs(ids) do
			-- проходим по отмекам упрорядоченным по ID и получаем нужные свойства
			local mark = id2mark[mark_id]
			id2val[mark_id] = fn(mark)	
		end
		-- переопределяем функцию получения значения, чтобы читать закешированные значения
		fn = function(mark)
			local id = mark.prop.ID
			return id2val[id] or 0
		end
	end

	for i = 1, #marks do
		local mark = marks[i]
		local key = fn(mark) or 0	-- создадим ключ, с сортируемой характеристикой
		
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

	if inc == false or inc == 0 then
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
	--printf('fetch: %.2f,  sort = %.2f, rev = %.2f copy_res = %.2f', fetch_time - start_time, sort_time-fetch_time, rev_time-sort_time, copy_res_time-rev_time)
	
	--print("mem before KB: ", collectgarbage("count"))
	marks = nil
	key = nil
	key_nums = nil
	collectgarbage()
	--print("mem after KB: ", collectgarbage("count"))
	return tmp
end


-- возвращает форматированную путейскую координату начала отметки
local function format_path_coord(mark)
	local km, m, mm = Driver:GetPathCoord(mark.prop.SysCoord)
	local res = sprintf('%d км %.1f м', km, m + mm/1000)
	return res
end

-- отсортировать отметки по системной координате
local function sort_mark_by_coord(marks)
	return sort_stable(marks, function(mark) 
		return mark.prop.SysCoord 
	end)
end

-- вычислить назание рельса по отметке
local function GetRailName(mark)
	local mark_rail = mark
	if type(mark_rail) == 'table' or type(mark_rail) == 'userdata' then
		mark_rail = mark.prop.RailMask
	elseif type(mark_rail) == 'number' then
		-- ok
	else
		errorf('type of mark must be number or Mark(table), got %s', type(mark))
	end
	
	if bit32.btest(mark_rail, 0x03) then
		return "Оба" 
	end
	
	local right_rail_mask = tonumber(Passport.FIRST_LEFT) + 1
	return bit32.btest(mark_rail, right_rail_mask) and "Правый" or "Левый"
end

-- определяет рельсовое расположение отметки. возвращает: -1 = левый, 0 = оба, 1 = правый
local function GetMarkRailPos(mark)
	local rail_mask = bit32.band(mark.prop.RailMask, 0x3)
	if rail_mask == 3 then
		return 0
	end
	
	local left_mask = tonumber(Passport.FIRST_LEFT) + 1
	return left_mask == rail_mask and 1 or -1
end

-- получить температуру у отметки
local function GetTemperature(mark)
	if mark and mark.prop then
		local rail = bit32.btest(mark.prop.RailMask, 0x01) and 0 or 1
		local temp = Driver:GetTemperature(rail, mark.prop.SysCoord)
		
		local v = temp and (temp.target or temp.head)
		if v then
			return math.floor(v + 0.5)
		end
	end
end
	
local function prepare_row_path(row, prefix, coord)
	local km, m, mm = Driver:GetPathCoord(coord)
	row[prefix .. 'KM'] = km
	row[prefix .. 'M'] = m
	row[prefix .. 'MM'] = mm
	row[prefix .. 'M_MM1'] = sprintf('%.1f', m + mm/1000)
	row[prefix .. 'M_MM2'] = sprintf('%.2f', m + mm/1000)
	row[prefix .. 'PK'] = sprintf('%d', m/100+1) 
	row[prefix .. 'PATH'] = sprintf('%d км %.1f м', km, m + mm/1000)
end

-- создание таблицы подстановок с общими параметрами отметки
local function MakeCommonMarkTemplate(mark)
	local rails_names = {
		[-1]= 'лев.',
		[0] = 'оба',
		[1] = 'прав.'}
	local prop = mark.prop
	local sys_center = prop.SysCoord + prop.Len / 2
	local inc_offset = Passport.INCREASE == '0' and (-prop.Len / 2) or (prop.Len / 2)

	local row = {}
	local temperature = GetTemperature(mark)

	prepare_row_path(row, "BEGIN_", 	sys_center-inc_offset)
	prepare_row_path(row, "", 		sys_center)
	prepare_row_path(row, "END_", 	sys_center+inc_offset)

	row.mark_id = prop.ID
	row.SYS = prop.SysCoord
	row.LENGTH = prop.Len
	row.TYPE = Driver:GetSumTypeName(prop.Guid)
	row.DESCRIPTION = prop.Description

	row.RAIL_RAW_MASK = prop.RailMask
	row.RAIL_POS = GetMarkRailPos(mark)
	row.RAIL_NAME = rails_names[row.RAIL_POS]
	row.RAIL_TEMP = temperature and sprintf('%+.1f', temperature) or ''

	if Driver.GetGPS then
		row.LAT, row.LON = Driver:GetGPS(prop.SysCoord)
	else
		row.LAT = ''
		row.LON = ''
	end

	row.DEFECT_CODE = ''
	row.DEFECT_DESC = ''

	return row
end

-- получить описания запусков распознавания
local function GetRecognitionStartInfo()
	local guids_recog_info = {'{1D5095ED-AF51-43C2-AA13-6F6C86302FB0}'}
	local marks = Driver:GetMarks{ListType='all', GUIDS=guids_recog_info}
	marks = sort_stable(marks, function(mark) return mark.prop.ID end)
	
	-- for i, mark in ipairs(marks) do print(i, mark.prop.ID, park.prop.SysCoord) end
	
	local infos  = {}
	for _, mark in ipairs(marks) do
		local desc = mark and mark.prop.Description
		if desc and #desc > 0 then
			local info = {}
			for k, v in string.gmatch(desc, '([%w_]+)=([%w%.]+)') do
				info[k] = v
			end
			table.insert(infos, info)
		end
	end
	return infos
end

-- получить таблицу паспорта с доп параметрами
local function GetExtPassport(psp)
	psp = psp or Passport
	
	if not _ext_passport_table then
		_ext_passport_table = {}
		for n,v in pairs(psp) do
			_ext_passport_table[n] = v 
		end
		
		local data_format = ' %Y-%m-%d %H:%M:%S '
		_ext_passport_table.REPORT_DATE = os.date(data_format)
		
		local recog_info = GetRecognitionStartInfo()
		if recog_info and #recog_info > 0 then
			local info = recog_info[#recog_info]
			
			if info.RECOGNITION_START then 
				_ext_passport_table.RECOGNITION_START = os.date(data_format, info.RECOGNITION_START)
			end
			
			if info.RECOGNITION_DLL_CTIME then 
				_ext_passport_table.RECOG_VERSION_DATE = os.date(data_format, info.RECOGNITION_DLL_CTIME)
			end
			
			if info.RECOGNITION_DLL_VERSION then 
				local ver = info.RECOGNITION_DLL_VERSION
				_ext_passport_table.RECOG_VERSION = ver
				_ext_passport_table.RECOG_VERSION_MAJOR = string.match(ver, '(%d+)%.')
			end
		end
	end
	return _ext_passport_table
end

-- построить изображение для данной отметки
local function MakeMarkImage(mark, video_channel, show_range, base64)
	local img_path
	
	if ShowVideo ~= 0 then
		local prop = mark.prop
		
		if not video_channel then
			local recog_video_channels = GetSelectedBits(prop.ChannelMask)
			video_channel = recog_video_channels and recog_video_channels[1]
		end

		local panoram_width = 1500
		local width = 400
		local mark_id = (ShowVideo == 1) and prop.ID or 0
		
		if show_range then
			panoram_width = show_range[2] - show_range[1]
			width = panoram_width / 10
			if ShowVideo == 1 then
				mark_id = -1
			end
		end
		
		if video_channel then
			local img_prop = {
				mark_id = mark_id,
				mode = 3,  -- panoram
				panoram_width = panoram_width, 
				-- frame_count = 3, 
				width = width, 
				height = 300,
				base64=base64
			}
			
			--print(prop.ID, prop.SysCoord, prop.Guid, video_channel)
			local coord = show_range and (show_range[1] + show_range[2])/2 or prop.SysCoord
			img_path = Driver:GetFrame(video_channel, coord, img_prop)
		end
	end
	return img_path
end

-- сделать строку ссылку для открытия атейпа на данной отметке
function MakeMarkUri(markid)
	local link = sprintf(" -g %s -mark %d", Passport.GUID, markid)
	link = string.gsub(link, "[%s{}]", function (c)
			return string.format("%%%02X", string.byte(c))
		end)
	return "atape:" .. link
end

local table_gap_types = {
	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = 0, 	-- Стык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = 0, 	-- Стык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = 0, 	-- СтыкЗазор(Пользователь)
	["{64B5F99E-75C8-4386-B191-98AD2D1EEB1A}"] = 1, 	-- ИзоСтык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC804}"] = 2, 	-- АТСтык(Видео)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC805}"] = 2, 	-- АТСтык(Пользователь)
}

--[[ получить тип стыка
(0 - болтовой, 1 - изолированный, 2 - сварной)]]
local function GetGapType(mark)
	-- 	https://bt.abisoft.spb.ru/view.php?id=743
	local dom = assert(luacom.CreateObject("Msxml2.DOMDocument.6.0"))
	if mark and mark.ext and mark.ext.RAWXMLDATA and dom:loadXML(mark.ext.RAWXMLDATA)	then
		local node = dom:SelectSingleNode('//PARAM[@name="ACTION_RESULTS" and @value="Common"]/PARAM[@name="JointType"]/@value')
		if node then
			return tonumber(node.nodeValue)
		end
	end

	local t = mark and mark.prop and table_gap_types[mark.prop.Guid]
	return t or -1
end



-- =================== ЭКПОРТ ===================



return{
	errorf = errorf,
	printf = printf,
	sprintf = sprintf,
	sort_marks = sort_marks,
	sort_stable = sort_stable,
	filter_marks = filter_marks,
	SelectNodes = SelectNodes,
	msxml_node_to_string=msxml_node_to_string,
	GetSelectedBits = GetSelectedBits,
	filter_user_accept = filter_user_accept,
	reverse_array = reverse_array,
	enum_group = enum_group,
	split_chunks = split_chunks,
	split_chunks_iter = split_chunks_iter,
	shallowcopy = shallowcopy,
	deepcopy = deepcopy,
	table_find = table_find,
	table_merge = table_merge,
	lower_bound = lower_bound,
	upper_bound = upper_bound,
	equal_range = equal_range,
	round = round,

	sort_mark_by_coord = sort_mark_by_coord,
	format_path_coord = format_path_coord,
	GetMarkRailPos = GetMarkRailPos,
	GetRailName = GetRailName,
	MakeCommonMarkTemaple = MakeCommonMarkTemplate,
	MakeCommonMarkTemplate = MakeCommonMarkTemplate,
	GetTemperature = GetTemperature,
	GetRecognitionStartInfo = GetRecognitionStartInfo,
	GetExtPassport = GetExtPassport,
	
	GetAllGapWidth = GetAllGapWidth,
	GetGapWidth = GetGapWidth,
	GetGapWidthName = GetGapWidthName,
	GetRailGapStep = GetRailGapStep,
	GetGapType = GetGapType,
	
	GetFishplateState = GetFishplateState,
	
	GetBeaconOffset = GetBeaconOffset,
	
	IsFastenerDefect = IsFastenerDefect,
	GetFastenetParams = GetFastenetParams,
	
	GetSurfDefectPrm = GetSurfDefectPrm,
	
	GetConnectorsArray = GetConnectorsArray,
	GetConnectorsCount = GetConnectorsCount,
	
	GetWeldedBondStatus = GetWeldedBondStatus,
	
	GetCrewJointArray = GetCrewJointArray,
	GetCrewJointCount = GetCrewJointCount,
	CalcValidCrewJointOnHalf = CalcValidCrewJointOnHalf,
	
	GetSleeperParam = GetSleeperParam,
	GetSleeperAngle = GetSleeperAngle,
	GetSleeperMeterial = GetSleeperMeterial,
	GetSleeperFault = GetSleeperFault,

	MakeMarkImage = MakeMarkImage,
	MakeMarkUri = MakeMarkUri,
}
