local hkey = require "windows_registry"

if not ATAPE then
	require "iuplua" 
	iup.SetGlobal('UTF8MODE', 1)
end


local reg_path = "Software\\Radioavionika\\SumPOV\\"


local NAMES = 
{
	"POV_OPERATOR",
	"POV_EAKSUI",
	"POV_REPORT",
	"POV_REJECTED",
}

-- ==============================================================


--[[ прочитаем значения из реестра 
возвращает таблицу имя-значение ]]
local function read_pov_flags()
	--[[ https://bt.abisoft.spb.ru/view.php?id=592#c2403
		1.Настройка состояния флагов ПОВ -> Настройка сценария установки ПОВ
		POV_REJECTED - не нужно использовать в настройки сценарии установки ПОВ. ]]
	
	local reg = hkey.HKEY_CURRENT_USER:create(reg_path .. "edit") -- хранение свойств отметок редактирования
	local names = {"POV_OPERATOR", "POV_EAKSUI", "POV_REPORT"}
	local def = {1, 1, 1}
	
	local values = {}
	for i, name in ipairs(names) do
		local value = reg:queryvalue(name)
		values[name] = (value and type(value) == 'number') and tonumber(value) or def[i] or 0
	end
	return values, reg
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
	--[[ https://bt.abisoft.spb.ru/view.php?id=592#c2403
		1.Настройка состояния флагов ПОВ -> Настройка сценария установки ПОВ
		POV_REJECTED - не нужно использовать в настройки сценарии установки ПОВ. ]]
		
	local values, reg = read_pov_flags() 	-- прочитаем значения из реестра

	local title = "Настройка подтверждающих отметок видеораспознавания"
	local fmt = "\z
		Подтверждено оператором: %o|Нет|Да|\n\z
		Отметки для отправки в ЕКАСУИ: %o|Нет|Подготовлено|Отправлено|\n\z
		Отметки для формирования отчетов: %o|Нет|Да|\n"

	local ok, operator, ekasui, report = iup.GetParam(title, nil, fmt, values.POV_OPERATOR, values.POV_EAKSUI, values.POV_REPORT)
	
	if ok then -- pop first element
		reg:setvalue('POV_OPERATOR', operator)
		reg:setvalue('POV_EAKSUI', ekasui)
		reg:setvalue('POV_REPORT', report)
		return true
	end
end

-- сформировать описание текущих настроек
function GetShortCurPOVDesc(sep)
	local values = read_pov_flags() 	-- прочитаем значения из реестра
	local res = {}
	
	local variants_operator = {"Нет", "Да"}
	local variants_ekasi = {"Нет", "Подготовлено", "Отправлено"}
	local variants_report = {"Нет", "Да"}
	
	table.insert(res, "Оператор: " .. (variants_operator[values.POV_OPERATOR+1] or '??'))
	table.insert(res, "ЕКАСУИ: "   .. (variants_ekasi[   values.POV_EAKSUI  +1] or '??'))
	table.insert(res, "Отчеты: "   .. (variants_report[  values.POV_REPORT  +1] or '??'))
	
	return table.concat(res, sep or ' | ')
end

function GetMarkDescription(mark, sep)
	local mark_values = {}
	local res = {}
	
	local variants_operator = {"Нет", "Да"}
	local variants_ekasi    = {"Нет", "Подготовлено", "Отправлено"}
	local variants_report   = {"Нет", "Да"}
	local variants_rejected = {"Нет", "Да"}
	
	if mark.ext.POV_OPERATOR then table.insert(res, "Оператор: "    .. (variants_operator[mark.ext.POV_OPERATOR+1] or '??')) end
	if mark.ext.POV_EAKSUI   then table.insert(res, "ЕКАСУИ: "      .. (variants_ekasi[   mark.ext.POV_EAKSUI  +1] or '??')) end
	if mark.ext.POV_REPORT   then table.insert(res, "Отчеты: "      .. (variants_report[  mark.ext.POV_REPORT  +1] or '??')) end
	if mark.ext.POV_REJECTED then table.insert(res, "Отвергнутые: " .. (variants_rejected[mark.ext.POV_REJECTED+1] or '??')) end
	
	return table.concat(res, sep or ' | ')
end

