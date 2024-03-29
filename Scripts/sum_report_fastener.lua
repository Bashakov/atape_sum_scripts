-- require('mobdebug').start()

if not ATAPE then
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"


local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'
local sumPOV = require "sumPOV"
local algorithm = require "algorithm"
local remove_grouped_marks = require "sum_report_group_scanner"
local ErrorUserAborted = require "UserAborted"
local TYPES = require 'sum_types'

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf

-- =========================================================================

local guids_fasteners =
{
	TYPES.FASTENER,	-- Скрепление
	TYPES.FASTENER_USER,	-- Скрепления(Пользователь)
}

local guids_fasteners_groups =
{
	TYPES.GROUP_FSTR_AUTO,   -- GROUP_FSTR_AUTO
	TYPES.GROUP_FSTR_USER, 	-- GROUP_FSTR_USER
}

local function GetMarks(ekasui, pov_filter)
	if not pov_filter then
		pov_filter = sumPOV.MakeReportFilter(ekasui)
	end
	if not pov_filter then return {} end
	local gg = mark_helper.table_merge(guids_fasteners, guids_fasteners_groups)
	local marks = Driver:GetMarks{GUIDS=gg}
	marks = pov_filter(marks)
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks
end

local function MakeFastenerMarkRow(mark, defect_code, defect_desc)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	row.FASTENER_GROUP_SIZE = mark.ext.GROUP_DEFECT_COUNT or ''
	row.FASTENER_TYPE = ''

	row.DEFECT_CODE = defect_code or ''
	row.DEFECT_DESC = defect_desc or DEFECT_CODES.code2desc(defect_code) or string.match(mark.prop.Description, '([^\n]+)\n') or ''

	return row
end

local function get_user_options(mark)
	local text = mark.ext.DEFECT_OPTIONS
	local res = {}
	local _ = string.gsub(text or '', '([^\n]+)',
		function(s)
			local n, v = string.match(s, '([^:]+):(.*)')
			-- print(s, n, v)
			if n then res[n] = v end
		end)
	return res
end

-- =========================================================================


local function igenerate_rows_fastener(marks, dlgProgress)
	return coroutine.wrap(function ()
	local fastener_type_names = {
		[0] = 'КБ-65',
		[1] = 'Аpc',
		[2] = 'ДО', -- скрепление на деревянной шпале на костылях
		[3] = 'КД', -- скрепление на деревянной шпале как КБ-65 но на двух шурупах
		[4] = 'Pandrol'
	}

	local defect_codes =
	{
		DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[1],
		DEFECT_CODES.FASTENER_MISSING_CLAMP[1],
		DEFECT_CODES.FASTENER_MISSING_BOLT[1],
	}

	local accepted = 0
	for i, mark in ipairs(marks) do
		if (
			TYPES.FASTENER_USER == mark.prop.Guid and mark.ext.CODE_EKASUI) or
			mark_helper.table_find(guids_fasteners_groups, mark.prop.Guid)
		then
			local row = MakeFastenerMarkRow(mark, mark.ext.CODE_EKASUI)
			row.FASTENER_TYPE = get_user_options(mark).connector_type or ''

			coroutine.yield(row)
			accepted = accepted + 1
		else
			local prm = mark_helper.GetFastenetParams(mark)
			local FastenerType = prm and prm.FastenerType or -1
			local FastenerFault = prm and prm.FastenerFault

			if FastenerFault and FastenerFault > 0 then
				local defect_code

				if prm.FastenerFault == 1 then -- отсутствие клеммного болта kb65
					defect_code = DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT
				elseif prm.FastenerFault == 2 then -- отсутствие клеммы apc
					defect_code = DEFECT_CODES.FASTENER_MISSING_CLAMP
				elseif prm.FastenerFault == 3 then -- Ослабл
					defect_code = DEFECT_CODES.FASTENER_MISSING_CLAMP
				elseif prm.FastenerFault == 4 then -- Изл.подкл.
					defect_code = DEFECT_CODES.FASTENER_DEFECT_LINING
				elseif prm.FastenerFault == 10 then -- отсутствие закладного болта kb65
					defect_code = DEFECT_CODES.FASTENER_MISSING_BOLT
				elseif prm.FastenerFault == 11 then -- отсутствие клеммного и закладного болта kb65 - имитируем закладной
					defect_code = DEFECT_CODES.FASTENER_MISSING_BOLT
				else
					defect_code = DEFECT_CODES.FASTENER_MISSING_CLAMP -- default
				end

				local row = MakeFastenerMarkRow(mark, defect_code[1])
				row.FASTENER_TYPE = fastener_type_names[FastenerType] or ''

				coroutine.yield(row)
				accepted = accepted + 1
			end
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 10 == 0 and not dlgProgress:step(i / #marks, sprintf('Сканирование %d / %d СКРЕПЛЕНИЙ, найдено %d', i, #marks, accepted)) then
			ErrorUserAborted()
		end
	end
	end)
end


local function igenerate_rows_fastener_user(marks, dlgProgress)
	return coroutine.wrap(function ()

	--local report_rows = {}
	local accepted = 0
	for i, mark in ipairs(marks) do
		if mark.prop.Guid == TYPES.FASTENER_USER and mark.ext.CODE_EKASUI then
			local row = MakeFastenerMarkRow(mark, mark.ext.CODE_EKASUI)
			row.FASTENER_TYPE = get_user_options(mark).connector_type or ''

			coroutine.yield(row)
			accepted = accepted + 1
		end

		if i % 300 == 0 then collectgarbage("collect") end
		if i % 10 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, accepted)) then
			ErrorUserAborted()
		end
	end
	end)
