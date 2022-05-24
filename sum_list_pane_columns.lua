mark_helper = require 'sum_mark_helper'

local prev_atape = ATAPE
ATAPE = true -- disable debug code while load scripts
	local sum_report_joints = require "sum_report_joints"
ATAPE = prev_atape

sprintf = mark_helper.sprintf
printf = mark_helper.printf
table_find = mark_helper.table_find

SelectNodes = mark_helper.SelectNodes
sort_marks = mark_helper.sort_marks
reverse_array = mark_helper.reverse_array
sort_stable = mark_helper.sort_stable
shallowcopy = mark_helper.shallowcopy
deepcopy = mark_helper.deepcopy

local DEFECT_CODES = require 'report_defect_codes'
local sumPOV = require "sumPOV"

-- =====================================================================  

-- получить параметр скрепления по имени (разбор xml)
local function GetFastenerParamName(mark, name)
	
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom)
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
	if not x then return nil end

	local req = 'PARAM%s+name%s*=%s*"' .. name .. '"%s*value%s*=%s*"([^"]+)"'
	--local req = 'PARAM%s+name="' .. name .. '"[^>]+value="([^"]+)"'
	local res = string.match(x, req)
	return res
end

local function split(str, sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   str:gsub(pattern, function(c) fields[#fields+1] = c end)
   return fields
end

-- =====================================================================  


column_num = 
{
	name = '№', 
	width = 35, 
	align = 'r',
	text = function(row)
		return row
	end,
	get_tooltip = function (row)
		local mark = work_marks_list[row]
		return sprintf('mark ID = %d', mark.prop.ID)
	end,
}

column_mark_id = 
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

column_path_coord = 
{
	name = 'Коорд.', 
	width = 80, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local prop = mark.prop
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		if km then
			return string.format('%3d км %05.1f', km, m + mm/1000.0)
		end
		return '<*****>'
	end,
	sorter = function(mark)
		return mark.prop.SysCoord
	end,
	get_tooltip = function (row)
		local mark = work_marks_list[row]
		local prop = mark.prop
		return sprintf('сист. коорд. = %s мм', mark_helper.format_sys_coord(prop.SysCoord))
	end,
}

column_path_coord_begin_end =
{
	name = 'Коорд.',
	width = 100,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local prop = mark.prop
		local km1, m1, mm1 = Driver:GetPathCoord(prop.SysCoord)
		local km2, m2, mm2 = Driver:GetPathCoord(prop.SysCoord + prop.Len)
		return string.format('%3d.%03d - %3d.%03d', km1, m1, km2, m2)
	end,
	sorter = function(mark)
		return mark.prop.SysCoord + prop.Len/2
	end
}

column_sys_coord = 
{
	name = 'Сист.', 
	width = 70, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local prop = mark.prop
		return mark_helper.format_sys_coord(prop.SysCoord)
	end,
	sorter = function(mark)
		return mark.prop.SysCoord
	end
}

column_length = 
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
	end,
	
}

column_length_npu = shallowcopy(column_length)

column_length_npu.get_color = function(row)
	local mark = work_marks_list[row]
	local prop = mark.prop
	if prop.Len > 10000 then
		return {0x000000, 0xff9999}
	end
	if prop.Len > 1000 then
		return {0x000000, 0xffeeee}
	end
end

column_rail = 
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

column_rail_lr = 
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



column_mag_use_recog = 
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

function make_column_recogn_width(name, source)
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

column_recogn_width_inactive = make_column_recogn_width("ШНГ", 'inactive')
column_recogn_width_active = make_column_recogn_width("ШРГ", 'active')
column_recogn_width_tread = make_column_recogn_width("ШПК", 'thread')
column_recogn_width_user = make_column_recogn_width("ШП", 'user')
column_recogn_width = make_column_recogn_width("Шир")

column_recogn_rail_gap_step = 
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

column_recogn_reability = 
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


column_recogn_video_channel = 
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

column_recogn_bolt = 
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
		-- defect = (all and all ~= 0) and -1 or defect or 0
		defect = defect or -1
		return defect
	end
}

column_gap_type =
{
	name = 'тип',
	width = 60,
	align = 'c',
	text = function(row)
		local mark = work_marks_list[row]
		local gap_type = mark_helper.GetGapType(mark) -- 0 - болтовой, 1 - изолированный, 2 - сварной
		if gap_type == 0 then
			return 'болтовой'
		elseif gap_type == 1 then
			return "изолированный"
		elseif gap_type == 2 then
			return "сварной"
		end
	end,
	sorter = function(mark)
		local gap_type = mark_helper.GetGapType(mark)
		return gap_type or -1
	end
}


column_joint_speed_limit = 
{
	name = 'Огр. скор.', 
	width = 65, 
	align = 'c', 
	text = function(row)
		local mark = work_marks_list[row]
		local _, limit = sum_report_joints.bolt2defect_limit(mark)
		return limit or ''
	end,
	sorter = function(mark)
		local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
		return valid_on_half or -1
	end
}

column_beacon_offset = 
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

-- найдена рядом с елочкой риска
column_firtree_beacon =
{
	name = 'Найд Риск',
	width = 50, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		if mark.prop.Guid == "{D3736670-0C32-46F8-9AAF-3816DE00B755}" then
			local found = mark.user.correspond_beacon_found
			return found and 'Да' or 'нет'
		end
		return ''
	end,
	sorter = function(mark)
		if mark.prop.Guid == "{D3736670-0C32-46F8-9AAF-3816DE00B755}" then
			local found = mark.user.correspond_beacon_found
			return found and 1 or 0
		end
		return -1
	end,
	get_color = function(row)
		local mark = work_marks_list[row]
		if mark.prop.Guid == "{D3736670-0C32-46F8-9AAF-3816DE00B755}" then
			local found = mark.user.correspond_beacon_found
			--return found and {0x00FF00, 0xFFFFFF} or {0xFF0000, 0xFFFFFF}
			return found and {0x000000, 0xCCFFCC} or {0x000000, 0xFFCCCC}
		end
	end,
}

-- найдена парная маячная отметка
column_pair_beacon =
{
	name = 'Парная',
	width = 50,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		if mark.prop.Guid == "{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}" or
	       mark.prop.Guid == "{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}" then
			return mark.user.pair_beacon_found and 'Да' or 'нет'
		end
		return ''
	end,
	sorter = function(mark)
		if mark.prop.Guid == "{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}" or
	       mark.prop.Guid == "{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}" then
			return mark.user.pair_beacon_found and 1 or 0
		end
		return -1
	end,
	get_color = function(row)
		local mark = work_marks_list[row]
		if mark.prop.Guid == "{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}" or
	       mark.prop.Guid == "{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}" then
			return mark.user.pair_beacon_found and {0x000000, 0xCCFFCC} or {0x000000, 0xFFCCCC}
		end
	end,
}

local fastener_type_names = {
	[0] = 'КБ-65', 
	[1] = 'Аpc',  
	[2] = 'ДО', -- скрепление на деревянной шпале на костылях 
	[3] = 'КД', -- скрепление на деревянной шпале как КБ-65 но на двух шурупах 
}
	
local fastener_fault_names = {
	[0] = 'норм.',
	[1] = 'От.КБ',  -- отсутствие клемного болта kb65
	[2] = 'От.КЛМ',	-- отсуствие клеммы apc
	[10] = 'От.ЗБ',  -- отсутствие закладного болта kb65
	[11] = 'От.КЗБ',  -- отсутствие клемного и закладного болта kb65	
}
	
column_fastener_type = 
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

column_fastener_fault = 
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

function GetFastenerWidth(mark)
	local polygon = GetFastenerParamName(mark, "Coord")
	if polygon then
		local points = table.pack(string.match(polygon .. ',', string.rep('(-?%d+)%D+', 8)))
		return points[5] - points[1]
	end
	return 0
end
	

column_fastener_width = 
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
			return val and sprintf('%d', val) or ''
		end,
		sorter = function(mark)
			local val = get_val(mark)
			return val or 0
		end,
	}
