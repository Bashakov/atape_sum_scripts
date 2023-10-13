if not ATAPE then
	require "iuplua"
end
if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local EKASUI_REPORT = require 'sum_report_ekasui'
local AVIS_REPORT = require 'sum_report_avis'
local sumPOV = require "sumPOV"
local TYPES = require 'sum_types'
local TYPE_GROUPS = require "sum_list_pane_guids"


local jat_guids = mark_helper.table_merge(TYPE_GROUPS.recognition_guids, TYPE_GROUPS.JAT)

local markid2defectcodes = {}

-- =========================================

local function filter_mark(mark)
    local g = mark.prop.Guid
    if mark_helper.table_find(TYPE_GROUPS.JAT, g) then
        return true
    else
        local codes = mark_helper.GetJoinConnectorDefectCodes(mark)
        if codes and #codes > 0 then
			markid2defectcodes[mark.prop.ID] = codes
			return true
		end
    end
end

local function GetMarks(params, dlgProgress)
	markid2defectcodes = {}

    local t = params and params.filter or 'all'
    local g = {}

    if t == 'all' or t == 'user' then
        g = mark_helper.table_merge(g, TYPE_GROUPS.JAT)
    end
    if t == 'all' or t == 'auto' then
        g = mark_helper.table_merge(g, TYPE_GROUPS.recognition_guids)
    end

    local marks = Driver:GetMarks{GUIDS=g}
    marks = mark_helper.filter_marks(marks, filter_mark, function (all, cur, accept)
		if dlgProgress and cur % 31 == 1 then
			dlgProgress:step(cur / all, string.format('Подготовка %d / %d', cur, all))
		end
	end)
    marks = mark_helper.sort_mark_by_coord(marks)
    return marks
end

-- сделать из отметки таблицу и подстановками
local function MakeJatMarkRow(mark, defect_code)
	local row = mark_helper.MakeCommonMarkTemplate(mark)

    if defect_code then
		row.DEFECT_CODE = defect_code
	end
	row.DEFECT_DESC = DEFECT_CODES.code2desc(defect_code)
    row.JAT_VALUE = mark.ext.JAT_VALUE or ""
    row.RAILWAY_HOUSE = mark.ext.RAILWAY_HOUSE or ""
    row.RAILWAY_TYPE = mark.ext.RAILWAY_TYPE or ""
    row.GAP_TYPE = ""
	return row
end

local function getGapType(mark)
    local gap_type = mark_helper.GetGapType(mark) -- 0 - болтовой, 1 - изолированный, 2 - сварной
    if gap_type == 0 then
        return 'болтовой'
    elseif gap_type == 1 then
        return "изолированный"
    elseif gap_type == 2 then
        return "сварной"
    end
    return ""
end

-- =========================================

local function generate_rows_jat(marks, dlgProgress, pov_filter)
	if #marks == 0 then return end

	local report_rows = {}
	for i, mark in ipairs(marks) do
        
		if pov_filter(mark) then
            local g = mark.prop.Guid
            if mark_helper.table_find(TYPE_GROUPS.JAT, g) then
                local row = MakeJatMarkRow(mark, mark.ext.CODE_EKASUI)
				table.insert(report_rows, row)
            else
				local gap_type = getGapType(mark)
                local codes = markid2defectcodes[mark.prop.ID]
                for _, code in ipairs(codes) do
                    local row = MakeJatMarkRow(mark, code)
                    row.GAP_TYPE = gap_type
					table.insert(report_rows, row)
                end
            end
        end

		if i % 31 == 0 and not dlgProgress:step(i / #marks, string.format('Сканирование %d / %d, найдено %d', i, #marks, #report_rows)) then
			return
		end
	end

	return report_rows
end

-- =========================================

-- вместо функций генераторов, вставляем функции обертки вызывающие генераторы с доп параметрами
local function make_gen_pov_filter(generator, ...)
	local args = {...}
	for i, gen in ipairs(generator) do
		generator[i] = function (marks, dlgProgress)
			return gen(marks, dlgProgress, table.unpack(args))
		end
	end
	return generator
end

local function make_report_ekasui(...)
	local generators = {...}
	return function(params)
		local pov_filter = sumPOV.MakeReportFilter(true)
		if not pov_filter then return {} end
		generators = make_gen_pov_filter(generators, pov_filter)
		return EKASUI_REPORT.make_ekasui_generator(
            function() return GetMarks(params) end,
            table.unpack(generators)) ()
	end
end

local function make_report_generator(...)
	local generators = {...}

	return function(params)
		local pov_filter = sumPOV.MakeReportFilter(false)
		if not pov_filter then return {} end

		local report_template_name = 'ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ УСТРОЙСТВ ЖАТ.xlsm'
		local sheet_name = 'JAT'

		generators = make_gen_pov_filter(generators, pov_filter)
		return AVIS_REPORT.make_report_generator(
            function(dlgProgress) return GetMarks(params, dlgProgress) end,
			report_template_name,
            sheet_name,
            table.unpack(generators))()
	end
end

local function make_html_report_generator(...)
	local generators = {...}
	return function(params)
		local pov_filter = sumPOV.MakeReportFilter(false)
		if not pov_filter then return {} end

		generators = make_gen_pov_filter(generators, pov_filter)

		local gen = AVIS_REPORT.make_html_generator(
            function(dlgProgress) return GetMarks(params, dlgProgress) end,
			"jat_report_template.html",
            "jat_",
			"ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ УСТРОЙСТВ ЖАТ",
            table.unpack(generators))
		gen()
	end
end

-- =============================================================================

local jat_ekasui = make_report_ekasui(generate_rows_jat)
local jat_report = make_report_generator(generate_rows_jat)
local jat_html = make_html_report_generator(generate_rows_jat)

local name_pref = 'Ведомость отступлений в содержании устройств ЖАТ|'

local jat_reports =
{
	{name = name_pref..'все',            		fn=jat_report, 	params = {filter="all" }, },
	{name = name_pref..'пользователь',   		fn=jat_report, 	params = {filter="user"}, },
	{name = name_pref..'автоматические', 		fn=jat_report, 	params = {filter="auto"}, },

	{name = name_pref..'ЕКАСУИ все',            fn=jat_ekasui, 	params = {filter="all" }, },
	{name = name_pref..'ЕКАСУИ пользователь',   fn=jat_ekasui, 	params = {filter="user"}, },
	{name = name_pref..'ЕКАСУИ автоматические', fn=jat_ekasui, 	params = {filter="auto"}, },

	{name = name_pref..'HTML все',            	fn=jat_html, 	params = {filter="all" }, },
	{name = name_pref..'HTML пользователь',   	fn=jat_html, 	params = {filter="user"}, },
	{name = name_pref..'HTML автоматические', 	fn=jat_html, 	params = {filter="auto"}, },
}

local function AppendReports(reports)
    for _, report in ipairs(jat_reports) do
		if report.fn then
			report.guids = jat_guids
			table.insert(reports, report)
		end
	end
end

-- =========================================

-- тестирование
if not ATAPE then
	_G.ShowVideo = 0
	local test_report  = require('local_data_driver')
	test_report.Driver('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 1000000})
	--test_report('C:\\Avikon\\CheckAvikonReports\\data\\data_27_short.xml')
    --test_report('D:/ATapeXP/Main/TEST/ZeroGap/2019_06_13/Avikon-03M/6284/[494]_2017_06_14_03.xml')

	local report = jat_reports[6]
	report.fn(report.params)

	--report_ALL()
end

return {
	AppendReports = AppendReports,
}