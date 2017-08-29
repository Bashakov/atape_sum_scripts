mark_helper = require 'sum_mark_helper'

local sprintf = function(s,...)	return s:format(...) 			end
local printf = function(s,...)	print(s:format(...)) 			end


local SelectNodes = mark_helper.SelectNodes
local sort_marks = mark_helper.sort_marks


local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
assert(xmlDom)



local function GetBeaconOffset(mark)
	xmlDom:loadXML(mark.ext.RAWXMLDATA)
	local node = xmlDom:SelectSingleNode('\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="Beacon_Web"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="Shift_mkm" and @value]/@value')
	return node and tonumber(node.nodeValue)/1000
end

local function GetRailGapStep(mark)
	if not xmlDom:loadXML(mark.ext.RAWXMLDATA) then 
		return nil
	end 
	local node = xmlDom:SelectSingleNode('\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="CalcRailGapStep"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="RailGapStepWidth" and @value]/@value')
	return node and tonumber(node.nodeValue)
end

-- получить пареметры скрепления
local function GetFastenerParam(mark)
	xmlDom:loadXML(mark.ext.RAWXMLDATA)
	
	local req = '\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="Fastener"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name and @value]'
	local res = {}
	for node in SelectNodes(xmlDom, req) do
		local name = node:SelectSingleNode("@name").nodeValue
		local value = node:SelectSingleNode("@value").nodeValue
		--print(name, value)
		res[name] = value
	end
	return res
end

