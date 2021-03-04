-- 2018.06.21 Описание к выходным формам видеоконтроля (в.2).docx
-- ВЕДОМОСТЬ 8: СВОДНАЯ ВЕДОМОСТЬ ОТСТУПЛЕНИЙ

local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
local sumPOV = require "sumPOV"
require "ExitScope"

-- ================================================================= --

local REPORTS =
{
    {
        form_8_column = 3,
        script_name = 'sum_report_fastener',
    },
    {
        form_8_column = 10,
        script_name = 'sum_report_joints',
    },
    {
        form_8_column = 17,
        script_name = 'sum_report_sleepers',
    },
    {
        form_8_column = 24,
        script_name = 'sum_report_rails',
    },
    {
        form_8_column = 38,
        script_name = 'sum_report_beacon',
    },
}

local function load_reports()
    local prev_atape = ATAPE
    ATAPE = true -- disable debug code while load scripts
    for _, report in ipairs(REPORTS) do
        report.script = require(report.script_name)
        report.get_marks = report.script.get_marks
        report.generators = report.script.all_generators
    end
    ATAPE = prev_atape
end

load_reports()


-- ================================================================= --
-- ================================================================= --

local function make_cur_report_rows(pov_filter, dlg, report)
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
        local pov_filter = sumPOV.MakeReportFilter(false)
        if not pov_filter then
            return
        end

        local dlg = luaiup_helper.ProgressDlg()
		defer(dlg.Destroy, dlg)

        local result = {}
        for i, report in ipairs(REPORTS) do
            local rows = make_cur_report_rows(pov_filter, dlg, report)
            if not rows then
                return
            end
            result[i] = rows
        end
        return result
    end)
end

local function group_by_velocity(rows, vel_limits)
    local others = 0 -- прочие
    local res = {}
    for i, _ in ipairs(vel_limits) do res[i] = 0 end

    for _, row in ipairs(rows) do
        local cur_limit = row.SPEED_LIMIT
        if cur_limit == 'Движение закрывается' then
            cur_limit = 0
        end
        if not cur_limit or not tonumber(cur_limit) then
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

-- ================================================================= --

if not ATAPE then
    local test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 100000000})

    make_summary_report()
end
