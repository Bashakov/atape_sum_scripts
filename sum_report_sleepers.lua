if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"


local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local DEFECT_CODES = require 'report_defect_codes'


function printf(s,...)  print(s:format(...)) end
function sprintf(s,...) return s:format(...) end

local guigs_sleepers = 
{
	"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}"
}

-- запросить у пользователя эпюру шпал
local function ask_user_report_param()
	local ok, sleeper_count, mek, angle_threshold = true, 1840, 4, 5.7
	if true then -- показывать ли диалог
		ok, sleeper_count, mek, angle_threshold  = iup.GetParam("Отчет оп шпалам", nil, 
			"Эпюра шпал: %i\n\z
			МКЭ: %i\n\z
			Разворот: %r\n\z", 
			sleeper_count, mek, angle_threshold)
	end
	if not ok then	
		return -1
	end
	return 1000000 / sleeper_count, mek, angle_threshold
end

local function check_distance(ref_dist, MEK, max_diff, cur_dist)
	if cur_dist < 200 then
		return true
	end
	for i = 1, MEK do
		if math.abs(cur_dist/i - ref_dist) <= max_diff then
			return true
		end
	end
	return false
end


-- проверить список из 3х отметок шпал, если у средней проблемы, добавить ее в выходной список
local function check_sleeper_error(left, cur, right, ref_dist, MEK, angle_threshold)
	local diffs = 
	{
		[1] = 2*40, -- "бетон",
		[2] = 2*80, -- "дерево",
	}

	local cur_material = mark_helper.GetSleeperMeterial(cur)
	local cur_angle = mark_helper.GetSleeperAngle(cur) or 0
	local max_diff = diffs[cur_material] or 80
	
	local dist_prev = cur.prop.SysCoord - left.prop.SysCoord 
	local dist_next = right.prop.SysCoord - cur.prop.SysCoord 
	cur.user.SLEEPER_DIST_PREV = dist_prev
	cur.user.SLEEPER_DIST_NEXT = dist_next
	
	local ret_defects = {}
	
	--local dist_ok = check_distance(ref_dist, MEK, max_diff, dist_prev) and check_distance(ref_dist, MEK, max_diff, dist_next)
	local dist_ok = check_distance(ref_dist, MEK, max_diff, dist_next)
	if not dist_ok then
		if cur_material == 1 then -- "бетон",
			table.insert(ret_defects, DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE)
		elseif cur_material == 2 then -- "дерево",
			table.insert(ret_defects, DEFECT_CODES.SLEEPER_DISTANCE_WOODEN)
		end
	end
	
	cur_angle = cur_angle * 180/3.14/1000
	if math.abs(cur_angle) > angle_threshold then
		table.insert(ret_defects, DEFECT_CODES.SLEEPER_ANGLE)
	end
	
	--printf("%9d %3d | %+8.1f  %+8.1f deg | %s", cur.prop.SysCoord, max_diff,  dist_next-ref_dist, cur_angle, table.concat(ret_defects, ','))
	return ret_defects
end

-- сделать из отметки таблицу и подставновками
local function make_result_row(mark)
	local row = mark_helper.MakeCommonMarkTemplate(mark)
	local material = mark_helper.GetSleeperMeterial(mark) 
	
	row.DEFECT_CODE = table.concat(mark.user.arr_defect_codes, ', ')
	row.SLEEPER_MATERIAL = material and (material == 1 and "ЖБШ" or "ДШ") or ''
	row.SLEEPER_DIST_PREV = mark.user.SLEEPER_DIST_PREV or ''
	row.SLEEPER_DIST_NEXT = mark.user.SLEEPER_DIST_NEXT or ''
	return row
end