end

column_surf_defect_type = make_column_surf_defect('Тип', 'SurfaceFault')
column_surf_defect_area = make_column_surf_defect('Плщ', 'SurfaceArea')
column_surf_defect_len = make_column_surf_defect('Длн', 'SurfaceLength')  -- https://bt.abisoft.spb.ru/view.php?id=251#c592
column_surf_defect_wdh = make_column_surf_defect('Шрн', 'SurfaceWidth') 

local fishpalte_fault_str = 
{
	[0] = 'испр.',
	[1] = 'надр.',
	[3] = 'трещ.',
	[4] = 'изл.',
}

column_fishplate_state =
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

local NPU_type_str = {"Возм.", "Подтв.", "БС"}

column_npu_type = 
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

column_connections_all = 
{
	name = 'Всего', 
	width = 60, 
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local all, fault = mark_helper.GetConnectorsCount(mark)
		return all or '0'
	end,
	sorter = function(mark)
		local all, fault = mark_helper.GetConnectorsCount(mark)
		return all or 0
	end
}

column_connections_defect = 
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

column_mark_type_name = 
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

column_user_accept = 
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

column_sleeper_angle = 
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
	end,
	get_color = function(row)
		local mark = work_marks_list[row]
		local angle = mark_helper.GetSleeperAngle(mark)
		if not angle then
			return {0x000000, 0xaaaaaa}
		end
		angle = math.abs(angle) *180/3.14/1000 
		if angle > 10 then
			return {0xFF0000, 0xFFaaaa}
		end
	end,
}

