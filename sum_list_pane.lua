if not ATAPE then
	HUN = true
end

mark_helper = require 'sum_mark_helper'

local SelectNodes = mark_helper.SelectNodes
local sort_marks = mark_helper.sort_marks
local reverse_array = mark_helper.reverse_array
local sort_stable = mark_helper.sort_stable
local shallowcopy = mark_helper.shallowcopy
local deepcopy = mark_helper.deepcopy
local table_find = mark_helper.table_find
local sprintf = mark_helper.sprintf
local printf = mark_helper.printf


if iup then
	iup.SetGlobal('UTF8MODE', 1)
end


MK_SHIFT     =  0x0004
MK_CONTROL   =	0x0008

-- =====================================================================  

-- для запуска и из атейпа и из отладчика
local function my_dofile(file_name)
	local errors = {}
	local paths = {
		file_name,
		'Scripts\\' .. file_name,
	}
	
	for i = 1,2 do
		for _, path in ipairs(paths) do
		local ok, data = pcall(function() return dofile(path)	end)
		if ok then
			return data
		end
			table.insert(errors, '\n\t' .. data)
	end

		-- https://bt.abisoft.spb.ru/view.php?id=574
		if i == 1 then
			local tmplt = '\\?.lua'
			paths = {}
			for pp in string.gmatch(package.path, "[^;]+") do
				if(pp:sub(-#tmplt) == tmplt) then
					table.insert(paths, pp:sub(1, -#tmplt) .. file_name)
				end
			end
		end
	end
	error(table.concat(errors))
end

-- добавляет содержимое таблицы src в конец dst
table.append = function (dst, src)
	for _, item in ipairs(src) do
		dst[#dst+1] = item
	end
end

-- загрузить фильтры из файлов в списке
local function load_filters(filters, ...)
	for _, file_name in ipairs{...} do
		local file_filters = my_dofile(file_name)
		table.append(filters, file_filters)	
	end
	return filters
end

-- =====================================================================  


my_dofile "sum_list_pane_guids.lua"
my_dofile "sum_list_pane_columns.lua"

local Filters = {}

if not HUN then 
	Filters = load_filters(Filters, 
		"sum_list_pane_filters_video.lua", 
		"sum_list_pane_filters_uzk.lua",
		"sum_list_pane_filters_magn.lua", 
		"sum_list_pane_filters_npu.lua",
		"sum_list_pane_filters_visible.lua",
		"sum_list_pane_filters_user.lua"
		)
else
	Filters = load_filters(Filters, 
		"sum_list_pane_filters_video_uic.lua"
		)
end


-- =====================================================================  

work_marks_list = {}
work_filter = None
work_sort_param = {0, 0}
selected_row = 0
work_mark_ids = {}

--=========================================================================== --
--=========================================================================== --

-- внутренняя функция, находит фильтр по его имени
local function get_filter_by_name(name)
	for _, filter in ipairs(Filters) do
		if filter.name == name then
			return filter
		end
	end
end

-- усатановка выделения на строку (снимает выделенеи с предыдущей)
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


-- проходит по всем фильтрам, строит список групп
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

-- удалить из файла отметку в указанной строке
local function delete_mark(row)
	local mark = work_marks_list[row]
	if mark and mark.prop and mark.ext then -- проверим что объект является именно специальной пользовательской отметкой
		work_mark_ids[mark.prop.ID] = nil
		mark:Delete()
		table.remove(work_marks_list, row)
		MarkTable:SetItemCount(#work_marks_list)
		Driver:RedrawView()
	end
end

-- сделать видеограмму
local function videogram_mark(row, col)
	local mark = work_marks_list[row]
	if mark and mark.prop and mark.ext then -- проверим что объект является именно специальной пользовательской отметкой
		my_dofile "sum_videogram.lua"
		local defect_codes = work_filter and work_filter.videogram_defect_codes
		local videogram_direct_set_defect = work_filter and work_filter.videogram_direct_set_defect
		MakeVideogram('mark', {mark=mark, defect_codes=defect_codes, direct_set_defect=videogram_direct_set_defect})
	end
end


-- дефолтный обработчик ПКМ
local function default_mark_contextmenu(row, col)
	if true then
		package.loaded.sum_context_menu = nil -- для перезагрузки 
		local sum_context_menu = require 'sum_context_menu'
		local RETURN_STATUS = sum_context_menu.RETURN_STATUS
		local GetMenuItems = sum_context_menu.GetMenuItems
		local mark = work_marks_list[row]
		local handlers = GetMenuItems(mark)
		local names = {}
		for i, h in ipairs(handlers) do names[i] = h.name end
		local r = MarkTable:PopupMenu(names)
		if r and handlers[r].fn then
			local status = handlers[r].fn(handlers[r])
			if status == RETURN_STATUS.UPDATE_MARK then
				Driver:RedrawView()
				MarkTable:Invalidate(row)
			end
			if status == RETURN_STATUS.REMOVE_MARK then 
				work_mark_ids[mark.prop.ID] = nil
				table.remove(work_marks_list, row)
				MarkTable:SetItemCount(#work_marks_list)
				Driver:RedrawView()
			end
			if status == RETURN_STATUS.UPDATE_ALL then -- перезагрузка списка
				Driver:RedrawView()
				if work_filter then	
					local cur_filter_name = work_filter.name
					InitMark("")
					MarkTable:SetItemCount(0)
					InitMark(cur_filter_name)
					MarkTable:SetItemCount(#work_marks_list)
				else
					MarkTable:Invalidate()
				end
			end
		end
	else
		local handlers = {
			{text = "Сформировать Выходную форму видеофиксации (д.б. открыт нужный видеокомпонент )", 		fn = videogram_mark},
			{text = "", },
			{text = "Удалить отметку", 	fn = delete_mark},
		}
		local texts = {}
		for _, h in ipairs(handlers) do
			table.insert(texts, h.text)
		end
		local r = MarkTable:PopupMenu(texts)
		if r and handlers[r].fn then
			handlers[r].fn(row, col)
		end
	end
end

-- прыгнуть на отметку в указанной строке
local function jump_mark(row)
	local mark = work_marks_list[row]	-- если row за пределами массива, то вернется nil
	if mark and mark.prop and mark.prop.ID then 
		Driver:JumpMark(mark.prop.ID)	
	end
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
			work_mark_ids = {}					-- очищаем список id отметок
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
			for _, mark in ipairs(work_marks_list) do
				work_mark_ids[mark.prop.ID] = true
			end
			work_marks_list = sort_stable( work_marks_list, column_sys_coord.sorter, true )
		end
	else										-- если фильтр с именем не найден
		work_mark_ids = {}
		work_marks_list = {}					-- очищаем список
		work_filter = None
		selected_row = 0
	end
	work_sort_param = {0, 0}
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
			else
				-- если не нащли обработчик в фильтре или в колонке, то применяем дефолтный с удалением
				default_mark_contextmenu(cell.row, cell.col)
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
				jump_mark(new_selected_row)
			end
		end
	end
	
	if down and selected_row > 0 then
		-- спрятать отметку
		if key == 'H' then	
			local mark = work_marks_list[selected_row]
			work_mark_ids[mark.prop.ID] = nil
			table.remove(work_marks_list, selected_row)
			MarkTable:SetItemCount(#work_marks_list)
			selected_row = 0
		end
		
		-- удалить
		if (key == 'D' or key == 'Delete') then
			if bit32.btest(flags, MK_SHIFT) or 1 == iup.Alarm("ATape", "Подтвердите удаление отметки", "Да", "Нет") then
				delete_mark(selected_row)
				jump_mark(selected_row)
			end
		end
	end
end

-- Вызывается ATape, при нажатии пользователем на иконку отметки
function OnUserClickMark(markID)
	for row, mark in ipairs(work_marks_list) do
		if mark and mark.prop and mark.prop.ID == markID then
			set_selected_row(row)
			MarkTable:EnsureVisible(row)
			break
		end
	end
end


-- функция вызывается из программы, для получения ID отметки в заданной строке
-- устаревашя функция, для старой панели отметок
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

-- функция вызывается из атейп, для определения следует ли показывать эту отметку в центральной полосе
function IsMarkVisible(mark_id)
	return work_mark_ids[mark_id]
end


-- функция вызывается из атейп, для определения списка GUID отображаемых в этом фильтре
function GetFilterGuids(filter_name)
	local filter = work_filter
	if name then
		filter = get_filter_by_name(name)	-- ищем фильтр по имени
	end
	
	if filter then
		return filter.GUIDS or {}
	end
end

-- ============================================================= --
-- 						  отладка
-- ============================================================= --

if not ATAPE then
	for _, g in ipairs(GetGroupNames()) do 
		print(g .. ':')
		for _, n in ipairs(GetFilterNames(g)) do
			print('\t' .. n)
		end
	end
	
	test_report  = require('test_report')
	local psp_path = 'D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml'
	--local psp_path = 'D:/ATapeXP/Main/494/multimagnetic/2018_01_25/Avikon-03M/12216/[494]_2018_01_03_01.xml'
	test_report(psp_path)
	
	local name 
	if HUN then
		name  = 'Surface Defects'
	else
		name  = 'Стыковые зазоры'
	end
	
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
