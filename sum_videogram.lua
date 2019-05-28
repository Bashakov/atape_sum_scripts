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

local function insert_video_channel_set(excel, cell, num_channel_set, syscoord, rail, width, height)
	local prm = 
	{
		width = excel:point2pixel(width),
		height = excel:point2pixel(height),
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
		if num_channel_set and mark and report_row then
			insert_video_channel_set(excel, cell, num_channel_set, report_row.SYS, bit32.band(mark.prop.RailMask, 3), cell.MergeArea.Width, cell.MergeArea.Height)
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


local function videogram_mark(params)
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


local function videogram_view(params)
	local param_names = {'video_set', 'width_mm', 'coord', 'rail'}
	for _, name in ipairs(param_names) do
		if not params[name] then
			errorf('missing parameter [%s]', name)
		end
		printf('params.%s = %s\n', name, params[name])
	end
		
		
	local template_path = Driver:GetAppPath() .. 'Scripts\\'  .. 'ВЫХОДНАЯ ФОРМА ВИДЕОФИКСАЦИИ ВЕРХНЕГО СТРОЕНИЯ ПУТИ.xlsm'
	-- local template_path = Driver:GetAppPath() .. 'Scripts\\'  .. '1.xlsx'
	local excel = excel_helper(template_path, 'В7 ВИД ПАК', false, dst_name)
	
	excel:ApplyPassportValues(Passport)
	excel:ApplyRows({}, nil, nil)

	local worksheet = excel._worksheet
	local user_range = worksheet.UsedRange
	
	-- printf('excel user range: row = %d, col = %d, cells = %d\n', user_range.Rows.count, user_range.Columns.count, user_range.Cells.count)
	for n = 1, user_range.Cells.count do						-- пройдем по всем ячейкам	
		local cell = user_range.Cells(n);
		local val = cell.Value2	
		
--		printf('cell (%s, %s) size = (%s, %s) (%s, %s)  text = %s\n', 
--			cell.row, cell.column, 
--			cell.Width, cell.Height, 
--			cell.MergeArea.Width, cell.MergeArea.Height,
--			val or '')
		
		if val and val == '$VIDEO$' then
			local frame_prm = 
			{
				width 		= excel:point2pixel(cell.MergeArea.Width),
				height 		= excel:point2pixel(cell.MergeArea.Height),
				rail 		= params.rail,
				width_mm	= params.width_mm,
			}
			
			local ok, res = pcall(function() 
				return Driver:GetVideoImage(params.video_set, params.coord, frame_prm)
			end)
			
			if ok then
				if res and #res > 1 then
					excel:InsertImage(cell, res)
				end
			else
				cell.Value2 = res  -- insert error string
			end
		end
	end
	
	excel:AppendTemplateSheet(Passport, {}, nil, 3)
	excel:SaveAndShow()
end


-- ================================= 

local function get_videogram(name)
	local videogram_list = 
	{
		{name = 'mark',    	fn = videogram_mark},
		{name = 'view',    	fn = videogram_view}
	}
	
	for _, r in ipairs(videogram_list) do
		if r.name == name then
			return r
		end
	end
end


-- ================================= ЭКСПОРТ ================================= 

-- проверить что такая видеограмма известна
function IsVideogramAvailable(name)
	return get_videogram(name) ~= nil
end

-- сделать видеограмму
function MakeVideogram(name, params)
	local videogram = get_videogram(name)
	if not videogram then 
		errorf('unknown videogram [%s]', name)
	end
	
	videogram.fn(params)
end
		

-- ================================= теситрование ================================= 

if not ATAPE then

	test_report  = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	
	--report_rails()
	videogram_view()
end

