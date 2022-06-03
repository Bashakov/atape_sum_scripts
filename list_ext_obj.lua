if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

local OOP = require 'OOP'

local notebook = require "list_ext_obj_notebook"
local kriv = require "list_ext_obj_KRIV"
local iso = require "list_ext_obj_ISO"

local Empty = OOP.class
{
	name = "-----",
	columns =
	{
	},
	ctor = function (self)
		return 0
	end,
	get_object = function (self, row)
	end,
}

local Filters =
{
	Empty,
}

for _, lst in ipairs{notebook.filters, kriv.filters, iso.filters} do
	for _, fltr in ipairs(lst) do
		table.insert(Filters, fltr)
	end
end

-- ======================================================================= --


local currect_filter = nil
local selected_row = -1


-- внутренняя функция, находит фильтр по его имени
local function get_filter_by_name(name)
	for _, filter in ipairs(Filters) do
		--print(string.format("get_filter_by_name(%s) %d:%s", name, i, filter.name))
		if filter.name == name then
			return filter
		end
	end
end

-- установка выделения на строку (снимает выделение с предыдущей)
local function set_selected_row(row)
	local prev_sel = selected_row
	selected_row = row
	if selected_row > 0 then
		MarkTable:Invalidate(selected_row)
	end
	if prev_sel > 0 then
		MarkTable:Invalidate(prev_sel)
	end
end

-- ====================== EXPORT ============================================== --

-- функция вызывается из программы, для получения списка имен доступных фильтров
function GetFilterNames()
	local names = {}						-- объявляем массив для названий

	for _, filter in ipairs(Filters) do		-- проходим по всем фильтрам
		table.insert(names, filter.name)	-- и их названия добавляем в массив
	end

	return names							-- возвращаем массив с названиями
end

-- функция вызывается из программы, для получения описания столбцов таблицы, функция возвращает массив таблиц с полями "name", "width" и "align".
function GetColumnDescription(name)
	local filter = get_filter_by_name(name)
	return filter and filter.columns or {}
end

-- функция вызывается из программы, при выборе пользователем одного из фильтров,
-- тут следует сформировать список отметок, и вернуть его длину
function InitMark(name, fnContinueCalc)
	fnContinueCalc = fnContinueCalc or function (p) return true end
	local cnt = 0
	if not currect_filter or currect_filter.name ~= name then
		currect_filter = {}
		selected_row = -1
		local f = get_filter_by_name(name)
		if f then
			currect_filter, cnt = f(fnContinueCalc)
		end
	end
	return cnt
end

-- функция вызывается из программы, для запроса текста в ячейке
function GetItemText(row, col)
	if not currect_filter then return end
	local object = currect_filter:get_object(row)
	local column = currect_filter.columns[col]
	if column and object then
		local text = column.get_text(row, object)
		if type(text) == "nil" then 
			text = ''
		end
		return tostring(text)
	end
end

-- функция вызывается из программы, при переключении пользователем режима сортировки
function SortMarks(col, inc)
	print(string.format("SortMarks %d %d", col, inc))
end

-- функция вызывается из программы, для запроса текста подсказки
function GetToolTip(row, col)
	if not currect_filter then return end
	local column = currect_filter.columns[col]
	local object = currect_filter:get_object(row)
	if column and object then
		if currect_filter.get_tooltip then
			local tt = currect_filter.get_tooltip(row, col)
			if tt ~= nil then return tostring(tt) end
		end
		if column.get_tooltip then
			local tt = column.get_tooltip(row)
			if tt ~= nil then return tostring(tt) end
		end
	end
end

-- функция вызывается из программы, для запроса цвета в ячейке
function GetItemColor(row, col)
	if selected_row == row  then
		return {0xffffff, 0x0000ff}
	end

	if not currect_filter then return end
	local column = currect_filter.columns[col]
	local object = currect_filter:get_object(row)
	if column and object then
		if currect_filter.get_color then
			return currect_filter.get_color(row, col)
		end
		if column.get_color then
			return column.get_color(row, object)
		end
	end
end

function OnMouse(act, flags, cell, pos_client, pos_screen)
	-- print(act, flags, cell.row, cell.col, pos_client.x, pos_client.y, pos_screen.x, pos_screen.y)

	if act == 'left_click' or act == 'right_click' then
		set_selected_row(cell.row)
	end

	if act == 'left_dbl_click' then
		set_selected_row(cell.row)
	end

	if currect_filter and currect_filter.OnMouse then
		currect_filter:OnMouse(act, flags, cell, pos_client, pos_screen)
	end

	-- if act == 'right_click' then
	-- 	if cell.row > 0 and cell.row <= #work_marks_list and work_filter and cell.col > 0 and cell.col <= #(work_filter.columns) then
	-- 		local fn_context_menu = work_filter.on_context_menu or work_filter.columns[cell.col].on_context_menu
	-- 		if fn_context_menu then
	-- 			fn_context_menu(cell.row, cell.col)
	-- 		else
	-- 			-- если не нащли обработчик в фильтре или в колонке, то применяем дефолтный с удалением
	-- 			default_mark_contextmenu(cell.row, cell.col)
	-- 		end
	-- 	end
	-- end
end