end

local function igen_adapter(fn)
	return function (...)
		local args = {...}
		return ErrorUserAborted.skip(function ()
			local g = fn(table.unpack(args))
			local rows = algorithm.list(g)
			rows = remove_grouped_marks(rows, guids_fasteners_groups, false) -- удаление шпал попадающих в гграницы кустовых дефектов, для исклучения дублирования
			return rows
		end)
	end
end

local generate_rows_fastener = igen_adapter(igenerate_rows_fastener)
local generate_rows_fastener_user = igen_adapter(igenerate_rows_fastener_user)

-- =============================================================================

local function make_report_generator(...)

	local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ СКРЕПЛЕНИЙ.xlsm'
	local sheet_name = 'В1 СКР'

	return AVIS_REPORT.make_report_generator(function() return GetMarks(false) end,
		report_template_name, sheet_name, ...)
end

local function make_report_ekasui(...)
	return EKASUI_REPORT.make_ekasui_generator(function() return GetMarks(true) end, ...)
end

local function make_report_videogram(...)
	local row_generators = {...}

	local function gen(mark)
		local report_rows = {}
		if mark and mark_helper.table_find(guids_fasteners, mark.prop.Guid) then
			for _, fn_gen in ipairs(row_generators) do
				local cur_rows = fn_gen({mark}, nil)
				for _, row in ipairs(cur_rows) do
					table.insert(report_rows, row)
				end
			end
		end
		return report_rows
	end

	return gen
end

-- =========================================================================

local report_fastener = make_report_generator(generate_rows_fastener)
local ekasui_fastener = make_report_ekasui(generate_rows_fastener)
local videogram = make_report_videogram(generate_rows_fastener)

local report_fastener_all = make_report_generator(generate_rows_fastener_user, generate_rows_fastener)
local ekasui_fastener_all = make_report_ekasui(generate_rows_fastener_user, generate_rows_fastener)

-- =========================================================================

local function AppendReports(reports)
	local name_pref = 'Ведомость отступлений в содержании скреплений|'
	local name_fastener = 'Определение параметров и состояния рельсовых скреплений (наличие визуально фиксируемых ослабленных скреплений, сломанных подкладок, отсутствие болтов, негодные прокладки, закладные и клеммные болты, шурупы, клеммы, анкеры)'

	local sleppers_reports =
	{
		{name = name_pref..'Все',    						fn=report_fastener_all, },
		{name = name_pref..'ЕКАСУИ Все',    				fn=ekasui_fastener_all, },
		{name = name_pref.. name_fastener,    				fn=report_fastener, },
		{name = name_pref..'ЕКАСУИ ' .. name_fastener,    	fn=ekasui_fastener, },
	}

	for _, report in ipairs(sleppers_reports) do
		report.guids = mark_helper.table_merge(guids_fasteners, guids_fasteners_groups)
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then
	local test_report  = require('local_data_driver')
	test_report.Driver('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 150000})

	report_fastener()
	--ekasui_fastener()
	-- report_fastener_user()
end

return {
	AppendReports = AppendReports,
	videogram = videogram,
	all_generators = {
		{generate_rows_fastener_user, 	"Установленые пользователем"},
		{generate_rows_fastener, 		"Состояние рельсовых скреплений"},
	},
	get_marks = function (pov_filter)
		return GetMarks(false, pov_filter)
	end,
}
