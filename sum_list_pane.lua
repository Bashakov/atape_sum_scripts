mark_helper = require 'sum_mark_helper'
stuff = require 'stuff'

local sprintf = stuff.sprintf
local printf = stuff.printf
local table_find = stuff.table_find

local SelectNodes = mark_helper.SelectNodes
local sort_marks = mark_helper.sort_marks
local reverse_array = mark_helper.reverse_array
local sort_stable = mark_helper.sort_stable


local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
assert(xmlDom)


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

local column_mark_id = 
{
	name = 'ID', 
	width = 80, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local mark_id = mark.prop.ID
		return mark_id
	end,
	sorter = function(mark)
		return mark.prop.ID
	end
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
		return mark.prop.SysCoord
	end
}

local column_sys_coord = 
{
	name = 'Сист.', 
	width = 70, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local prop = mark.prop
		local s = string.format("%d", prop.SysCoord)
		s = s:reverse():gsub('(%d%d%d)','%1.'):reverse()
		return s
	end,
	sorter = function(mark)
		return mark.prop.SysCoord
	end
}

local column_length = 
{
	name = 'Длн.', 
	width = 40, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local prop = mark.prop
		return sprintf("%.2f", prop.Len / 1000)
	end,
	sorter = function(mark)
		return mark.prop.Len
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
		if rail_mask == 3 then
			return 'Оба'
		end
		
		return rail_mask == 1 and 'Куп' or 'Кор'
	end,
	sorter = function(mark)
		return bit32.band(mark.prop.RailMask, 0x3)
	end
}

local column_rail_lr = 
{
	name = 'Р', 
	width = 35, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local rail_pos = mark_helper.GetMarkRailPos(mark)
		local rails_names = {
			[-1]= 'Лв.', 
			[0] = 'Оба',
			[1] = 'Пр.'
		}
		return rails_names[rail_pos]
	end,
	sorter = function(mark)
		return bit32.band(mark.prop.RailMask, 0x3)
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
		return r or -2
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
			return w or 0
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
		local r = mark_helper.GetRailGapStep(mark)
		return r or ''
	end,
	sorter = function(mark)
		local r = mark_helper.GetRailGapStep(mark)
		r = r and r or 0
		return r
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
		return r
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
		defect = (all and all ~= 0) and -1 or defect or 0
		return defect
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
		return valid_on_half or -1
	end
}

local column_beacon_offset = 
{
	name = 'Смещ.', 
	width = 50, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local offset = mark_helper.GetBeaconOffset(mark)
		return offset and sprintf('%2d', offset) or ''
	end,
	sorter = function(mark)
		local r = mark.ext.VIDEO_RECOGNITION
		local offset = mark_helper.GetBeaconOffset(mark)
		return offset
	end
}
	
local fastener_type_names = {
	[0] = 'КБ-65',
	[1] = 'Аpc',
	[2] = 'КД',
}
	
local fastener_fault_names = {
	[0] = 'норм.',
	[1] = 'От.ЗБ',  -- отсутствие закладного болта kb65
	[2] = 'От.Кл',	-- отсуствие клеммы apc
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
		return FastenerType and tonumber(FastenerType) or 0
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
		return FastenerFault and tonumber(FastenerFault) or 0
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
		return w
	end
}



local function make_column_surf_defect(col_name, attrib)  
	local function get_val(mark)
		local prm = mark_helper.GetSurfDefectPrm(mark)
		return prm and prm[attrib]
	end
	
	return {
		name = col_name, 
		width = 40, 
		align = 'r', 
		text = function(row)
			local mark = work_marks_list[row]
			local val = get_val(mark)
			return val and sprintf('%d', val)
		end,
		sorter = function(mark)
			local val = get_val(mark)
			return val or 0
		end,
	}
end

local column_surf_defect_type = make_column_surf_defect('Тип', 'SurfaceFault')
local column_surf_defect_area = make_column_surf_defect('Плщ', 'SurfaceArea')
local column_surf_defect_len = make_column_surf_defect('Длн', 'SurfaceWidth')  -- https://bt.abisoft.spb.ru/view.php?id=251#c592
local column_surf_defect_wdh = make_column_surf_defect('Шрн', 'SurfaceLength') 

