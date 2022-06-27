-- https://bt.abisoft.spb.ru/view.php?id=932
local TYPES = require 'sum_types'
local mark_helper = require "sum_mark_helper"

-- создать таблицу из переданных аргументов, если аргумент таблица, то она распаковывается рекурсивно
local function concat(...)
	local res = {}

	for _, item in ipairs{...} do
		for _, val in ipairs(item) do
			res[#res+1] = val
		end
	end

	return res
end


local group = {'АвтоРаспознавание УЗ'}

local cmn_columns =
{
	column_num,
	column_path_coord,
	column_length,
	column_rail_lr,
	column_mark_type_name,
}

local guids =
{
	TYPES.OTMETKA_12,
	TYPES.OTMETKA_16,
}

local LEVEL =
{
	HI = 1,
	MED = 2,
	LO = 3,
	NONE = 4,
}

local function get_recog_params(mark)
	local desc = mark.prop.Description
	local IP, CN, G = string.match(desc, "IP:%s*(%d+)%s*CN:%s*(%d+)%s*G:%s*(%d+)")
	return tonumber(IP), tonumber(CN), tonumber(G)
end

local function get_lvl(mark)
	local IP = get_recog_params(mark)
	if not IP then		return LEVEL.NONE	end
	if IP <= 200 then	return LEVEL.LO		end
	if IP <= 500 then	return LEVEL.MED	end
						return LEVEL.HI
end

local column_mark_IP =
{
	name = 'IP',
	width = 50,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local IP = get_recog_params(mark)
		return IP or ''
	end,
	sorter = function(mark)
		local IP = get_recog_params(mark)
		return IP
	end
}

local function get_mark_color(mark)
	local COLORS = {
		[LEVEL.HI]  = {text={r=0,g=0,b=0}, bg={r=255,g=180,b=200}},
		[LEVEL.MED] = {text={r=0,g=0,b=0}, bg={r=255,g=255,b=200}},
		[LEVEL.LO]  = {text={r=0,g=0,b=0}, bg={r=230,g=255,b=230}},
	}
	local lvl = get_lvl(mark)
	return COLORS[lvl] or {0x000000, 0xffffff}
end

local function get_row_color(row)
	return get_mark_color(work_marks_list[row])
end

-- =============================================== --



local defects_all =
{
	group = group,
	name = 'УЗ Дефекты',
	columns =  concat(cmn_columns, {column_mark_desc}),
	GUIDS = guids,
	get_color = get_row_color,
}

local defects_neck =
{
	group = group,
	name = 'УЗ Дефекты Шейка/подошва',
	columns = cmn_columns,
	GUIDS = guids,
	filter = function(mark)
		return not string.match(mark.prop.Description, "%S")
	end,
	get_color = get_row_color,
}

local defects_head_1 =
{
	group = group,
	name = 'УЗ Дефекты Головка 1 уровень',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = guids,
	filter = function(mark)
		local lvl = get_lvl(mark)
		return lvl <= LEVEL.HI
	end,
	get_color = get_row_color,
}

local defects_head_2 =
{
	group = group,
	name = 'УЗ Дефекты Головка 2 уровень',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = guids,
	filter = function(mark)
		local lvl = get_lvl(mark)
		return lvl <= LEVEL.MED
	end,
	get_color = get_row_color,
}

local defects_head_3 =
{
	group = group,
	name = 'УЗ Дефекты Головка Все',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = guids,
	filter = function(mark)
		local lvl = get_lvl(mark)
		return lvl <= LEVEL.LO
	end,
	get_color = get_row_color,
}

-- =============================================== --

local filters =
{
	defects_all,
	defects_neck,
	defects_head_1,
	defects_head_2,
	defects_head_3,
}

return filters