sleeperfault2text =
{
	[0] = "undef",
	[1] = "fracture(ferroconcrete)",
	[2] = "chip(ferroconcrete)",
	[3] = "crack(wood)",
	[4] = "rottenness(wood)",
}

column_sleeper_fault =
{
	name = 'дефект',
	width = 80,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local params = mark_helper.GetSleeperFault(mark)
		if params and params.FaultType then
			return sleeperfault2text[params.FaultType] or params.FaultType
		end
		return ''
	end,
	sorter = function(mark)
		local params = mark_helper.GetSleeperFault(mark)
		return params and params.FaultType or 0
	end,
	get_color = function(row)
		local mark = work_marks_list[row]
		local params = mark_helper.GetSleeperFault(mark)
		if params and params.FaultType and params.FaultType > 0 then
			return {0x000000, 0xFFF0F0}
		end
	end,
}

local sleeper_meterial_names =
{
	[1] = "бет",
	[2] = "дер",
}

column_sleeper_meterial = 
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

column_sleeper_dist_prev = 
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

column_sleeper_dist_next = 
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
column_sleeper_epure_defect_user = 
{
	name = 'Код', 
	width = 100, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local dist = mark.user.defect_code
		return dist or ''
		
	end,
	sorter = function(mark)
		local dist = mark.user.defect_code
		return dist or 0
	end
}

column_weldedbond_status = {
	name = 'Статус.', 
	width = 90, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local status = mark_helper.GetWeldedBondStatus(mark)
		return status and status == 0 and '  исправен' or 'НЕИСПРАВЕН'
	end,
	sorter = function(mark)
		local status = mark_helper.GetWeldedBondStatus(mark)
		return status or -1
	end
}

column_weldedbond_defect_code = {
	name = 'Код.', 
	width = 90, 
	align = 'r', 
	text = function(row)
		local mark = work_marks_list[row]
		local code = mark_helper.GetWeldedBondDefectCode(mark)
		return code or ''
	end,
	sorter = function(mark)
		local code = mark_helper.GetWeldedBondDefectCode(mark)
		return code or ''
	end,
	get_tooltip = function (row)
		local mark = work_marks_list[row]
		local code = mark_helper.GetWeldedBondDefectCode(mark)
		return DEFECT_CODES.code2desc(code)
	end,
}

column_mark_desc = 
{
	name = 'Описание', 
	width = 120, 
	align = 'l',
	text = function(row)
		local mark = work_marks_list[row]
		return mark.prop.Description
	end,
	sorter = function(mark)
		return mark.prop.Description
	end
}

local function get_recognition_run_info(mark)
	local info = {}
	local desc = mark and mark.prop.Description
	if desc and #desc > 0 then
		-- print(desc)
		-- print('')
		for _, l in ipairs(split(desc, '\n')) do
			local k, v = string.match(l, '([%w_]+)=(.+)')
			if k and v then
				info[k] = v
			end
		end
	end
	return info
end

local function make_recog_prop_column(name, width, val_fn, sort_fn)
	if type(val_fn) == 'string' then
		local name_val_fn = val_fn
		val_fn = function(info)
			return info[name_val_fn]
		end
	end
	if type(sort_fn) == 'string' then
		local name_sort_fn = sort_fn
		sort_fn = function(info)
			return info[name_sort_fn]
		end
	end
	if not sort_fn then
		sort_fn = val_fn
	end
	return
	{
		name = name, 
		width = width, 
		align = 'r',
		text = function(row)
			local mark = work_marks_list[row]
			local info = get_recognition_run_info(mark)
			return val_fn(info) or ''
		end,
		sorter = function(mark)
			local info = get_recognition_run_info(mark)
			return sort_fn(info) or ''
		end
	}