local fishpalte_fault_str = 
{
	[0] = 'испр.',
	[1] = 'надр.',
	[3] = 'трещ.',
	[4] = 'изл.',
}

local column_fishplate_state =
{
	name = "Накл", 
	width = 60, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local fault = mark_helper.GetFishplateState(mark)
		return fishpalte_fault_str[fault] or tostring(fault)
	end,
	sorter = function(mark)
		local fault = mark_helper.GetFishplateState(mark)
		return fault
	end,
}

local NPU_type_str = {"Возм.", "Подтв."}

local NPU_guids = {
	"{19FF08BB-C344-495B-82ED-10B6CBAD508F}",
	"{19FF08BB-C344-495B-82ED-10B6CBAD5090}"
}

local column_npu_type = 
{
	name = 'тип', 
	width = 60, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local prop = mark.prop
		local pos = table_find(NPU_guids, prop.Guid)
		local text = NPU_type_str[pos] or '--'
		return text
	end,
	sorter = function(mark)
		return mark.prop.Guid
	end
}

local column_connections_all = 
{
	name = 'Всего', 
	width = 60, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local all, fault = mark_helper.GetConnectorsCount(mark)
		return all or ''
	end,
	sorter = function(mark)
		local all, fault = mark_helper.GetConnectorsCount(mark)
		return all or 0
	end
}

local column_connections_defect = 
{
	name = 'Дефек.', 
	width = 60, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local all, fault = mark_helper.GetConnectorsCount(mark)
		return fault  or ''
	end,
	sorter = function(mark)
		local all, fault = mark_helper.GetConnectorsCount(mark)
		return fault or 0
	end
}

local column_mark_type_name = 
{
	name = 'Тип', 
	width = 120, 
	align = 'l', 
	text = function(row)
		local mark = work_marks_list[row]
		local name = Driver:GetSumTypeName(mark.prop.Guid)
		return name
	end,
	sorter = function(mark)
		return mark.prop.Guid
	end
}

local column_user_accept = 
{
	name = 'Подт.', 
	width = 33, 
	align = 'c', 
	text = function(row)
		local mark = work_marks_list[row]
		local ua = mark.ext.ACCEPT_USER
		return ua and (ua == 1 and 'да' or 'нет') or ''
	end,
	sorter = function(mark)
		return mark.ext.ACCEPT_USER or -1 
	end
}

local column_sleeper_angle = 
{
	name = 'Разв.', 
	width = 40, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local angle = mark_helper.GetSleeperAngle(mark)
		if angle then
			angle = math.abs(angle)
			angle = angle*180/3.14/1000
			return sprintf('%4.1f', angle)
		end
		return ''
	end,
	sorter = function(mark)
		local angle = mark_helper.GetSleeperAngle(mark)
		return math.abs(angle or 0)
	end
}

local sleeper_meterial_names = 
{
	[1] = "бет",
	[2] = "дер",
}

local column_sleeper_meterial = 
{
	name = 'Матер.', 
	width = 55, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local material = mark_helper.GetSleeperMeterial(mark)
		return sleeper_meterial_names[material] or ''
	end,
	sorter = function(mark)
		local material = mark_helper.GetSleeperMeterial(mark)
		return material or 0
	end
}

local column_sleeper_dist_prev = 
{
	name = 'Пред.', 
	width = 40, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local dist = mark.user.dist_prev
		return dist or ''
		
	end,
	sorter = function(mark)
		local dist = mark.user.dist_prev
		return dist or 0
	end
}
local column_sleeper_dist_next = 
{
	name = 'След.', 
	width = 40, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local dist = mark.user.dist_next
		return dist or ''
		
	end,
	sorter = function(mark)
		local dist = mark.user.dist_next
		return dist or 0
	end
}

local column_weldedbond_status = {
	name = 'Статус.', 
	width = 90, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local status = mark_helper.GetWeldedBondStatus(mark)
		if not status then return '' end
		return status == 0 and '  исправен' or 'НЕИСПРАВЕН'
	end,
	sorter = function(mark)
		local status = mark_helper.GetWeldedBondStatus(mark)
		return status or -1
	end
}

