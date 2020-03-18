local stuff = require 'stuff'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'

local sprintf = stuff.sprintf
local printf = stuff.printf
local errorf = stuff.errorf

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

-- сделать строку ссылку для открытия атейпа на данной отметке
local function make_mark_uri(markid)
	local link = stuff.sprintf(" -g %s -mark %d", Passport.GUID, markid)
	link = string.gsub(link, "[%s{}]", function (c)
			return string.format("%%%02X", string.byte(c))
		end)
	return "atape:" .. link
end

-- ============================================================================= 

local function report_NPU(params)
	local dlg = luaiup_helper.ProgressDlg()
	
	local marks = Driver:GetMarks{ListType='list'}
	
	marks = mark_helper.filter_marks(
		marks, 
		function(mark)
			return stuff.table_find(params.guids, mark.prop.Guid)
		end, 
		function(all, checked, accepted)
			if checked % 20 == 0 then
				dlg:step(checked / all, string.format('Check %d / %d mark, accept %d', checked, all, accepted))
			end
		end
	)

	marks = mark_helper.sort_mark_by_coord(marks)

	if #marks == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end
	
	local excel = excel_helper(Driver:GetAppPath() .. params.filename, nil, false)
	
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#marks, 1)

	assert(#marks == data_range.Rows.count, 'misamtch count of mark and table rows')

	local full_len = 0
	for line, mark in ipairs(marks) do
		local prop = mark.prop
		local ext = mark.ext
		local km1, m1, mm1 = Driver:GetPathCoord(prop.SysCoord)
		local km2, m2, mm2 = Driver:GetPathCoord(prop.SysCoord + prop.Len)
		local rail_name = mark_helper.GetMarkRailPos(mark) == 1 and "Правый" or "Левый"
		local create_time = ext.CREATE_TIME and os.date(' %Y-%m-%d %H:%M:%S ', ext.CREATE_TIME) or ''
		local update_time = ext.UPDATE_TIME and os.date(' %Y-%m-%d %H:%M:%S ', ext.UPDATE_TIME) or ''
		
		if Passport.INCREASE == '0' then
			km1, m1, mm1, km2, m2, mm2 = km2, m2, mm2, km1, m1, mm1
		end
		
		local uri = make_mark_uri(prop.ID)
--		excel:InsertLink(data_range.Cells(line, 2), uri, tonumber(line))
	
	
		excel:InsertLink(data_range.Cells(line, 13), uri, tonumber(line))
		data_range.Cells(line, 14).Value2 = sprintf("%d км %.1f м", km1, m1 + mm1/1000)
		data_range.Cells(line, 15).Value2 = sprintf("%d км %.1f м", km2, m2 + mm2/1000)
		data_range.Cells(line, 16).Value2 = rail_name
		data_range.Cells(line, 17).Value2 = sprintf('%.2f', prop.Len / 1000):gsub('%.', ',')
		data_range.Cells(line, 18).Value2 = prop.Description
--		data_range.Cells(line, 4).Value2 = sprintf("%d км %.1f м", km1, m1 + mm1/1000)
--		data_range.Cells(line, 5).Value2 = sprintf("%d км %.1f м", km2, m2 + mm2/1000)


--		data_range.Cells(line, 7).Value2 = sprintf("%d км", km1)
--		data_range.Cells(line, 9).Value2 = sprintf("%d м",  m1 )
--		data_range.Cells(line,10).Value2 = sprintf("%d км", km2)
--		data_range.Cells(line,12).Value2 = sprintf("%d м",  m2 )
--
--		data_range.Cells(line, 6).Value2 = get_rail_name(mark)
--		data_range.Cells(line,13).Value2 = sprintf('%.2f', prop.Len / 1000):gsub('%.', ',')
--		data_range.Cells(line,14).Value2 = prop.Description


		data_range.Cells(line,19).Value2 = create_time
		data_range.Cells(line,20).Value2 = update_time
		
		if not dlg:step(line / #marks, stuff.sprintf(' Out %d / %d line', line, #marks)) then 
			break
		end
		
		full_len = full_len + prop.Len
		printf("%d: %f %f %s %f = %.2f\n", line, prop.Len, full_len, full_len/1000, full_len/1000, full_len/1000)
	end 
	
	data_range.Cells(#marks+2, 13).Value2 = sprintf('%.2f', full_len / 1000.0):gsub('%.', ',')

	if dlg and iup and dlg.dlgProgress then
		iup.Destroy(dlg.dlgProgress)
	end
	
	excel:SaveAndShow()
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
	test_report('D:\\d-drive\\ATapeXP\\Main\\test\\test\\[987]_2019_10_22_02.xml')
	
	report_NPU(cur_reports[1].params)
	--ekasui_rails()
end

return {
	AppendReports = AppendReports,
}
