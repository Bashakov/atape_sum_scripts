local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
require 'ExitScope'

local sprintf = mark_helper.sprintf
local printf = mark_helper.printf
local errorf = mark_helper.errorf
local table_find = mark_helper.table_find

-- =============================================================================

local NPU_guids = {
	"{19FF08BB-C344-495B-82ED-10B6CBAD5090}", -- НПУ
	"{19FF08BB-C344-495B-82ED-10B6CBAD508F}", -- Возможно НПУ
}

local NPU_guids_2 = {
	"{19FF08BB-C344-495B-82ED-10B6CBAD5091}", -- НПУ БС
}

local NPU_guids_uzk = {
	"{29FF08BB-C344-495B-82ED-000000000011}",
}

-- =============================================================================

local function report_NPU(params)
	return EnterScope(function (defer)
    local dlg = luaiup_helper.ProgressDlg('Построение отчета НПУ')
    defer(dlg.Destroy, dlg)

	local marks = Driver:GetMarks{ListType='list', GUIDS=params.guids}

	marks = mark_helper.sort_mark_by_coord(marks)

	local sum_length = 0
	local report_rows = {}
	for i, mark in ipairs(marks) do
		local row = mark_helper.MakeCommonMarkTemplate(mark)
		report_rows[i] = row
		sum_length = sum_length + mark.prop.Len
	end

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, nil, false)
	local ext_psp = mark_helper.GetExtPassport(Passport)

	ext_psp.SUM_LENGTH = sum_length
	excel:ApplyPassportValues(ext_psp, dlg)
	excel:ApplyRows(report_rows, nil, dlg)
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)

	excel:SaveAndShow()
	end)
end

-- =============================================================================

local cur_reports =
{
	{name="НПУ",    fn=report_NPU,	params={ filename="Telegrams\\НПУ_VedomostTemplate.xls", guids=NPU_guids },     guids=NPU_guids},
	{name="УЗ_НПУ", fn=report_NPU,	params={ filename="Telegrams\\НПУ_VedomostTemplate.xls", guids=NPU_guids_uzk }, guids=NPU_guids_uzk},
	{name="НПУ БС", fn=report_NPU,	params={ filename="Telegrams\\НПУ_БС_VedomostTemplate.xls", guids=NPU_guids_2}, 	guids=NPU_guids_2},
}

local function AppendReports(reports)
	for _, report in ipairs(cur_reports) do
		table.insert(reports, report)
	end
end

-- тестирование
if not ATAPE then

	test_report  = require('test_report')
	--test_report('D:\\ATapeXP\\Main\\480\\[480]_2013_11_09_14.xml')
	test_report('D:\\d-drive\\ATapeXP\\Main\\test\\1\\[987]_2022_02_04_01.xml', nil, {0, 1000000}) --

	report_NPU(cur_reports[1].params)
	--ekasui_rails()
	
end

return {
	AppendReports = AppendReports,
}
