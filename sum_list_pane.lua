if not ATAPE then
	HUN = false
end

mark_helper = require 'sum_mark_helper'
local algorithm = require 'algorithm'


local sprintf = mark_helper.sprintf

local sumPOV = require "sumPOV"

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end


local MK_SHIFT     =  0x0004
--local MK_CONTROL   =	0x0008

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
		"sum_list_pane_filters_magn.lua",
		"sum_list_pane_filters_npu.lua",
		"sum_list_pane_filters_visible.lua",
		"sum_list_pane_filters_recog_user.lua",
		"sum_list_pane_filters_ultrasound.lua"
		)
else
	Filters = load_filters(Filters,
		"sum_list_pane_filters_video_uic.lua"
		)
end


-- =====================================================================

work_marks_list = {}
work_filter = nil
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

-- дефолтный обработчик ПКМ
local function default_mark_contextmenu(row, col)
	package.loaded.sum_context_menu = nil -- для перезагрузки
	local sum_context_menu = require 'sum_context_menu'
	local RETURN_STATUS = sum_context_menu.RETURN_STATUS
	local GetMenuItems = sum_context_menu.GetMenuItems
	local mark = work_marks_list[row]
	local handlers = GetMenuItems(mark)
	local r = MarkTable:PopupMenu(handlers)
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
end

-- прыгнуть на отметку в указанной строке
local function jump_mark(row)
	local mark = work_marks_list[row]	-- если row за пределами массива, то вернется nil
	if mark and mark.prop and mark.prop.ID then
		Driver:JumpMark(mark.prop.ID)
	end
end

local function clear_lists()
	work_mark_ids = {}					-- очищаем список id отметок
	work_marks_list = {}				-- обнуляем список отметок
	work_filter = nil
	selected_row = 0
	work_sort_param = {0, 0}
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
			if not filter.hide then					-- проверим что фильтр не скрытый
				table.insert(names, filter.name)	-- и их названия добавляем в массив
			end
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
function InitMark(name, fnContinueCalc)
	fnContinueCalc = fnContinueCalc or function (p) return true end

	local filter = get_filter_by_name(name)		-- ищем фильтр по имени
	if work_filter == filter then				-- если тот что был до этого выходим
		return #work_marks_list
	end
	clear_lists()

	if filter then
		work_filter = filter						-- делаем найденный фильтр - рабочим
		local driver_marks = Driver:GetMarks{		-- запрашиваем у драйвера новый список отметок
			GUIDS=filter.GUIDS, 					-- с указанными типами
			ListType = filter.visible and 'visible' or 'all'}

		local fn_filter = filter.filter				-- берем функцию фильтрации по отметкам
		for i, mark in ipairs(driver_marks) do		-- проходим по отметкам, полученным из драйвера
			local accept = true
			if fn_filter then						-- если функция фильтрации, то проверяем отметку
				accept = fn_filter(mark)
				if not fnContinueCalc(i / #driver_marks) then
					clear_lists()
					return 0
				end
			end
			if accept then
				table.insert(work_marks_list, mark)		-- сохраняем отметку в рабочий список
			end
		end

		if filter.post_load then			-- если объявлена функция пост обработки
			work_marks_list = filter.post_load(work_marks_list, fnContinueCalc)	-- то запускаем ее
		end

		for _, mark in ipairs(work_marks_list) do
			work_mark_ids[mark.prop.ID] = true
		end
		work_marks_list = mark_helper.sort_mark_by_coord(work_marks_list)
	end
	return #work_marks_list						-- возвращаем длину списка, чтобы атейп зарезервировал таблицу
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

	if row > 0 and row <= #work_marks_list and work_filter and col > 0 and col <= #(work_filter.columns) then
		local fnFilter = work_filter.get_tooltip
		if fnFilter then
			local tt = fnFilter(row, col)
			if tt ~= nil then return tostring(tt) end
		end
		local fnColumn = work_filter.columns[col].get_tooltip
		if fnColumn then
			local tt = fnColumn(row)
			if tt ~= nil then return tostring(tt) end
		end
		local fnText = work_filter.columns[col].text
		if fnText then
			local res = fnText(row)
			return tostring(res)
		end
	end
end

-- функция вызывается из программы, при переключении пользователем режима сортировки
function SortMarks(col, inc)
	if work_marks_list and work_filter and col > 0 and col <= #(work_filter.columns) then
		local column = work_filter.columns[col]
		local fn = column.sorter
		if fn then
			if work_sort_param[0] ~= col then
				work_marks_list = mark_helper.sort_stable(work_marks_list, fn, inc)
			elseif work_sort_param[1] ~= inc then
				algorithm.reverse_array(work_marks_list)
			end
		end
	end

	selected_row = 0
	work_sort_param[0] = col
	work_sort_param[1] = inc
end

-- функция вызывается из программы, для запроса цвета в ячейке
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

local function get_filter_jump_fn(cell)
	if cell.row > 0 and cell.row <= #work_marks_list and work_filter and cell.col > 0 and cell.col <= #(work_filter.columns) then
		return work_filter.columns[cell.col].jump or work_filter.jump
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
			local fn_jump = get_filter_jump_fn(cell)
			if fn_jump then
				fn_jump{mark=mark, cell=cell}
			else
				Driver:JumpMark(mark.prop.ID)
			end
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

		-- ПОВ
		if (key == 'A') then -- accept
			local mark = work_marks_list[selected_row]
			if mark and mark.prop and mark.ext then -- проверим что объект является именно специальной пользовательской отметкой
				--sumPOV.AcceptEKASUI(mark, true, not sumPOV.IsAcceptEKASUI(mark))
				sumPOV.UpdateMarks(mark, true)
				MarkTable:Invalidate(selected_row)
			end
		end

		if (key == 'R') then -- reject
			local mark = work_marks_list[selected_row]
			if mark and mark.prop and mark.ext then -- проверим что объект является именно специальной пользовательской отметкой
				sumPOV.RejectDefects(mark, true, not sumPOV.IsRejectDefect(mark))
				MarkTable:Invalidate(selected_row)
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
	-- for _, g in ipairs(GetGroupNames()) do
	-- 	print(g .. ':')
	-- 	for _, n in ipairs(GetFilterNames(g)) do
	-- 		print('\t' .. n)
	-- 	end
	-- end

	local test_report  = require('local_data_driver')
	local psp_path = 'D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml'
	--local psp_path = 'D:/d-drive/ATapeXP/Main/498/Рыбинск-Псков/1/2021_11_25/Avikon-03M/3068/[498]_2021_09_17_35.xml'
	--local psp_path = 'D:/Downloads/932/31883/[507]_2022_04_14_04.xml'
	--local psp_path = "D:/Downloads/1006/123/[500]_2020_03_05_01(1 км 754 м 679 мм - 5 км 765 м 763 мм).xml"

	test_report.Driver(psp_path, nil, {1,1000000})

	local name = 'III Соединители и перемычки'
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
	--SortMarks(6, True)
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