--[[ установить флаги отметки в соответстви c настройками ]]
function UpdateMarks(marks, save_marks)
	if marks.prop or marks.ext then marks = {marks}	end		-- если передана одна отметка, а не список, делаем список
	local values = read_pov_flags()		-- прочитаем значения из реестра
	
	for _, mark in ipairs(marks) do
		for name, value in pairs(values) do
			mark.ext[name] = value
		end
		
		if save_marks then mark:Save() end
	end
end

--[[ пользователю предлагается окно редактирования значения флагов отметки 

(с отображением предыдущего набора) и выбор флагов ПОВ (флаги по умолчанию 
соответствуют с выбранному сценарию).
]]
function EditMarks(marks, save_marks)
	if marks.prop or marks.ext then marks = {marks}	end 	-- если передана одна отметка, а не список, делаем список
	if #marks == 0 then return end	-- если список пустой, то выходим
	
	local values_def = read_pov_flags() 	-- прочитаем значения из реестра
	
	-- прочитать параметры первой отметки и примем их поумолчанию для остальных
	local values = {}
	for i, name in ipairs(NAMES) do
		values[name] = marks[1].ext[name] or values_def[name] or 0
	end
	
	local title = "Настройка флагов ПОВ отметки"
	local fmt = "\z
		Подтверждено оператором: %o|Нет|Да|\n\z
		Отметки для отправки в ЕКАСУИ: %o|Нет|Подготовлено|Отправлено|\n\z
		Отметки для формирования отчетов: %o|Нет|Да|\n\z
		Отвергнутые: %o|Нет|Да|\n"

	local ok, operator, ekasui, report, rejected = 
		iup.GetParam(title, nil, fmt, 
			values.POV_OPERATOR, values.POV_EAKSUI, values.POV_REPORT, values.POV_REJECTED)
	
	if ok then
		for _, mark in ipairs(marks) do
			mark.ext.POV_OPERATOR = operator
			mark.ext.POV_EAKSUI   = ekasui
			mark.ext.POV_REPORT   = report
			mark.ext.POV_REJECTED = rejected
			if save_marks then mark:Save() end
		end
	end
end

--[[ Для ряда объектов (шпалы, ..) вводится пункт меню Отвергнуть дефектность. 
При этом устанавливается соответствующий флаг ПОВ. ]]
function RejectDefects(marks, save_marks, reject)
	if marks.prop or marks.ext then marks = {marks}	end 	-- если передана одна отметка, а не список, делаем список
	
	for _, mark in ipairs(marks) do
		mark.ext['POV_REJECTED'] = reject and 1 or 0

		if save_marks then mark:Save() end
	end
end

-- проверить что у отметки поставлен флаг отвергнутая дефектность
function IsRejectDefect(mark)
	return mark and mark.ext and mark.ext['POV_REJECTED'] == 1
end

-- установить признак Подготовлено для отправки в ЕКАСУИ 
function AcceptEKASUI(marks, save_marks, accept)
	if marks.prop or marks.ext then marks = {marks}	end 	-- если передана одна отметка, а не список, делаем список
	
	for _, mark in ipairs(marks) do
		mark.ext['POV_EAKSUI'] = accept and 1 or 0
		if save_marks then mark:Save() end
	end
end

-- проверить признак Подготовлено для отправки в ЕКАСУИ 
function IsAcceptEKASUI(mark, save_marks)
	return mark and mark.ext and mark.ext['POV_EAKSUI'] == 1
end



