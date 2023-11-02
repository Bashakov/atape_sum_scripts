-- https://bt.abisoft.spb.ru/view.php?id=932
-- https://bt.abisoft.spb.ru/view.php?id=1006

--local mark_helper = require "sum_mark_helper"
local us_recognition = require "ultrasound_recognition"


local LEVEL = us_recognition.LEVEL
local POSITION = us_recognition.POSITION

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

local columns_channels =
{
	name = 'Каналы',
	width = 80,
	align = 'l',
	text = function(row)
		local mark = work_marks_list[row]
		return us_recognition.get_channels_str(mark)
	end,
	sorter = function(mark)
		return mark.prop.ChannelMask
	end
}

local cmn_columns =
{
	column_num,
	column_path_coord,
	column_length,
	column_rail_lr,
	column_mark_type_name,
	columns_channels,
}


local column_mark_IP =
{
	name = 'IP',
	width = 50,
	align = 'r',
	text = function(row)
		local mark = work_marks_list[row]
		local IP = us_recognition.get_recog_params(mark)
		return IP or ''
	end,
	sorter = function(mark)
		local IP = us_recognition.get_recog_params(mark)
		return IP
	end
}

local function get_mark_color(mark)
	local COLORS = {
		[LEVEL.HI ] = {text={r=0,g=0,b=0}, bg={r=255,g=180,b=200}},
		[LEVEL.MED] = {text={r=0,g=0,b=0}, bg={r=255,g=255,b=200}},
		[LEVEL.LO ] = {text={r=0,g=0,b=0}, bg={r=230,g=255,b=230}},
	}
	local lvl = us_recognition.get_lvl(mark)
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
	GUIDS = us_recognition.GUIDS,
	get_color = get_row_color,
}

local defects_neck_all =
{
	group = group,
	name = 'УЗ дефекты Шейка\\подошва Все',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return
			us_recognition.check_position(mark, POSITION.NECK)
	end,
	get_color = get_row_color,
}

local defects_neck_1 =
{
	group = group,
	name = 'УЗ дефекты Шейка\\подошва 1 уровень',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return
			us_recognition.check_position(mark, POSITION.NECK) and
			us_recognition.get_lvl(mark) == LEVEL.HI
	end,
	get_color = get_row_color,
}

local defects_head_all =
{
	group = group,
	name = 'УЗ Дефекты Головка Все',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return
			us_recognition.check_position(mark, POSITION.HEAD)
	end,
	get_color = get_row_color,
}

local defects_head_1 =
{
	group = group,
	name = 'УЗ Дефекты Головка 1 уровень',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return
			us_recognition.check_position(mark, POSITION.HEAD) and
			us_recognition.get_lvl(mark) == LEVEL.HI
	end,
	get_color = get_row_color,
}

local defects_head_2 =
{
	group = group,
	name = 'УЗ Дефекты Головка 2 уровень',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		local lvl = us_recognition.get_lvl(mark)
		return
			us_recognition.check_position(mark, POSITION.HEAD) and
			(lvl == LEVEL.HI or lvl == LEVEL.MED)
	end,
	get_color = get_row_color,
}

-- =============================================== --

local filters =
{
	defects_all,
	defects_neck_all,
	defects_neck_1,
	defects_head_all,
	defects_head_1,
	defects_head_2,
}

return filters
