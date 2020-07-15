local stuff = require 'stuff'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
require "ExitScope"

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

-- =============================================== --

local joints_guids = 
{
	"{CBD41D28-9308-4FEC-A330-35EAED9FC801}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC804}",
}

local switch_guids = {
	"{19253263-2C0B-41EE-8EAA-000000100000}",
	"{19253263-2C0B-41EE-8EAA-000000200000}",
	"{19253263-2C0B-41EE-8EAA-000000400000}",
	"{19253263-2C0B-41EE-8EAA-000000800000}",
}

-- =============================================== --

-- вычислить длинну рельса между двума стыками с учетом ширины зазора
local function get_rail_len(mark1, mark2)
	local l = math.abs(mark2.prop.SysCoord - mark1.prop.SysCoord)
	local w1 = mark_helper.GetGapWidth(mark1) or 0
	local w2 = mark_helper.GetGapWidth(mark2) or 0
	return l - (w1 + w2) / 2
end

--[[ проверить что отметки рельс является рубкой 

2020.06.18 ТребованияРУБКИ.docx:
к рельсовым рубкам относятся рельсы, длина которых отличается от стандартной (25,0-24,84 м, 12,52 – 12,38 м)
и находится в диапазоне от 6 до 25 метров ]]
local function check_rail_is_rubka(mark1, mark2)
	local rail_len = get_rail_len(mark1, mark2)
	if rail_len < 25 and rail_len > 24.84 then
		return false
	end
	if rail_len < 12.52 and rail_len > 12.38 then
		return false
	end
	return true
end

-- ищет рубки, возвращает массив пар отметок, ограничивающих врезку
local function scan_for_short_rail(marks, min_length)
	local res = {}
	local prev_mark = {}
	
	for _, mark in ipairs(marks) do
		local rail = bit32.band(mark.prop.RailMask)
		local coord = mark.prop.SysCoord
		if prev_mark[rail] and coord - prev_mark[rail].coord < min_length and check_rail_is_rubka(prev_mark[rail].mark, mark) then
			table.insert(res, {prev_mark[rail].mark, mark})
		end
		prev_mark[rail] = {coord=coord, mark=mark}
	end
	return res
end

-- проверить что координата находится в стрелке
local function is_inside_switch(switches, coords)
	for _, switch in ipairs(switches) do
		local inside = true
		for _, c in ipairs(coords) do
			if c < switch.from or switch.to < c then
				inside = false
				break
			end
		end
		if inside then
			return switch.id
		end
	end
	return nil
end

-- найти все стрелки
local function scan_for_rr_switch()
	local marks = Driver:GetMarks{ListType='all', GUIDS=switch_guids}
	local res = {}
	for i = 1, #marks do
		local mark = marks[i]
		local prop = mark.prop
		res[#res+1] = {from=prop.SysCoord, to=prop.SysCoord + prop.Len, id=prop.ID}
	end
	printf('found %d switches', #res)
	return res
end

-- сгенерировать и вставить картинку в отчет
local function insert_frame(excel, data_range, mark, row, col, video_channel, show_range)
	local img_path
	local ok, msg = pcall(function ()
			img_path = mark_helper.MakeMarkImage(mark, video_channel, show_range, false)
		end)
	if not ok then
		data_range.Cells(row, col).Value2 = msg and #msg and msg or 'Error'
	elseif img_path and #img_path then
		excel:InsertImage(data_range.Cells(row, col), img_path)
	end
end
	

-- отчет по коротким стыкам
local function report_short_rails(params)
	EnterScope(function(defer)
		local ok, min_length = iup.GetParam(params.sheetname, nil, "Верхний порог длины рельса (м): %i\n", 30 )
		if not ok then	
			return
		end
			
		local dlg = luaiup_helper.ProgressDlg()
		defer(dlg.Destroy, dlg)
		local marks = Driver:GetMarks()
		
		marks = mark_helper.filter_marks(marks, 
			function (mark) -- filter
				return stuff.table_find(joints_guids, mark.prop.Guid) and mark.ext.RAWXMLDATA
			end, 
			function (all, checked, accepted) -- progress
				if checked % 20 == 0 then
					dlg:step(checked / all, string.format('Сканирование %d / %d отметок, выбрано %d', checked, all, accepted))
				end
			end
		)
		marks = mark_helper.sort_mark_by_coord(marks)

		local short_rails = scan_for_short_rail(marks, min_length*1000)

		if #short_rails == 0 then
			iup.Message('Info', "Подходящих отметок не найдено")
			return
		end
		local rr_switchs = scan_for_rr_switch()
		
		local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
		excel:ApplyPassportValues(Passport)
		local data_range = excel:CloneTemplateRow(#short_rails)

		assert(#short_rails == data_range.Rows.count, 'misamtch count of mark and table rows')

		for line, mark_pair in ipairs(short_rails) do
			local mark1, mark2 = table.unpack(mark_pair)
			local prop1, prop2 = mark1.prop, mark2.prop
			local km1, m1, mm1 = Driver:GetPathCoord(prop1.SysCoord)
			local km2, m2, mm2 = Driver:GetPathCoord(prop2.SysCoord)
			local switch_id = is_inside_switch(rr_switchs, {prop1.SysCoord, prop2.SysCoord})
			
			local uri = mark_helper.MakeMarkUri(prop1.ID)
			local text_pos = sprintf("%d km %.1f = %d km %.1f", km1, m1 + mm1/1000, km2, m2 + mm2/1000)
			excel:InsertLink(data_range.Cells(line, 1), uri, text_pos)
			--data_range.Cells(line, 2).Value2 = sprintf("%.1f", (prop2.SysCoord - prop1.SysCoord) / 1000)
			data_range.Cells(line, 2).Value2 = sprintf("%.3f", get_rail_len(mark1, mark2) / 1000)
			data_range.Cells(line, 3).Value2 = mark_helper.GetRailName(mark1)
			if switch_id then
				local switch_uri = mark_helper.MakeMarkUri(switch_id)
				excel:InsertLink(data_range.Cells(line, 4), switch_uri, "Да")
			end
			
			local temperature = Driver:GetTemperature(bit32.band(prop1.RailMask, 3)-1, (prop1.SysCoord+prop2.SysCoord)/2 )
			local temperature_msg = temperature and sprintf("%.1f", temperature.target) or '-'
			data_range.Cells(line, 5).Value2 = temperature_msg:gsub('%.', ',')
			
			if math.abs(prop1.SysCoord - prop2.SysCoord) < 30000 then
				insert_frame(excel, data_range, mark1, line, 6, nil, {prop1.SysCoord-500, prop2.SysCoord+500})
			end
			
			if not dlg:step(line / #short_rails, stuff.sprintf('Сохранение %d / %d', line, #short_rails)) then 
				break
			end
		end 

		if ShowVideo == 0 then 
			excel:AutoFitDataRows()
			data_range.Cells(5).ColumnWidth = 0
		end
		
		excel:SaveAndShow()
	end)
end

-- =============================================== --

local cur_reports = 
{
	{
		name = "Короткие рубки|Excel", 
		fn = report_short_rails, 
		params = {filename="Scripts\\ProcessSum.xlsm", sheetname="Рубки"},
		guids = joints_guids,
	},
}

-- тестирование
if not ATAPE then

	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	local r = cur_reports[1]
	r.fn(r.params)
	--ekasui_rails()
end

return 
{
	AppendReports = function (reports)
		for _, report in ipairs(cur_reports) do
			table.insert(reports, report)
		end
	end
}