end

column_recog_run_date = make_recog_prop_column('Произведен', 120, function (info)
	if info.RECOGNITION_START then
		--return info.RECOGNITION_START
		return os.date('%Y-%m-%d %H:%M:%S', info.RECOGNITION_START)
	end
end, 'RECOGNITION_START')

column_recog_run_type = make_recog_prop_column('Тип', 100, function (info)
	local res = ''
	if info.RECOGNITION_TYPE then
		res = res .. info.RECOGNITION_TYPE
	end
	if info.RECOGNITION_MODE then
		res = res .. ' ' .. info.RECOGNITION_MODE
	end
	return res
end)

column_recog_dll_ver = make_recog_prop_column('Версия', 50, 'RECOGNITION_DLL_VERSION')
column_recog_dll_ver_VP = make_recog_prop_column('VR', 50, 'VP_dll_ver')
column_recog_dll_ver_cpu = make_recog_prop_column('CPU', 50, 'cpu_dll_ver')
column_recog_dll_ver_gpu = make_recog_prop_column('GPU', 50, 'gpu_dll_ver')
column_recog_dll_ver_mod = make_recog_prop_column('MOD', 50, 'model_dll_ver')


local function make_POV_column(name, sign)
	local res = {
		name = name, 
		width = 40, 
		align = 'c',
		text = function(row)
			local mark = work_marks_list[row]
			local s = {[0] = "нет", [1] = "Да", [2] = "Отп."}
			return mark.ext[sign] and s[mark.ext[sign]] or ''
		end,
		sorter = function(mark)
			return mark.ext.sign
		end
	}
	return res
end

column_pov_operator = make_POV_column('Oпр.', 'POV_OPERATOR')
column_pov_ekasui = make_POV_column('ЕКАСУИ', 'POV_EAKSUI')
column_pov_report = make_POV_column('Отч.', 'POV_REPORT')
column_pov_rejected = make_POV_column('Отвр.', 'POV_REJECTED')

local pov_names = {"POV_OPERATOR", "POV_EAKSUI", "POV_REPORT", "POV_REJECTED"}

column_pov_common = 
{
	name = 'ПОВ', 
	width = 40, 
	align = 'c',
	text = function(row)
		local mark = work_marks_list[row]
		local res = ''
		for i, sign in ipairs(pov_names) do
			res = res .. (mark.ext[sign] or '.')
		end
		return res
	end,
	sorter = function(mark)
		return 0
	end,
	get_tooltip = function (row)
		local mark = work_marks_list[row]
		return sumPOV.GetMarkDescription(mark, '\n')
	end,
}

column_group_defect_count = 
{
	name = 'Кол.',
	width = 40,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		return  mark.ext.GROUP_DEFECT_COUNT
	end,
	sorter = function(mark)
		return mark.ext.GROUP_DEFECT_COUNT
	end
}

column_ekasui_code =
{
	name = 'ЕКАСУИ',
	width = 85,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		return mark.ext.CODE_EKASUI or ''
	end,
	sorter = function(mark)
		return mark.ext.CODE_EKASUI or ''
	end,
	get_tooltip = function (row)
		local mark = work_marks_list[row]
		local code = mark.ext.CODE_EKASUI
		local desc = code and DEFECT_CODES.code2desc(code) or code
		return desc
	end
}

column_defect_code_list =
{
	name = 'Дефекты',
	width = 85,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local text = mark.user.defect_codes and table.concat(mark.user.defect_codes, ',') or ''
		return text
	end,
	sorter = function(mark)
		local text = mark.user.defect_codes and table.concat(mark.user.defect_codes, ',') or ''
		return text
	end,
	get_tooltip = function (row)
		local mark = work_marks_list[row]
		local r = {}
		for _, code in ipairs(mark.user.defect_codes or {}) do
			table.insert(r, string.format("%s: %s", code, DEFECT_CODES.code2desc(code)))
		end
		return table.concat(r, '\n')
	end
}

column_speed_limit_list =
{
	name = 'Огр.Ск',
	width = 85,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local limit = mark.user.speed_limits and math.min(table.unpack(mark.user.speed_limits)) or nil
		if limit == 0 then
			return "Закрытие"
		end
		return tostring(limit) or ''
	end,
	sorter = function(mark)
		local limit = mark.user.speed_limits and math.min(mark.user.speed_limits) or nil
		return limit
	end,
}
