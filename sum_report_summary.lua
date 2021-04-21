-- 2018.06.21 Описание к выходным формам видеоконтроля (в.2).docx
-- ВЕДОМОСТЬ 8: СВОДНАЯ ВЕДОМОСТЬ ОТСТУПЛЕНИЙ

local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
local sumPOV = require "sumPOV"
require "ExitScope"
local hkey = require "windows_registry"

local flags_reg_path = "Software\\Radioavionika\\Reports\\summary_report_flags"

-- ================================================================= --

local REPORTS =
{
    {
        form_8_column = 3,
        script_name = 'sum_report_fastener',
        title = "Отступления в содержании скреплений",
    },
    {
        form_8_column = 10,
        script_name = 'sum_report_joints',
        title = "Отступления в содержании рельсовых стыков",
    },
    {
        form_8_column = 17,
        script_name = 'sum_report_sleepers',
        title = "",
    },
    {
        form_8_column = 24,
        script_name = 'sum_report_rails',
        title = "Отступления в содержании шпал",
    },
    {   -- балласт
        form_8_column = 31,
    },
    {
        form_8_column = 38,
        script_name = 'sum_report_beacon',
        title = 'Отступления в содержании бесстыкового пути',
    },
}

local function get_selected_reports(count)
    local reg = hkey.HKEY_CURRENT_USER:create(flags_reg_path)
	local value = reg:queryvalue('reports') or ''
	local values = {}
	string.gsub(value, '%d', function (v)
        table.insert(values, tonumber(v) or 1)
    end)
    while #values < count do
        table.insert(values, 1)
    end
    return table.unpack(values)
end

local function  save_selected_reports(values)
    local reg = hkey.HKEY_CURRENT_USER:create(flags_reg_path)
	reg:setvalue('reports', table.concat(values, ';')) 
end

local function load_reports()
    local res_reports = {}

    local prev_atape = ATAPE
    ATAPE = true -- disable debug code while load scripts

    local dlg_text = ""
    local count = 0
    for _, report in ipairs(REPORTS) do
        if report.script_name then
            table.insert(res_reports, report)
            dlg_text = dlg_text .. (report.title or report.script_name) .. "%t\n"
            report.script = require(report.script_name)

            for i, gen in ipairs(report.script.all_generators) do
                local name = type(gen) == "table" and gen[2] or tostring(i)
                dlg_text = dlg_text .. name .. ": %b\t\n"
                count = count + 1
            end
        end
    end

    local selected = {iup.GetParam("Выбор отчетов", nil, dlg_text, get_selected_reports(count))}

    if selected[1] then
        table.remove(selected, 1)
        save_selected_reports(selected)

        for _, report in ipairs(res_reports) do
            report.generators = {}

            for _, gen in ipairs(report.script.all_generators) do
                if selected[1] == 1 then
                    table.insert(report.generators, gen[1])
                end
                table.remove(selected, 1)
            end

            if #report.generators > 0 then
                report.get_marks = report.script.get_marks
            else
                report.get_marks = function () return {}  end
            end
        end
    end
    ATAPE = prev_atape

    return res_reports
end

