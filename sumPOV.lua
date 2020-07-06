local hkey = require "windows_registry"

if not ATAPE then
	require "iuplua" 
	iup.SetGlobal('UTF8MODE', 1)
end


local reg_path = "Software\\Radioavionika\\SumPOV\\"
local HKEY_POV_edit = hkey.HKEY_CURRENT_USER:create(reg_path .. "edit") -- хранение свойств отметок редактирования

local PARAMETERS = 
{
	{	
		sign = "POV_OPERATOR",
		variants = {"Нет", "Да"},
		dialog = "Подтверждено оператором",
		desc = "Оператор",
	},{	
		sign = "POV_EAKSUI",
		variants = {"Нет", "Подготовлено", "Отправлено"},
		dialog = "Отметки для отправки в ЕКАСУИ",
		desc = "ЕКАСУИ",
	},{	
		sign = "POV_REPORT",
		variants = {"Нет", "Да"},
		dialog = "Отметки для формирования отчетов",
		desc = "Отчеты",
	},{	
		sign = "POV_REJECTED",
		variants = {"Нет", "Да"},
		dialog = "Отвергнутые",
		desc = "Отвергнутые",
	}
}

-- ==============================================================

-- прочитаем значения из реестра
local function read_reg()
	local values = {}
	for i, item in ipairs(PARAMETERS) do
		local value = HKEY_POV_edit:queryvalue(item.sign)
		if value and type(value) == 'number' then
			values[i] = tonumber(value)
		else
			values[i] = 0
		end
	end
	return values
end

-- сортировка списка отметок по ID
local function sort_marks_id(marks)
	local ids = {}
	local id2mark = {}
	for i, mark in ipairs(marks) do
		local mark_id = mark.prop.ID
		ids[i] =  mark_id
		id2mark[mark_id] = mark
	end
	table.sort(ids)
	local res = {}
	for i, mark_id in ipairs(ids) do
		res[i] = id2mark[mark_id]
	end
	return res
end



local function show_settings(values, title)
	local fmt = ''
	for _, item in ipairs(PARAMETERS) do
		fmt = fmt .. string.format("%s: %%o|%s|\n", item.dialog, table.concat(item.variants, "|"))
	end
	
	-- запрос у пользователя
	local res = {iup.GetParam(title, nil, fmt, table.unpack(values))}
	
	if table.remove(res, 1) then -- pop first element
		return res
	end
end


-- ========================= EXPORT =============================

--[[ отображение диалога настройки параметров
вызывается из программы или из скрипта 
]]
function ShowSettings()
	local values = read_reg() 	-- прочитаем значения из реестра

	local title = "Настройка подтверждающих отметок видеораспознавания"
	values = show_settings(values, title) -- запрос у пользователя
	if values then
		for i, item in ipairs(PARAMETERS) do
			HKEY_POV_edit:setvalue(item.sign, values[i])
		end
		return true
	end
end

-- сформировать описание текущих настроек
function GetCurrentSettingsDescription()
	local reg_values = read_reg() 	-- прочитаем значения из реестра
	local res = {}
	
	for i, item in ipairs(PARAMETERS) do 
		local val = reg_values[i]
		local t = '??'
		if 0 <= val and val < #(item.variants) then
			t = item.variants[val+1]
		end
		local text = string.format("%s: %s", item.desc, t)
		table.insert(res, text)
	end
	return table.concat(res, ' | ')
end


--[[ установить флаги отметки в соответстви c настройками
]]
function UpdateMarks(marks, save_marks)
	-- если передана одна отметка, а не список, делаем список
	if marks.prop or marks.ext then marks = {marks}	end
	
	local reg_values = read_reg() 	-- прочитаем значения из реестра
	
	for _, mark in ipairs(marks) do
		for i, item in ipairs(PARAMETERS) do
			mark.ext[item.sign] = reg_values[i]
		end
		if save_marks then
			mark:Save()
		end
	end
end

--[[ пользователю предлагается окно редактирования значения 
(с отображением предыдущего) и выбор флагов ПОВ (флаги по умолчанию 
соответствуют с выбранному сценарию).
]]
function EditMarks(marks, save_marks)
	if marks.prop or marks.ext then marks = {marks}	end 	-- если передана одна отметка, а не список, делаем список
	if #marks == 0 then return end
	
	local reg_values = read_reg() 	-- прочитаем значения из реестра
	
	-- прочитать параметры отметки
	local mark_params = {}
	for i, item in ipairs(PARAMETERS) do
		mark_params[i] = marks[1].ext[item.sign] or reg_values[i] or 0
	end
	
	local title = "Настройка флагов ПОВ отметки"	
	mark_params = show_settings(mark_params, title) -- запрос у пользователя
	if mark_params then
		for _, mark in ipairs(marks) do
			for i, item in ipairs(PARAMETERS) do
				mark.ext[item.sign] = mark_params[i]
			end
			if save_marks then mark:Save() end
		end
	end
