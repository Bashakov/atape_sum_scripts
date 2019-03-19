if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

require "luacom"

local stuff = require 'stuff'
local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'


local table_find = stuff.table_find
local sprintf = stuff.sprintf
local printf = stuff.printf
local errorf = stuff.errorf

-- ============================================================================= 

local function insert_video_chennel_set(excel, cell, num_channel_set, syscoord, rail, width, height)
	local prm = 
	{
		width = width,
		height = height,
		rail = rail
	}
	
	local ok, res = pcall(function() 
		--error('test')
		return Driver:GetVideoImage(num_channel_set, syscoord, prm)
	end)
	
	if ok then
		if res and #res > 1 then
			excel:InsertImage(cell, res)
		end
	else
		cell.Value2 = res
	end
end

local function insert_video_screen(excel, cell)
	local ok, res = pcall(function() 
		--error('test')
		return Driver:GetVideoScreen({})
	end)
	
	if ok then
		if res and #res > 1 then
			excel:InsertImage(cell, res)
		end
	else
		cell.Value2 = res
	end
end


local function insert_video_image(excel, mark, report_row)
	local worksheet = excel._worksheet
	local user_range = worksheet.UsedRange
	
	for n = 1, user_range.Cells.count do						-- пройдем по всем ячейкам	
		local cell = user_range.Cells(n);
		local val = cell.Value2	
		local num_channel_set = val and string.match(val, '%$VIDEO%((.-)%)%$')
		if num_channel_set then
			insert_video_chennel_set(excel, cell, num_channel_set, report_row.SYS, bit32.band(mark.prop.RailMask, 3), cell.MergeArea.Width, cell.MergeArea.Height)
		end
		
		if val and val == '$VIDEO_SCREEN$' then
			insert_video_screen(excel, cell)
		end
	end
end

-- ============================================================================= 

local Profiler = OOP.class
{
	ctor = function(self, name)
		self.name = name
		self.start = os.clock()
		self.prev = self.start 
		self.items = {}
	end,
	
	step = function(self, name)
		local t = os.clock()
		table.insert(self.items, {name=name, duration=t-self.prev})
		self.prev = t
	end,
	
	show = function(self)
		local res = {sprintf('Profiler: %s, all %.3f sec', self.name, os.clock() - self.start)}
		for _, item in ipairs(self.items) do
			res[#res+1] = sprintf('\t%30s: %10.1f ms', item.name, item.duration * 1000)
		end
		return table.concat(res, '\n')
	end,
}
		

local function make_videogram_report_mark(mark)
	local profiler = Profiler('make_videogram_report_mark')
	
	local report_row = mark_helper.MakeCommonMarkTemplate(mark)
	profiler:step("MakeCommonMarkTemplate")
	local report_rows = {report_row}
	
	local ext_psp = mark_helper.GetExtPassport(Passport)
	profiler:step("GetExtPassport")
	
	local template_path = Driver:GetAppPath() .. 'Scripts\\'  .. 'ВЫХОДНАЯ ФОРМА ВИДЕОФИКСАЦИИ ВЕРХНЕГО СТРОЕНИЯ ПУТИ.xlsm'
	local excel = excel_helper(template_path, 'В7 ВИД', false, dst_name)
	profiler:step("excel_helper")
	
	excel:ApplyPassportValues(ext_psp)
	profiler:step("ApplyPassportValues")
	
	excel:ApplyRows(report_rows, nil, nil)
	profiler:step("ApplyRows")
	
	insert_video_image(excel, mark, report_row)
	profiler:step("insert_video_image")
	
	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	profiler:step("AppendTemplateSheet")
	
	excel:SaveAndShow()
	profiler:step("SaveAndShow")
	
	--iup.Message('Info', profiler:show())
end


local function report_videogram()
	local marks = Driver:GetMarks{}
	marks = mark_helper.sort_mark_by_coord(marks)
	
	if #marks == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end
	
	local cont = 1
	if #marks > 1 then
		local msg = sprintf('Отмечено %d отметок, построение отчета может занять большое время, продолжить?', #marks)
		cont = iup.Alarm("Warning", msg, "Yes", "Only First", "No")
	end
	
	if cont == 3 then
		return
	end
	
	for i, mark in ipairs(marks) do
		make_videogram_report_mark(mark)
		if cont == 2 then
			break
		end
	end
end



-- ============================================================================= 


-- регистрируем наш отчет
local function AppendReports(reports)
	table.insert(reports, 
		{name = 'Видеограмма',    	fn = report_videogram}
	)
end

-- тестирование
if not ATAPE then

	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	--report_rails()
	report_videogram()
end

return {
	AppendReports = AppendReports,
}