-- получить параметр скрепления по имени (разбор xml)
local function GetFastenerParamName(mark, name)
	xmlDom:loadXML(mark.ext.RAWXMLDATA)
	
	local req = string.format('\z
		/ACTION_RESULTS\z
		/PARAM[@name="ACTION_RESULTS" and @value="Fastener"]\z
		/PARAM[@name="FrameNumber" and @value and @coord]\z
		/PARAM[@name="Result" and @value="main"]\z
		/PARAM[@name="%s"]/@value', name)
	local node = xmlDom:SelectSingleNode(req)
	return node and node.nodeValue
end

-- получить параметр скрепления по имени (поиск строки, работает не всегда)
local function GetFastenerParamName1(mark, name)
	local x = mark.ext.RAWXMLDATA
	local req = 'PARAM%s+name%s*=%s*"' .. name .. '"%s*value%s*=%s*"([^"]+)"'
	--local req = 'PARAM%s+name="' .. name .. '"[^>]+value="([^"]+)"'
	local res = string.match(x, req)
	return res
end

-- =====================================================================  

local work_marks_list = {}
local work_filter = None
local work_sort_param = {0, 0}

local column_num = 
{
	name = '№', 
	width = 35, 
	align = 'r',
	text = function(row)
		return row
	end,
}

local column_path_coord = 
{
	name = 'Коорд.', 
	width = 80, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local prop = mark.prop
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		return string.format('%3d км %05.1f', km, m + mm/1000.0)
	end,
	sorter = function(mark)
		return {mark.prop.SysCoord}
	end
}

local column_rail = 
{
	name = 'Р', 
	width = 33, 
	align = 'c', 
	text = function(row)
		local mark = work_marks_list[row]
		local rail_mask = bit32.band(mark.prop.RailMask, 0x3)
		
		local left_mask = tonumber(Passport.FIRST_LEFT) + 1
		local rail_name = left_mask == rail_mask and "пр" or "лев"
		local kup_cor = rail_mask == 1 and 'Куп' or 'Кор'
		return kup_cor
	end,
	sorter = function(mark)
		return { bit32.band(mark.prop.RailMask, 0x3) }
	end
}

local column_mag_use_recog = 
{
	name = 'Расп.', 
	width = 40, 
	align = 'l', 
	text = function(row)
		local mark = work_marks_list[row]
		local rec = mark.ext.VIDEO_RECOGNITION
		local v = 
		{
			[1] = 'Да',
			[0] = 'нет',
			[-1] = 'Ошиб.',
		}
		return v[rec] or rec or '-'
	end,
	sorter = function(mark)
		local r = mark.ext.VIDEO_RECOGNITION
		return {r or -2}
	end
}

local function make_column_recogn_width(name, source)
	return {
		name = name, 
		width = 30, 
		align = 'r', 
		text = function(row)
			local mark = work_marks_list[row]
			local w = mark_helper.GetGapWidthName(mark, source)
			return w and sprintf('%2d', w) or ''
		end,
		sorter = function(mark)
			local w = mark_helper.GetGapWidthName(mark, source)
			return {w or 0}
		end
	}
end

local column_recogn_width_inactive = make_column_recogn_width("ШНГ", 'inactive')
local column_recogn_width_active = make_column_recogn_width("ШРГ", 'active')
local column_recogn_width_tread = make_column_recogn_width("ШПК", 'thread')
local column_recogn_width_user = make_column_recogn_width("ШП", 'user')
local column_recogn_width = make_column_recogn_width("Шир")

local column_recogn_rail_gap_step = 
{
	name = 'Ступ', 
	width = 40, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local r = GetRailGapStep(mark)
		return r or ''
	end,
	sorter = function(mark)
		local r = GetRailGapStep(mark)
		r = r and r or -1
		return {r}
	end
}

local column_recogn_reability = 
{
	name = 'Дст', 
	width = 32, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local r = mark.ext.VIDEOIDENTRLBLT
		return r
	end,
	sorter = function(mark)
		local r = mark.ext.VIDEOIDENTRLBLT
		r = r and tonumber(r) or 0
		return {r}
	end
}


local column_recogn_video_channel = 
{
	name = 'Кнл', 
	width = 40, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local channels = mark_helper.GetSelectedBits(mark.prop.ChannelMask)
		return table.concat(channels, ',')
	end,
	sorter = function(mark)
		return mark.prop.ChannelMask
	end
}

local column_recogn_bolt = 
{
	name = 'Б/Д', 
	width = 30, 
	align = 'c', 
	text = function(row)
		local mark = work_marks_list[row]
		local all, defect = mark_helper.GetCrewJointCount(mark)
		return all and all ~=0 and sprintf('%d/%d', all, defect) or ''
	end,
	sorter = function(mark)
		local all, defect = mark_helper.GetCrewJointCount(mark)
		defect = (all and all == 0) and -1 or defect
		return {defect}
	end
}

-- колич нормальных болтов в половине накладки
local joint_speed_limit_messages = {
	[0] = 'ЗАКРЫТИЕ',
	[1] = '<25 км/ч',
}

local column_joint_speed_limit = 
{
	name = 'Огр. скор.', 
	width = 65, 
	align = 'c', 
	text = function(row)
		local mark = work_marks_list[row]
		local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
		return valid_on_half and (joint_speed_limit_messages[valid_on_half] or '??') or ''
	end,
	sorter = function(mark)
		local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
		return {valid_on_half or -1}
	end
}

local column_beacon_offset = 
{
	name = 'Смещ.', 
	width = 50, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local offset = GetBeaconOffset(mark)
		return offset and sprintf('%2d', offset) or ''
	end,
	sorter = function(mark)
		local r = mark.ext.VIDEO_RECOGNITION
		local offset = GetBeaconOffset(mark)
		return {offset}
	end
}
	
local fastener_type_names = {
	[0] = 'КБ-65',
	[1] = 'Аpc',
	[2] = 'КД',
}
	
local fastener_fault_names = {
	[0] = 'норм.',
	[1] = 'От.ЗБ', 
	[2] = 'От.Кл',
}
	
local column_fastener_type = 
{
	name = 'Тип', 
	width = 50, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local FastenerType = GetFastenerParamName1(mark, 'FastenerType')
		return FastenerType and (fastener_type_names[tonumber(FastenerType)] or FastenerType) or ''
	end,
	sorter = function(mark)
		local FastenerType = GetFastenerParamName1(mark, 'FastenerType')
		return {FastenerType and tonumber(FastenerType) or 0}
	end
}

local column_fastener_fault = 
{
	name = 'Сост.', 
	width = 50, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local FastenerFault = GetFastenerParamName1(mark, 'FastenerFault')
		return FastenerFault and (fastener_fault_names[tonumber(FastenerFault)] or FastenerFault) or ''
	end,
	sorter = function(mark)
		local FastenerFault = GetFastenerParamName1(mark, 'FastenerFault')
		return {FastenerFault and tonumber(FastenerFault) or 0}
	end
}

local function GetFastenerWidth(mark)
	local polygon = GetFastenerParamName(mark, "Coord")
	if polygon then
		local points = table.pack(string.match(polygon .. ',', string.rep('(-?%d+)%D+', 8)))
		return points[5] - points[1]
	end
	return 0
end
	

local column_fastener_width = 
{
	name = 'Шир', 
	width = 40, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local w = GetFastenerWidth(mark)
		return sprintf('%d', w)
	end,
	sorter = function(mark)
		local w = GetFastenerWidth(mark)
		return {w}
	end
}

local recognition_guids = {
	"{CBD41D28-9308-4FEC-A330-35EAED9FC801}", 
	"{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC804}",
}			
				
--=========================================================================== --

local Filters = 
{
	--{	
	--	name = 'Магнитные Стыки', 		
	--	columns = {
	--		column_num,
	--		column_path_coord, 
	--		column_rail,
	--		column_mag_use_recog,
	--		}, 
	--	GUIDS = {
	--		"{19253263-2C0B-41EE-8EAA-000000000010}",
	--		"{19253263-2C0B-41EE-8EAA-000000000040}",}
	--},
	{
		name = 'Стыковые зазоры', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_recogn_width_inactive,
			column_recogn_width_active,
			column_recogn_width_tread,
			column_recogn_width_user,
			column_recogn_bolt,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
	},
	{
		name = 'Отсутствующие болты (вне норматива)', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_recogn_bolt,
			column_joint_speed_limit,
			--column_recogn_reability,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
			return valid_on_half and valid_on_half < 2
		end,
	},
	{
		name = 'Маячные отметки',
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_beacon_offset,
			}, 
		GUIDS = {
			"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}",
			"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",}
	},
	{
		name = 'Скрепления',
		columns = {
			column_num,
			column_path_coord, 
			column_rail,
			column_fastener_type,
			column_fastener_fault,
--			column_recogn_reability,
--			column_fastener_width,
			}, 
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",}
	},
	{
		name = 'Горизонтальные ступеньки', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_recogn_width,
			column_recogn_rail_gap_step,
			}, 
		GUIDS = recognition_guids,
	},
}