end

--[[ Для ряда объектов (шпалы, ..) вводится пункт меню Отвергнуть дефектность. 
При этом устанавливается соответствующий флаг ПОВ.
]]
function RejectDefects(marks, save_marks)
	if marks.prop or marks.ext then marks = {marks}	end 	-- если передана одна отметка, а не список, делаем список
	
	for _, mark in ipairs(marks) do
		mark.ext['POV_REJECTED'] = 1

		if save_marks then mark:Save() end
	end
end

function AcceptEKASUI(marks, save_marks, accept)
	if marks.prop or marks.ext then marks = {marks}	end 	-- если передана одна отметка, а не список, делаем список
	
	for _, mark in ipairs(marks) do
		mark.ext['POV_EAKSUI'] = accept and 1 or 0
		if save_marks then mark:Save() end
	end
end

function IsAcceptEKASUI(mark, save_marks)
	return mark and mark.ext and mark.ext['POV_EAKSUI'] == 1
end



function MakeReportFilter(mode, tip)
	local reg = hkey.HKEY_CURRENT_USER:create(reg_path .. mode)
	
	local fmt = ''
	local values = {}
	local groups = {}
	
	for i, item in ipairs(PARAMETERS) do
		groups[i] = {}
		local reg_val = reg:queryvalue(item.sign) or 0
		fmt = fmt .. string.format("%s: %%t|\n", item.desc)
		for vi, var in ipairs(item.variants) do
			fmt = fmt .. string.format("%s: %%b[пропустить,Включить]|\n", var)
			table.insert(groups[i], #values)
			table.insert(values, bit32.band(reg_val, bit32.lshift(1,vi-1)))
		end
	end

	local function param_action(dialog, param_index)
		if param_index == iup.GETPARAM_OK then 
			-- проверяем, что группы не пустые
			local failed = {}
			for i, group in ipairs(groups) do
				local s = 0
				for _, idx in ipairs(group) do
					local param = iup.GetParamParam(dialog, idx)
					s = s + param.value
				end
				if s == 0 then
					table.insert(failed, PARAMETERS[i].desc)
				end
			end
			if #failed ~= 0 then
				local msg = 'Empty Group: ' .. table.concat(failed, ', ')
				iup.Message('ERROR', msg)
				return 0
			end
		end
		return 1
	end

	local title = "Настройка ПОВ фильтрации отчета"
	if tip then title = title .. ": " .. tip end

	local res = {iup.GetParam(title, param_action, fmt, table.unpack(values))}  -- !!!!!
	
	local masks = {}
	if table.remove(res, 1) then -- pop first element
		-- save to registry
		for i, item in ipairs(PARAMETERS) do
			local mask = 0
			for vi, var in ipairs(item.variants) do
				local user_value = table.remove(res, 1)
				if user_value ~= 0 then
					mask = bit32.bor(mask, bit32.lshift(1, vi-1))
				end
			end
			reg:setvalue(item.sign, mask)
			masks[item.sign] = mask
		end
		
		return function (mark)
			if not mark or not mark.ext then return false end
			for name, mask in pairs(masks) do
				local val = mark.ext[name]
				if val then
					local mm = bit32.lshift(1, val)
					--print(name, mask, mm)
					if not bit32.btest(mm, mask) then
						return false
					end
				else
					--return false
				end
			end
			return true
		end
	end
end


-- =====================================================

--local fltr = MakeReportFilter('ekasui', 'EKASUI')
--local mark = {ext={POV_OPERATOR=1, POV_EAKSUI=0, POV_REPORT=0, POV_REJECTED=0}}
--print(fltr(mark))
--ShowSettings()
--print(GetCurrentSettingsDescription())

-- =====================================================

return 
{
	ShowSettings = ShowSettings,
	UpdateMarks = UpdateMarks,
	GetCurrentSettingsDescription = GetCurrentSettingsDescription,
	EditMarks = EditMarks,
	RejectDefects = RejectDefects,
	AcceptEKASUI = AcceptEKASUI,
	IsAcceptEKASUI = IsAcceptEKASUI,
	MakeReportFilter = MakeReportFilter
}
