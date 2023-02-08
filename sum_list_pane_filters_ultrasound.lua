-- https://bt.abisoft.spb.ru/view.php?id=932
-- https://bt.abisoft.spb.ru/view.php?id=1006

--local mark_helper = require "sum_mark_helper"
local us_recognition = require "ultrasound_recognition"


local LEVEL = us_recognition.LEVEL

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

local defects_neck =
{
	group = group,
	name = 'УЗ Дефекты Шейка/подошва',
	columns = cmn_columns,
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return not string.match(mark.prop.Description, "%S")
	end,
	get_color = get_row_color,
}

local defects_head_1 =
{
	group = group,
	name = 'Большие дефекты головки',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return us_recognition.get_lvl(mark) == LEVEL.HI
	end,
	get_color = get_row_color,
}

local defects_head_2 =
{
	group = group,
	name = 'Средние дефекты головки',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return us_recognition.get_lvl(mark) == LEVEL.MED
	end,
	get_color = get_row_color,
}

local defects_head_3 =
{
	group = group,
	name = 'Малые дефекты головки',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return us_recognition.get_lvl(mark) == LEVEL.LO
	end,
	get_color = get_row_color,
}

local defects_head_4 =
{
	group = group,
	name = 'Малые отражатели в головке',
	columns = concat(cmn_columns, {column_mark_IP}),
	GUIDS = us_recognition.GUIDS,
	filter = function(mark)
		return us_recognition.get_lvl(mark) == LEVEL.NONE
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
	defects_head_4,
}

return filters