function MakeReportFilter(ekasui)
	local function read_reg_bits(reg, name, default)
		local value = reg:queryvalue(name)
		value = value and type(value) == 'number' and tonumber(value) or default
		local res = {}
		for i = 1, 32 do
			res[i] = bit32.btest(value, bit32.lshift(1, i-1)) and 1 or 0
		end
		return res
	end
	
	local function make_mask(...)
		local res = 0
		for i, v in ipairs{...} do
			if v and v ~=0 then
				res = bit32.bor(res, bit32.lshift(1, i-1))
			end
		end
		return res
	end
			
	local ok = false
	local op_no, op_yes, ek_no, ek_prep, ek_snd, rp_no, rp_yes = 0, 0, 0, 0, 0, 0, 0
	
	if ekasui then
		local reg = hkey.HKEY_CURRENT_USER:create(reg_path .. 'ekasui')
		
		local reg_POV_OPERATOR = read_reg_bits(reg, 'POV_OPERATOR', 0)
		local reg_POV_EAKSUI = read_reg_bits(reg, 'POV_EAKSUI', 2)
	
		local title = "Настройка ПОВ фильтрации отчета: ЕКАСУИ"
		local fmt = "\z
			Подтверждено оператором: %t|\n\z
				Нет: %b[пропустить,включить]|\n\z
				Да: %b[пропустить,включить]|\n\z
			Отметки для отправки в ЕКАСУИ: %t|\n\z
				Нет: %b[пропустить,включить]|\n\z
				Подготовлено: %b[пропустить,включить]|\n\z
				Отправлено: %b[пропустить,включить]|\n"
		ok, op_no, op_yes, ek_no, ek_prep, ek_snd = iup.GetParam(title, nil, fmt, 
				reg_POV_OPERATOR[1], reg_POV_OPERATOR[2],
				reg_POV_EAKSUI[1],   reg_POV_EAKSUI[2], reg_POV_EAKSUI[3])
	
		if ok then
			reg:setvalue('POV_OPERATOR', make_mask(op_no, op_yes))
			reg:setvalue('POV_EAKSUI',   make_mask(ek_no, ek_prep, ek_snd))
		end
	else -- vedomost
		local reg = hkey.HKEY_CURRENT_USER:create(reg_path .. 'vedomost')
		
		local reg_POV_OPERATOR = read_reg_bits(reg, 'POV_OPERATOR', 0)
		local reg_POV_REPORT = read_reg_bits(reg, 'POV_REPORT', 2)
		
		local title = "Настройка ПОВ фильтрации отчета: ВК"
		local fmt = "\z
			Подтверждено оператором: %t|\n\z
				Нет: %b[пропустить,включить]|\n\z
				Да: %b[пропустить,включить]|\n\z
			Отметки для формирования отчетов: %t|\n\z
				Нет: %b[пропустить,включить]|\n\z
				Да: %b[пропустить,включить]|\n"
		ok, op_no, op_yes, rp_no, rp_yes = iup.GetParam(title, nil, fmt, 
				reg_POV_OPERATOR[1], reg_POV_OPERATOR[2],
				reg_POV_REPORT[1],   reg_POV_REPORT[2])
		
		if ok then
			reg:setvalue('POV_OPERATOR', make_mask(op_no, op_yes))
			reg:setvalue('POV_REPORT',   make_mask(rp_no, rp_yes))
		end
	end
	
	if ok then
		local check_mark = function (mark)
			if mark.ext.POV_REJECTED == 1 then
				return false
			end
			
			if op_no ~= 0 or op_yes ~= 0 then
				local v = mark.ext.POV_OPERATOR or 1
				if op_no  ~= 0 and v == 0 then return true end
				if op_yes ~= 0 and v == 1 then return true end
			end
			
			if ek_no ~= 0 or ek_prep ~= 0 or ek_snd ~= 0 then
				local v = mark.ext.POV_EAKSUI or 1
				if ek_no   ~= 0 and v == 0 then return true end
				if ek_prep ~= 0 and v == 1 then return true end
				if ek_snd  ~= 0 and v == 2 then return true end
			end
			
			if rp_no ~= 0 or rp_yes ~= 0 then
				local v = mark.ext.POV_REPORT or 1
				if rp_no  ~= 0 and v == 0 then return true end
				if rp_yes ~= 0 and v == 1 then return true end
			end
		
			return false
		end
		
		return function(marks)
			if marks.prop and marks.ext then 
				-- single mark
				return check_mark(marks)
			else
				-- mark array
				local res = {}
				for _, mark in ipairs(marks) do 
					if check_mark(mark) then
						table.insert(res, mark)
					end
				end
				return res
			end
		end
	end
end



-- =====================================================
-- =====================================================

return 
{
	ShowSettings = ShowSettings,
	UpdateMarks = UpdateMarks,
	GetCurrentSettingsDescription = GetShortCurPOVDesc,
	GetMarkDescription = GetMarkDescription,
	EditMarks = EditMarks,
	RejectDefects = RejectDefects,
	IsRejectDefect = IsRejectDefect,
	AcceptEKASUI = AcceptEKASUI,
	IsAcceptEKASUI = IsAcceptEKASUI,
	MakeReportFilter = MakeReportFilter
}
