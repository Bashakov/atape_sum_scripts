local hkey = require "windows_registry"

require 'iuplua'
iup.SetGlobal('UTF8MODE', 1)


local HKEY_POV = hkey.HKEY_CURRENT_USER:create("Software\\Radioavionika\\SumPOV")
local NAMES = {"OPERATOR", "EAKSUI", "REPORT", "REJECTED"}

-- ==============================================================

local function zip(...)
end


-- прочитаем значения из реестра
local function read_reg()
	local values = {}
	for i, name in ipairs(NAMES) do
		local value = HKEY_POV:queryvalue(name)
		if value and type(value) == 'number' then
			values[i] = tonumber(value)
		else
			values[i] = 0
		end
	end
	return values
end

-- прочитать параметры, дял записи в отметку
local function read_mark_params()
	local res = {}
		
	local values = read_reg() 	-- прочитаем значения из реестра
	for i, name in ipairs(NAMES) do
		res['POV_' .. name] = values[i]
	end
	return res
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


-- ========================= EXPORT =============================

--[[ отображение диалога настройки параметров
вызывается из программы или из скрипта 
]]
function ShowSettings()
	local values = read_reg() 	-- прочитаем значения из реестра

	-- запрос у пользователя
	local res = {iup.GetParam("Настройка подтверждающих отметок видеораспознавания", nil, "\z
		Подтверждено оператором: %o|Нет|Да|\n\z
		Отметки для отправки в ЕКАСУИ: %o|Нет|Подготовлено|Отправлено|\n\z
		Отметки для формирования отчетов: %o|Нет|Да|\n\z
		Отвергнутые: %o|Нет|Да|\n\z",
	table.unpack(values))}

	-- если ОК, сохраняем в реестр обратно
	if res[1] then
		for i, name in ipairs(NAMES) do
			HKEY_POV:setvalue(name, res[i+1])
		end
	end
end

-- сформировать описание текущих настроек
function GetCurrentSettingsDescription()
	local desc = 
	{
		{"Оператор",    {"Нет", "Да"}},
		{"ЕКАСУИ",      {"Нет", "Подготовлено", "Отправлено"}},
		{"Отчеты",      {"Нет", "Да"}},
		{"Отвергнутые", {"Нет", "Да"}},
	}
	local reg_values = read_reg() 	-- прочитаем значения из реестра
	local res = {}
	
	for i, val in ipairs(reg_values) do
		local t = '??'
		if 0 <= val and val < #(desc[i][2]) then
			t = desc[i][2][val+1]
		end
		local text = string.format("%s: %s", desc[i][1], t)
		table.insert(res, text)
	end
	return table.concat(res, ' | ')
end


--[[ установить флаги отметки в соответстви c настройками
]]
function UpdateMarks(marks, save_marks)
	-- если передана одна отметка, а не список, делаем список
	if marks.prop or marks.ext then marks = {marks}	end
	
	local params = read_mark_params() 	-- прочитаем значения из реестра
	
	for i, mark in ipairs(marks) do
		for name, value in pairs(params) do
			mark.ext[name] = value
		end
		if save_marks then
			mark:Save()
		end
	end
end

--[[ отфильтровать отметки в соответствии с настройками
]] 
function FilterMarks(marks)
	local params = read_mark_params() 	-- прочитаем значения из реестра
	
	-- если передана одна отметка, а не список, делаем список
	if marks.prop or marks.ext then marks = {marks}	end
	marks = sort_marks_id(marks)	-- сортируем про id, для ускорения доступа к свойствам отметок, которые читаются и кэшируются группами по id
	
	local res = {}
	for _, mark in ipairs(marks) do
		local s = 0
		for name, expt_value in ipairs(params) do
			local mark_val = mark.ext[name] or 100
			if imark_val >= expt_value then
				s = s + 1
			end
		end
		if s == 4 then
			table.insert(res, mark)
		end
	end
	return res
end

-- =====================================================

--ShowSettings()

return 
{
	ShowSettings = ShowSettings,
	FilterMarks = FilterMarks,
	UpdateMarks = UpdateMarks,
}
