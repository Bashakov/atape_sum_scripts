mark_helper = require 'sum_mark_helper'
stuff = require 'stuff'

local sprintf = stuff.sprintf
local printf = stuff.printf
local table_find = stuff.table_find

local SelectNodes = mark_helper.SelectNodes
local sort_marks = mark_helper.sort_marks
local reverse_array = mark_helper.reverse_array
local sort_stable = mark_helper.sort_stable
local shallowcopy = mark_helper.shallowcopy
local deepcopy = mark_helper.deepcopy

-- =====================================================================  

-- для запуска и из атейпа и из отладчика
local function my_dofile(file_name)
	local errors = ''
	
	for _, path in ipairs{file_name, 'Scripts/' .. file_name} do
		local ok, data = pcall(function() return dofile(path)	end)
		if ok then
			return data
		end
		errors = errors .. '\n' .. data
	end

	error(errors)
end

table.append = function (dst, src)
	for _, item in ipairs(src) do
		dst[#dst+1] = item
	end
end

-- =====================================================================  



my_dofile "sum_list_pane_guids.lua"
my_dofile "sum_list_pane_columns.lua"

local filters_video = my_dofile "sum_list_pane_filters_video.lua"
local filters_uzk = my_dofile "sum_list_pane_filters_uzk.lua"
local filters_magn = my_dofile "sum_list_pane_filters_magn.lua"
local filters_npu = my_dofile "sum_list_pane_filters_npu.lua"
local filters_visible = my_dofile "sum_list_pane_filters_visible.lua" 

local Filters = {}
table.append(Filters, filters_video)
table.append(Filters, filters_uzk)
table.append(Filters, filters_magn)
table.append(Filters, filters_npu)
table.append(Filters, filters_visible)

-- =====================================================================  

work_marks_list = {}
work_filter = None
work_sort_param = {0, 0}
selected_row = 0

--=========================================================================== --
--=========================================================================== --


-- внутренняя функция, находи фильтр по его имени
local function get_filter_by_name(name)
	for _, filter in ipairs(Filters) do
		if filter.name == name then
			return filter
		end
	end
end

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



local function fetch_groups()
	local lst = {}
	
	for _, filter in ipairs(Filters) do
		local g = filter.group
		local f = filter.name
		if type(g) == 'string' then
			table.insert(lst, {g, f})
		elseif type(g) == 'table' then
			for _, gn in ipairs(g) do
				table.insert(lst, {gn, f})
			end
		end
	end
	
	local groups = {}
	for _, v in ipairs(lst) do
		local g, f = table.unpack(v)
		if not groups[g] then
			groups[g] = {}
		end
		groups[g][f] = true
	end
	
	return groups
end

-- ======================================================================= -- 

-- функция вызывается из программы, для получения списка имен доступных фильтров
function GetGroupNames()
	local groups = fetch_groups()
	local names = {}
	for n, f in pairs(groups) do table.insert(names, n) end
	table.sort(names)
	return names							-- возвращаем массив с названиями
end

-- функция вызывается из программы, для получения списка имен доступных фильтров
function GetFilterNames(group_name)
	local names = {}						-- объявляем массив для названий
	local group = nil
	
	if group_name and group_name ~= '' then
		local groups = fetch_groups()
		group = groups[group_name] or {}
	end
		
	for _, filter in ipairs(Filters) do		-- проходим по всем фильтрам
		if not group or group[filter.name] then
			table.insert(names, filter.name)	-- и их названия добавляем в массив 
		end
	end

	return names							-- возвращаем массив с названиями
end

-- функция вызывается из программы, для получения описания столбцов таблицы, функция возвращает массив таблиц с полями "name", "width" и "align".
function GetColumnDescription(name)
	local filter = get_filter_by_name(name)
	return filter and filter.columns or {}
end

-- функция вызывается из программы, при выборе пользователем одного из фильтров, 
-- тут следует сформировать список отметок, и вернуть его длинну
function InitMark(name)
	local filter = get_filter_by_name(name)		-- ищем фильтр по имени
	if filter then								-- если нашли
		if work_filter ~= filter then			-- и если фильтр не тот что был до этого
			work_filter = filter				-- делаем найденный фильтр - рабочим
			work_marks_list = {}				-- обнуляем список отметок
			local marks = Driver:GetMarks{		-- запрашиваем у дравера новый список отметок
				GUIDS=filter.GUIDS, 			-- с указанными типами
				ListType = filter.visible and 'visible' or 'all'}
			local fn_filter = filter.filter		-- берем функцию фильтрации по отметкам
			for i = 1, #marks do				-- проходим по отметкам, полученым из драйвера
				local mark = marks[i]			
				if not fn_filter or fn_filter(mark) then 	-- если функция фильтрации, то проверяем отметку
					table.insert(work_marks_list, mark)		-- сохраняем отметку в рабочий список
				end
			end
			if filter.post_load then			-- если объявлена функция пост обработки
				work_marks_list = filter.post_load(work_marks_list)	-- то запускаме ее
			end
		end
	else										-- если фильтр с именем не найден
		work_marks_list = {}					-- очищаем список
		work_filter = None
		selected_row = 0
	end
	return #work_marks_list						-- возврвщаем длинну списка, чтобы атейп зарезервировал таблицу
end

-- функция вызывается из программы, для запроса текста в ячейке
function GetItemText(row, col)
	-- print (row, col, #work_marks_list, #work_columns) -- отладочная печать
	if row > 0 and row <= #work_marks_list and 		-- если номер строки валидный
	   work_filter and 								-- задан рабочий фильтр
	   col > 0 and col <= #(work_filter.columns) 	-- и номер колонки валиден
	then	
		local fn = work_filter.columns[col].text -- в описании колонки берем метод получения текста
		if fn then								
			local res = fn(row)					-- и вызываем его, предавая номер строки
			return tostring(res)				-- возвращаем результат в программу
		end
	end
	return ''
end

-- функция вызывается из программы, для запроса текста подсказки
function GetToolTip(row, col)
	--print ('GetToolTip', row, col) -- отладочная печать
	local mark = work_marks_list[row]
	local res = sprintf('tooltip\nrow = %d\ncol = %d', row, col)

	if mark then
		res = res .. '\n' .. mark.prop.Description
	end
	return res
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
	
	selected_row = 0
	work_sort_param[0] = col
	work_sort_param[1] = inc
end

-- функция вызывается из программы, для запроса текста в ячейке
function GetItemColor(row, col)
	if selected_row == row  then
		return {0xffffff, 0x0000ff}
	end
			
	if row > 0 and row <= #work_marks_list and work_filter and col > 0 and col <= #(work_filter.columns) then
		local fnFilter = work_filter.get_color
		if fnFilter then
			return fnFilter(row, col)
		end
		local fnColumn = work_filter.columns[col].get_color
		if fnColumn then
			return fnColumn(row)
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
		
		local mark = work_marks_list[cell.row]
		if mark and mark.prop and mark.prop.ID then 
			Driver:JumpMark(mark.prop.ID)	
		end
	end
	
	if act == 'right_click' then
		if cell.row > 0 and cell.row <= #work_marks_list and work_filter and cell.col > 0 and cell.col <= #(work_filter.columns) then
			local fn_context_menu = work_filter.on_context_menu or work_filter.columns[cell.col].on_context_menu
			if fn_context_menu then
				fn_context_menu(cell.row, cell.col)
			end
		end
	end
end

function OnKey(key, down, flags)
	print(key, down, flags)
	if down then
		local step_page = MarkTable:GetRowPerPage() - 1
		local new_selected_row = -1
		
		if key == "Up"   		then new_selected_row = selected_row - 1 			end
		if key == "Down" 		then new_selected_row = selected_row + 1 			end
		if key == "Home" 		then new_selected_row = 1 							end
		if key == "End" 		then new_selected_row = #work_marks_list 			end
		if key == "Page Up" 	then new_selected_row = selected_row - step_page; 	end
		if key == "Page Down" 	then new_selected_row = selected_row + step_page; 	end

		if new_selected_row ~= -1 then
			new_selected_row = math.max(new_selected_row, 1)
			new_selected_row = math.min(new_selected_row, #work_marks_list)

			if new_selected_row > 0 and new_selected_row ~= selected_row then
				set_selected_row(new_selected_row)
				MarkTable:EnsureVisible(new_selected_row)
				
				local mark = work_marks_list[new_selected_row]
				if mark and mark.prop and mark.prop.ID then 
					Driver:JumpMark(mark.prop.ID)	
				end
			end
		end
	end
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


-- ============================================================= --
-- 						  отладка
-- ============================================================= --

if not ATAPE then
	--local g = GetGroupNames()
	--local n = GetFilterNames("Зазоры")

	test_report  = require('test_report')
	local psp_path = 'D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml'
	--local psp_path = 'D:/ATapeXP/Main/494/multimagnetic/2018_01_25/Avikon-03M/12216/[494]_2018_01_03_01.xml'
	test_report(psp_path)
	
	local name  = 'Стыковые зазоры'
	
	local columns = GetColumnDescription(name)
	local col_fmt = {}
	local col_names = {}
	
	for _, col in ipairs (columns) do
		table.insert(col_names, col.name)
		table.insert(col_fmt, sprintf('%%%ds', col.width/8))
	end
	col_fmt = table.concat(col_fmt, ' | ')
	local str_header = sprintf(col_fmt, table.unpack(col_names))
	print(str_header)
	print(string.rep('=', #str_header))
	
	local cnt_row = InitMark(name)
	for row = 1, cnt_row do
		local values = {}
		for col = 1, #columns do
			local text = GetItemText(row, col)
			table.insert(values, text)
		end
		local text_row = sprintf(col_fmt, table.unpack(values))
		print(text_row)
	end
end
