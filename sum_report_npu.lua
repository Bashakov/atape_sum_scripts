local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
local TYPES = require 'sum_types'
require 'ExitScope'

local sprintf = mark_helper.sprintf
local printf = mark_helper.printf
local errorf = mark_helper.errorf
local table_find = mark_helper.table_find

-- =============================================================================

local NPU_guids = {
	TYPES.NPU, -- НПУ
}

local NPU_guids_2 = {
	TYPES.NPU2, -- НПУ БС
}

local NPU_guids_uzk = {
	"{29FF08BB-C344-495B-82ED-000000000011}",
}

-- =============================================================================

local function _check_marks_path_coord(marks, dlg)
	local accept = {}
	local reject = {}
	for i, mark in ipairs(marks) do
		local cc = { -- проверим левый край, центр и правый край
			mark.prop.SysCoord,
			mark.prop.SysCoord + mark.prop.Len / 2,
			mark.prop.SysCoord + mark.prop.Len,
		}
		local skip = false
		for _, coord in ipairs(cc) do
			local km = Driver:GetPathCoord(coord)
			if not km then
				skip = true
				break
			end
		end

		if skip then
			table.insert(reject, mark)
		else
			table.insert(accept, mark)
		end

		if i % 100 == 0 and dlg and not dlg:step(i / #marks, sprintf('Проверка координаты отметок %d / %d', i, #marks)) then
			return {}, {}
		end
	end
	return accept, reject
end

local function report_NPU(params)
	return EnterScope(function (defer)
    local dlg = luaiup_helper.ProgressDlg('Построение отчета НПУ')
    defer(dlg.Destroy, dlg)

	local marks_drv = Driver:GetMarks{ListType='list', GUIDS=params.guids}
	local marks, reject = _check_marks_path_coord(marks_drv, dlg)

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
	if #reject > 0 then
		local msg = string.format('Из отчета были исключены %d отметок на неопределенной координате', #reject)
		iup.Message('Info', msg)
	end
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

	local test_report  = require('local_data_driver')
	-- test_report.Driver('D:\\d-drive\\ATapeXP\\Main\\test\\1\\[987]_2022_02_04_01.xml', nil) --
	test_report.Driver("D:\\ATapeXP\\Main\\494\\video\\[494]_2017_06_08_12.xml")

	report_NPU(cur_reports[1].params)
	--ekasui_rails()
	
end

return {
	AppendReports = AppendReports,
}