--=========================================================================== --

local recognition_guids = {
	"{CBD41D28-9308-4FEC-A330-35EAED9FC801}", 
	"{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC804}",
}			
			
local recognition_surface_defects = {
	"{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}",
}

--=========================================================================== --

local Filters = 
{
--	{	
--		name = 'Магнитные Стыки', 		
--		columns = {
--			column_num,
--			column_path_coord, 
--			column_rail,
--			column_mag_use_recog,
--			}, 
--		GUIDS = {
--			"{19253263-2C0B-41EE-8EAA-000000000010}",
--			"{19253263-2C0B-41EE-8EAA-000000000040}",}
--	},
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
			column_user_accept,
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
			column_user_accept,
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
			column_user_accept,
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
		name = 'Горизонтальные уступы', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_recogn_width,
			column_recogn_rail_gap_step,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local step = mark_helper.GetRailGapStep(mark)
			return step 
		end,
	},
	{
		name = 'Штепсельные соединители', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_rail_lr,
			column_connections_all,
			column_connections_defect,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local all, fault = mark_helper.GetConnectorsCount(mark)
			return all 
		end,
	},
	{
		name = 'Приварные соединители', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_rail_lr,
			column_weldedbond_status,
			column_mark_id,
		}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local status = mark_helper.GetWeldedBondStatus(mark)
			return status 
		end,
	},
	{
		name = 'Поверхностные дефекты', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_surf_defect_type,
			column_surf_defect_area,
			column_surf_defect_len,
			column_surf_defect_wdh,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_surface_defects,
	},	
	{
		name = 'Дефекты накладок', 
		columns = {
			column_num, 
			column_path_coord, 
			column_rail,
			column_fishplate_state,
			column_recogn_video_channel,
			}, 
		GUIDS = recognition_guids,
		filter = function(mark)
			local fault = mark_helper.GetFishplateState(mark)
			return fault > 0
		end,
	},
	{
		name = 'НПУ', 
		columns = {
			column_num, 
			column_path_coord, 
			column_length,
			--column_rail,
			column_rail_lr,
			column_npu_type,
			}, 
		GUIDS = NPU_guids,
	},
	{
		name = 'Шпалы(эпюра,перпедикулярность)',
		columns = {
			column_num,
			column_path_coord, 
			column_rail, 
			column_sleeper_angle,
			column_sleeper_meterial,
			column_recogn_video_channel,
			column_sleeper_dist_prev,
			column_sleeper_dist_next,
			column_sys_coord,
			}, 
		GUIDS = {
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}"},
		post_load = function(marks)
			local prev_pos = nil
			marks = sort_stable(marks, column_sys_coord.sorter, true)
			for left, cur, right in mark_helper.enum_group(marks, 3) do
				local pp, cp, np = left.prop.SysCoord, cur.prop.SysCoord, right.prop.SysCoord
				cur.user.dist_prev = cp - pp
				cur.user.dist_next = np - cp
			end
			return marks
		end,
	},
	{
		name = 'Видимые', 
		columns = {
			column_num, 
			column_path_coord, 
			column_length,
			--column_rail,
			column_rail_lr,
			column_mark_type_name,
			column_recogn_video_channel,
			}, 
		visible = true,
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
			local marks = Driver:GetMarks{GUIDS=filter.GUIDS, ListType = filter.visible and 'visible' or 'all'}
			for i = 1, #marks do
				local mark = marks[i]
				if not fn_filter or fn_filter(mark) then 
					table.insert(work_marks_list, mark)
				end
			end
			if filter.post_load then
				work_marks_list = filter.post_load(work_marks_list)
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
			return tostring(res)
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
	if work_marks_list and work_filter and col > 0 and col <= #(work_filter.columns) then
		local column = work_filter.columns[col]
		local fn = column.sorter
		if fn then
			if work_sort_param[0] ~= col then 
				work_marks_list = sort_stable(work_marks_list, fn, inc)
			elseif work_sort_param[1] ~= inc then
				reverse_array(work_marks_list)
			end
		end
	end
	
	work_sort_param[0] = col
	work_sort_param[1] = inc
end