-- внутренняя функция, возвращает описание фильтра по его имени
local function get_filter_by_name(name)
	for _, filter in ipairs(Filters) do
		if filter.name == name then
			return filter
		end
	end
end

-- ======================================================================= -- 

-- функция вызывается из программы, для получения списка имен доступных фильтров
function GetFilterNames()
	local names = {}
	for _, filter in ipairs(Filters) do
		table.insert(names, filter.name)
	end
	return names
end

-- функция вызывается из программы, для получения описания столбцов таблицы, функция возвращает массив таблиц с полями "name", "width" и "align".
function GetColumnDescription(name)
	local filter = get_filter_by_name(name)
	return filter and filter.columns or {}
end

-- функция вызывается из программы, при выборе пользователем одного из фильтров, тут следует сформировать список отметок, и вернуть его длинну
function InitMark(name)
	local filter = get_filter_by_name(name)
	if filter then
		if work_filter ~= filter then
			local fn_filter = filter.filter
			work_filter = filter
			work_marks_list = {}
			local marks = Driver:GetMarks{GUIDS=filter.GUIDS}
			for i = 1, #marks do
				local mark = marks[i]
				if not fn_filter or fn_filter(mark) then 
					table.insert(work_marks_list, mark)
				end
			end
		end
	else
		work_marks_list = {}
		work_filter = None
	end
	return #work_marks_list
end

-- функция вызывается из программы, для запроса текста в ячейке по заданным координатам
function GetItemText(row, col)
	-- print (row, col, #work_marks_list, #work_columns)
	if row > 0 and row <= #work_marks_list and 
	   work_filter and col > 0 and col <= #(work_filter.columns) then
		local fn = work_filter.columns[col].text
		if fn then
			local res = fn(row)
			return res
		end
	end
	return ''
end

-- функция вызывается из программы, для получения ID отметки в заданной строке
function GetMarkID(row)
	-- print (row, col, #work_marks_list, #work_columns)
	if row > 0 and row <= #work_marks_list then
		local mark = work_marks_list[row]
		if mark and mark.prop then 
			return mark.prop.ID
		end
	end
	return -1
end

-- функция вызывается из программы, при переключении пользователем режима сортировки
function SortMarks(col, inc)
	if work_sort_param[0] ~= col or work_sort_param[1] ~= inc then 
		work_sort_param[0] = col
		work_sort_param[1] = inc
		
		if work_marks_list and work_filter and col > 0 and col <= #(work_filter.columns) then
			local column = work_filter.columns[col]
			local fn = column.sorter
			if fn then
				work_marks_list = sort_marks(work_marks_list, fn, inc)
			end
		end
	end
end