local function make_report()
	local template_path = Driver:GetAppPath() .. 'Scripts/ВЕДОМОСТЬ ОТСТУПЛЕНИЙ В СОДЕРЖАНИИ ШПАЛ.xlsm'
	local marks = Driver:GetMarks{GUIDS=guigs_sleepers}
	marks = mark_helper.sort_mark_by_coord(marks)
	
	if false then
		marks = mark_helper.filter_marks(marks, function(mark) 
			return bit32.btest(mark.prop.RailMask, 0x01)
		end)
	end
	
	if #marks  < 3 then
		return
	end
	
	local ref_dist, MEK, angle_threshold = ask_user_report_param()
	if ref_dist < 0 then
		return
	end
		
	local dlgProgress = luaiup_helper.ProgressDlg()
	
	local out_marks = {}
	local i = 0
	for left, cur, right in mark_helper.enum_group(marks, 3) do
		i = i + 1
		if i % 10 == 0 and not dlgProgress:step(i / #marks, stuff.sprintf('Check %d / %d mark found %d mark', i, #marks, #out_marks)) then 
			return
		end
		
		local arr_defect_codes = check_sleeper_error(left, cur, right, ref_dist, MEK, angle_threshold)
		if #arr_defect_codes > 0 then
			cur.user.arr_defect_codes = arr_defect_codes
			table.insert(out_marks, cur)
			
			--if #out_marks > 10 then	break end
		end
	end
	
	if #out_marks > 1000 then
		local msg = sprintf('Найдено %d проблемных шпал, построение отчета может занять большое время, продолжить?', #out_marks)
		local cont = iup.Alarm("Warning", msg, "Yes", "No")
		if cont == 2 then
			return
		end
	end
	
	local ext_psp = mark_helper.GetExtPassport(Passport)
	
	local excel = excel_helper(template_path, "В3 ШП", false)
	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(out_marks, make_result_row, dlgProgress)
	excel:AppendTemplateSheet(ext_psp, out_marks, make_result_row, 3)
	excel:SaveAndShow()
end


local function sleepers_report_plot()
	local marks = Driver:GetMarks{GUIDS=guigs_sleepers}
	marks = mark_helper.sort_mark_by_coord(marks)
	
	local excel = luacom.CreateObject("Excel.Application")
	assert(excel, "Error! Could not run EXCEL object!")
	
	-- excel.visible = true

	local worksheet = nil
	
	if false then
		local dlgProgress = luaiup_helper.ProgressDlg()
		
		local workbooks = excel.Workbooks
		workbooks:Add()
		local workbook = workbooks(1)
		worksheet = workbook.Sheets(1)
		-- worksheet.Name = 'Разворот'
		
		local prev = nil
		for i = 1, #marks do
	--		if i > 100 then
	--			break
	--		end
			local mark = marks[i]
			local prop = mark.prop
			
			local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
			local path = sprintf('%d км %5.1f м', km, m + mm/1000)
			
			local angle = mark_helper.GetSleeperAngle(mark) or 0
			angle = angle * 180/3.14/1000
			
			worksheet.Cells(i, 1).Value2 = i
			worksheet.Cells(i, 2).Value2 = prop.SysCoord
			worksheet.Cells(i, 3).Value2 = path
			worksheet.Cells(i, 4).Value2 = angle
			worksheet.Cells(i, 5).Value2 = prev and prop.SysCoord-prev or 0
			
			prev = prop.SysCoord
			if i % 30 == 0 and not dlgProgress:step(i / #marks, stuff.sprintf('out %d / %d mark', i, #marks)) then 
				break
			end
		end
	else
		local fn = sprintf("%s\\sleepers_%s.csv", os.getenv("TEMP"), os.date('%y%m%d%H%M%S'))
		local fo = io.open(fn, 'w+')
		local prev = nil
		for i = 1, #marks do
			local mark = marks[i]
			local prop = mark.prop
			
			local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
			local path = sprintf('%d km %5.1f m', km, m + mm/1000)
			
			local angle = mark_helper.GetSleeperAngle(mark) or 0
			--angle = angle * 180/3.14/1000
			
			local row = {
				i, 
				prop.SysCoord,
				path,
				angle,
				prev and prop.SysCoord-prev or 0
			}
			fo:write(table.concat(row, ';') .. '\n')
			
			prev = prop.SysCoord
		end
		fo:close()
		
		local workbook = excel.Workbooks:Open(fn)
		worksheet = workbook.Sheets(1)
	end

	excel.visible = true
	
	local shape = worksheet.Shapes:AddChart2(1, 4, 250, 10, 800, 250)
	local chart = shape.Chart
	chart.ChartTitle.Text = 'Разворот'
    chart:SetSourceData(worksheet:Range("D:D"))
	chart:SeriesCollection(1).XValues = worksheet:Range("C:C")
	
	
	shape = worksheet.Shapes:AddChart2(1, 4, 250, 260, 800, 250)
	chart = shape.Chart
	chart.ChartTitle.Text = "Расстояние"
    chart:SetSourceData(worksheet:Range("E:E"))
	chart:SeriesCollection(1).XValues = worksheet:Range("C:C")
    chart:Axes(2).MaximumScale = 1000
	
end


-- ============================================================================= 

local function AppendReports(reports)
	local sleppers_reports = 
	{
		{name = 'Ведомость отступлений в содержании шпал|Эпюра и перпендикулярность шпал',    	fn=make_report, 		guids=guigs_sleepers},
		{name = 'Ведомость отступлений в содержании шпал|график',		                        fn=sleepers_report_plot,guids=guigs_sleepers},		
	}

	for _, report in ipairs(sleppers_reports) do
		table.insert(reports, report)
	end
end


return {
	AppendReports = AppendReports,
}