local function load_guids()
    local guids_table = {}

    local prev_atape = ATAPE
    ATAPE = true -- disable debug code while load scripts

    for _, report in ipairs(REPORTS) do
        if report.script_name then
            local script = require(report.script_name)
            local reports = {}
            script.AppendReports(reports)
            for _, r in ipairs(reports) do
                for _, g in ipairs(r.guids) do
                    guids_table[g] = true
                end
            end
        end
    end
    ATAPE = prev_atape

    local res = {}
    for g, _ in pairs(guids_table) do
        res[#res+1] = g
    end
    return res
end

local guids = load_guids()


-- ================================================================= --

-- проход по таблице в сортированном порядке
local function sorted(tbl)
	local keys = {}
	for n, _ in pairs(tbl) do table.insert(keys, n) end
	table.sort(keys)
	local i = 0
	return function()
		i = i + 1
		return keys[i], tbl[keys[i]]
	end
end

-- ================================================================= --

local function make_cur_report_rows(pov_filter, dlg, report)
    if not report.get_marks then
        return {}
    end

    local code2marks = {} -- убрать дублирование отметок полученных через стандартную функцию отчетов (включающую пользовательские отметки с опр. гуидом) и пользовательскую функцию отчетов
    local report_rows = {}
    local marks = report.get_marks(pov_filter)
    for _, gen in ipairs(report.generators) do
        local cur_rows = gen(marks, dlg, pov_filter)
        if not cur_rows then
            return {}
        end
        for _, row in ipairs(cur_rows) do
            local code = row.DEFECT_CODE or ''
            local id = row.mark_id or -1
            if not code2marks[code] then code2marks[code] = {} end
            if id < 0 or not code2marks[code][id] then
                code2marks[code][id] = true
                table.insert(report_rows, row)
            end
        end
    end
    return report_rows
end

local function make_all_reports_list()
    return EnterScope(function (defer)
        local reports = load_reports()

        local pov_filter = sumPOV.MakeReportFilter(false)
        if not pov_filter then
            return
        end

        local dlg = luaiup_helper.ProgressDlg()
		defer(dlg.Destroy, dlg)

        local result = {}
        for i, report in ipairs(reports) do
            dlg:setTitle(report.title or report.script_name)
            local rows = make_cur_report_rows(pov_filter, dlg, report)
            if not rows then
                return
            end
            result[i] = rows
        end
        return result
    end)
end

local function get_num_speed_limit(row)
    local disable_words = {
        ['Закрытие движения'] = true,
        ['ЗАПРЕЩЕНО'] = true,
        ['Движение закрывается'] = true,
    }

    local cur_limit = row.SPEED_LIMIT
    if disable_words[cur_limit] then
        cur_limit = 0
    elseif not cur_limit or not tonumber(cur_limit) then
        cur_limit = nil
    else
        cur_limit = tonumber(cur_limit)
    end
    return cur_limit
end

local function group_by_velocity(rows, vel_limits)
    local others = 0 -- прочие
    local res = {}
    for i, _ in ipairs(vel_limits) do
        res[i] = 0
    end

    for _, row in ipairs(rows) do
        local cur_limit = get_num_speed_limit(row)
        if not cur_limit then
            others = others + 1
        else
            cur_limit = tonumber(cur_limit)
            for i = #vel_limits, 1, -1 do
                if cur_limit >= vel_limits[i] then
                    res[i] = res[i] + 1
                    break
                end
            end
        end
    end
    table.insert(res, others)
    table.insert(res, #rows)
    return res
end

local function group_by_KM(rows, n, result)
    local OTHER = #REPORTS+1
    local TOTAL = OTHER+1
    local LIMITS = TOTAL+1

    for _, row in ipairs(rows) do
        local km = row.KM
        local t = result[km]
        if not t then
            t = {}
            for i = 1, LIMITS do t[i] = 0 end
            result[km] = t
        end

        t[n] = t[n] + 1
        t[TOTAL] = t[TOTAL] + 1
        if get_num_speed_limit(row) then
            t[LIMITS] = t[LIMITS] + 1
        end
    end
end

-- ================================================================= --

local function make_summary_report()
    local vel_limits = {0, 15, 25, 40, 60}
    local all_other = 0
    local all_marks = 0
    local rep2mark = make_all_reports_list()
    if not rep2mark then return end

	local template_path = Driver:GetAppPath() .. 'Scripts/'  .. 'СВОДНАЯ ВЕДОМОСТЬ ОТСТУПЛЕНИЙ.xlsx'

    local excel = excel_helper(template_path, nil, false)
	excel:ApplyPassportValues(mark_helper.GetExtPassport(Passport))

    local user_range = excel._worksheet.UsedRange
    local row_num = 11
    for rep_n, rows in ipairs(rep2mark) do
        local report = REPORTS[rep_n]
        local g = group_by_velocity(rows, vel_limits)
        all_marks = all_marks + g[#g-0]
        all_other = all_other + g[#g-1]

        for vel_n, cnt in ipairs(g) do
            local col = report.form_8_column + vel_n - 1
            local cell = user_range.Cells(row_num, col)
            cell.Value2 = cnt
        end
    end
    user_range.Cells(row_num, 45).Value2 = all_other
    user_range.Cells(row_num, 46).Value2 = all_marks
    user_range.Cells(row_num, 47).Value2 = all_marks-all_other

    excel:SaveAndShow()
end


local function make_per_km_report()
    --local kms = {1,2,3,4,5,6,7,8,9,10}

    local rep2mark = make_all_reports_list()
    if not rep2mark then return end
    local km2nums = {}
    for rep_n, rows in ipairs(rep2mark) do
        group_by_KM(rows, rep_n, km2nums)
    end
    local kms = {}
    for km, _ in sorted(km2nums) do
        kms[#kms+1] = km
    end

	local template_path = Driver:GetAppPath() .. 'Scripts/'  .. 'ПОКИЛОМЕТРОВАЯ ВЕДОМОСТЬ ОТСТУПЛЕНИЙ.xlsx'

    local excel = excel_helper(template_path, nil, false)
	excel:ApplyPassportValues(mark_helper.GetExtPassport(Passport))

    local template_row_num = 12
    local tamplate_col_start = 5
    local user_range = excel._worksheet.UsedRange
    if #kms > 1 then
        local row_template = user_range.Rows(template_row_num+1).EntireRow -- возьмем строку (включая размеремы EntireRow)
        row_template:Resize(#kms-1):Insert()				-- размножим ее
    end

    local all = {}
    for i, km in ipairs(kms) do
        local rn = template_row_num+i-1
        user_range.Cells(rn, 1).Value2 = km
        for rep_n, num in ipairs(km2nums[km]) do
            local col = tamplate_col_start + rep_n - 1
            user_range.Cells(rn, col).Value2 = num
            all[col] = (all[col] or 0) + num
        end
    end

    for col, num in pairs(all) do
        user_range.Cells(template_row_num + #kms, col).Value2 = num
    end
    excel:SaveAndShow()
end

-- ================================================================= --


local function AppendReports(reports)
	local name_pref = 'Сводные ведомости|'

    local cur_reports =
	{
        {name = name_pref..'СВОДНАЯ ВЕДОМОСТЬ ОТСТУПЛЕНИЙ',    		fn = make_summary_report, },
        {name = name_pref..'ПОКИЛОМЕТРОВАЯ ВЕДОМОСТЬ ОТСТУПЛЕНИЙ',  fn = make_per_km_report, },
    }

    for _, report in ipairs(cur_reports) do
        report.guids = guids
        table.insert(reports, report)
	end
end

-- ================================================================= --

if not ATAPE then
    local test_report  = require('test_report')
    -- local data_path = 'D:\\Downloads\\722\\492 dlt xml sum\\[492]_2021_03_14_03.xml'
    -- local data_path = 'D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml'
    local data_path = 'D:\\Downloads\\722\\2021.03.23\\[492]_2021_01_26_02.xml'

	test_report(data_path, nil, {0, 10000000})

    make_summary_report()
    --make_per_km_report()
end


return {
	AppendReports = AppendReports,
}
