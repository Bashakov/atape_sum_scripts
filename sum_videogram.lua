if not ATAPE then
	require "iuplua"
	require "luacom"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

local excel_helper = require 'excel_helper'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'

local table_find = mark_helper.table_find
local sprintf = mark_helper.sprintf
local printf = mark_helper.printf
local errorf = mark_helper.errorf

-- =============================================================================

local function insert_video_channel_set(excel, cell, num_channel_set, syscoord, rail, width, height)
	local prm =
	{
		width = excel:point2pixel(width),
		height = excel:point2pixel(height),
		rail = rail
	}

	local ok, res = pcall(function()
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

local function insert_video_screen(excel, cell, shown_mark)
	local ok, res = pcall(function()
		if shown_mark then
			local sys_center = shown_mark.prop.SysCoord + shown_mark.prop.Len / 2
			local video_screen_param = Driver:GetVideoScreenParam()
			local frame_prm = {
				width 		= excel:point2pixel(cell.MergeArea.Width),
				height 		= excel:point2pixel(cell.MergeArea.Height),
				rail 		= bit32.band(shown_mark.prop.RailMask, 3),
				width_mm	= video_screen_param.panoram_width, }
			return Driver:GetVideoImage(video_screen_param.current_video_set, sys_center, frame_prm)
		else
			return Driver:GetVideoScreen({})
		end
	end)

	if ok then
		if res and #res > 1 then
			excel:InsertImage(cell, res)
		end
	else
		cell.Value2 = res
	end
end


local function insert_video_image(excel, mark, report_row, own_frame)
	local worksheet = excel._worksheet
	local user_range = worksheet.UsedRange

	for n = 1, user_range.Cells.count do						-- пройдем по всем ячейкам
		local cell = user_range.Cells(n);
		local val = cell.Value2

		local num_channel_set = val and string.match(val, '%$VIDEO%((.-)%)%$')
		if num_channel_set and mark and report_row then
			insert_video_channel_set(
				excel,
				cell,
				num_channel_set,
				report_row.SYS,
				bit32.band(mark.prop.RailMask, 3),
				cell.MergeArea.Width,
				cell.MergeArea.Height)
		end

		if val and val == '$VIDEO_SCREEN$' then
			insert_video_screen(excel, cell, own_frame and mark)
		end
	end
end



local function get_path_coord(sys)
	local km, m, mm = Driver:GetPathCoord(sys)
	local pk = math.floor(m/100)+1
	return {km=km, pk=pk, m=m, mm=mm}
end

local function format_path_coord(path)
	local res = sprintf('%d км %.1f м', path.km, path.m + path.mm/1000)
	return res
end
-- =============================================================================

local function reset_atape_flag(fn, ...)
	-- сбрасываем флаг ATAPE в функции, чтобы не выполнялись разные тестовые функции в импортируемых модулях
	local prev_state = _G.ATAPE
	_G.ATAPE = true
	local results = {pcall(fn, ...)}
	_G.ATAPE = prev_state
	if not results[1] then
		error(results[2])
	end
	return table.unpack(results, 2)
end

local function merge_row_mark_param(name, values)
	local res = {}
	if values then
		local known = {}
		for _, value in ipairs(values) do
			if value ~= '' and not known[value] then
				table.insert(res, value)
				known[value] = 1
			end
		end
	end
	return table.concat(res, ', ')
end


local function make_mark_row_defects(mark, awailable_defect_codes)
	local check_defect_code = function(row)
		if not awailable_defect_codes then
			return true
		end
		if not row.DEFECT_CODE then
			return false
		end
		
		for _, dc in ipairs(awailable_defect_codes) do 
			if  tostring(dc) == tostring(row.DEFECT_CODE) or 
				tonumber(dc) == tonumber(row.DEFECT_CODE) then
				return true
			end
		end
	end
	
	local report_scripts = {
		'sum_report_beacon',
		'sum_report_fastener',
		'sum_report_joints',
		'sum_report_rails',
		'sum_report_sleepers',
	}
	
	local row_info = nil
	for _, name in ipairs(report_scripts) do
		local report = require(name)
		local cur_rep_rows = report and report.videogram and report.videogram(mark)
		for _, r in ipairs(cur_rep_rows or {}) do
			if check_defect_code(r) then
				for n, v in pairs(r) do
					if not row_info    then row_info    = {} end
					if not row_info[n] then row_info[n] = {} end
					table.insert(row_info[n], v)
				end
			end
		end
	end
	
	for name, value in pairs(row_info or {}) do
		row_info[name] = merge_row_mark_param(name, value)
	end
	return row_info
end


local function make_videogram_report_mark(mark, own_frame, awailable_defect_codes, direct_set_defect)
	
	local report_row
	if not direct_set_defect then 
		report_row = reset_atape_flag(make_mark_row_defects, mark, awailable_defect_codes)
	end
	if not report_row then
		report_row = mark_helper.MakeCommonMarkTemplate(mark)
		if direct_set_defect then
			report_row.DEFECT_CODE = direct_set_defect[1]
			report_row.DEFECT_DESC = direct_set_defect[2]
		end
	end

	local report_rows = {report_row}

	local ext_psp = mark_helper.GetExtPassport(Passport)

	local template_path = Driver:GetAppPath() .. 'Scripts\\'  .. 'ВЫХОДНАЯ ФОРМА ВИДЕОФИКСАЦИИ ВЕРХНЕГО СТРОЕНИЯ ПУТИ.xlsm'
	local excel = excel_helper(template_path, 'В7 ВИД', false)

	excel:ApplyPassportValues(ext_psp)
	excel:ApplyRows(report_rows, nil, nil)

	insert_video_image(excel, mark, report_row, own_frame)

	excel:CleanUnknownTemplates()

	excel:AppendTemplateSheet(ext_psp, report_rows, nil, 3)
	excel:SaveAndShow()
end


local function videogram_mark(params)
	local marks
	local own_frame = false
	if params and params.mark then
		marks = {params.mark}
		own_frame = true
	else
		marks = Driver:GetMarks{}
		marks = mark_helper.sort_mark_by_coord(marks)
	end

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
		make_videogram_report_mark(
			mark, 
			own_frame,
			params and params.defect_codes, 
			params and params.direct_set_defect)
		if cont == 2 then
			break
		end
	end
end

local function videogram_view_single()

	local template_path = Driver:GetAppPath() .. 'Scripts\\'  .. 'ВЫХОДНАЯ ФОРМА ВИДЕОФИКСАЦИИ ВЕРХНЕГО СТРОЕНИЯ ПУТИ.xlsm'
	local list_name = 'ВИД';
	--local list_name = 'В7 ВИД';

	local excel = excel_helper(template_path, list_name, false)

	local video_screen_param = Driver:GetVideoScreenParam()
	local sys_left  = video_screen_param.visible_coord - video_screen_param.panoram_width / 2
	local sys_right = video_screen_param.visible_coord + video_screen_param.panoram_width / 2

	Passport.REPORT_DATE = os.date(' %Y-%m-%d %H:%M:%S ')
	Passport.FromKm = format_path_coord(get_path_coord(sys_left))
	Passport.ToKm = format_path_coord(get_path_coord(sys_right))

	excel:ApplyPassportValues(Passport)
	if list_name ~= 'ВИД' then
		excel:ApplyRows({}, nil, nil) --чтобы не заполнять отсутствующую таблицу
	end

	local worksheet = excel._worksheet
	local user_range = worksheet.UsedRange

	for n = 1, user_range.Cells.count do						-- пройдем по всем ячейкам
		local cell = user_range.Cells(n);
		local val = cell.Value2

		if val == '$VIDEO_SCREEN$' then
			insert_video_screen(excel, cell)
		end
	end

	excel:AppendTemplateSheet(ext_psp, {}, nil, 0)
	excel:SaveAndShow()
end


local function videogram_view_packet(params)
	local param_names = {'width_show_mm', 'left_coord'}
	for _, name in ipairs(param_names) do
		if not params[name] then
			errorf('missing parameter [%s]', name)
		end
		printf('params.%s = %s\n', name, params[name])
	end

	local dlg = luaiup_helper.ProgressDlg()
	dlg:step(0, 'preparing ... ')
	local function progress_callback(cur, all)
		dlg:step(cur / all, 'processing ...')
	end

	local template_path = Driver:GetAppPath() .. 'Scripts\\'  .. 'ВЫХОДНАЯ ФОРМА ВИДЕОФИКСАЦИИ ВЕРХНЕГО СТРОЕНИЯ ПУТИ.xlsm'
	local sheet_name = 'В7 ВИД ПАК'
	local excel = excel_helper(template_path, 'В7 ВИД ПАК', false)

	Passport.FromKm = nil
	Passport.ToKm = nil
	Passport.REPORT_DATE = os.date(' %Y-%m-%d %H:%M:%S ')
	excel:ApplyPassportValues(Passport)

	local video_screen_param = Driver:GetVideoScreenParam()

	local img_count = math.ceil(params.width_show_mm / video_screen_param.panoram_width)
	img_count = math.max(img_count, 1)

	for i, dst_rng in excel:EnumDstTable(img_count, progress_callback) do
		local sys_left = params.left_coord + (i-1) * video_screen_param.panoram_width
		local sys_right = sys_left + video_screen_param.panoram_width
		local sys_center = (sys_left + sys_right) / 2
		printf('frame = %d, coord = %d\n', i, sys_center)

		local path_left = get_path_coord(sys_left)
		local path_right = get_path_coord(sys_right)
		local path_center = get_path_coord(sys_center)

		local values = {
			FromKm = format_path_coord(path_left),
			ToKm = format_path_coord(path_right),
			KM = path_center.km,
			M = path_center.m,
			MM = path_center.mm,
			PK = path_center.pk,
		}
		excel:ReplaceTemplates(dst_rng, {values})

		--printf('excel user range: row = %d, col = %d, cells = %d\n', dst_rng.Rows.count, dst_rng.Columns.count, dst_rng.Cells.count)

		for n = 1, dst_rng.Cells.count do						-- пройдем по ячейкам вставленной таблицы
			local cell = dst_rng.Cells(n);
			local val = cell.Value2

--			printf('cell (%s, %s) size = (%s, %s) (%s, %s)  text = %s\n',
--				cell.row, cell.column,
--				cell.width, cell.height,
--				cell.mergearea.width, cell.mergearea.height,
--				val or '')

			if val == '$VIDEO$' then
				local ok, strerror = pcall(function()
					local frame_prm =
					{
						width 		= excel:point2pixel(cell.MergeArea.Width),
						height 		= excel:point2pixel(cell.MergeArea.Height),
						rail 		= video_screen_param.rail_filter,
						width_mm	= video_screen_param.panoram_width,
					}
					local img_path = Driver:GetVideoImage(video_screen_param.current_video_set, sys_center, frame_prm)
					print(img_path)
					if img_path and #img_path > 1 then
						excel:InsertImage(cell, img_path)
					end
				end)

				if not ok then
					cell.Value2 = strerror  -- insert error string
				end
			end
		end
		dlg:step(i / img_count, 'generation ...')
	end

	excel:AppendTemplateSheet(Passport, {}, nil, 0)
	excel:SaveAndShow()
end


-- =================================

local function get_videogram(name)
	local videogram_list =
	{
		{name = 'mark',    			fn = videogram_mark},
		{name = 'view_packet',    	fn = videogram_view_packet},
		{name = 'view_single',    	fn = videogram_view_single}
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

	Driver.GetVideoScreenParam = function(self)
		return {
			visible_coord = 1000000,
			current_video_set = 1,
			panoram_width = 2000,
			rail_filter = 3,
		}
	end


	local savedGetMarks = Driver.GetMarks
	-- тестовая функция обертка: возвращает только одну отметку, для videogram_mark
	Driver.GetMarks = function(self, filter)
		return savedGetMarks(self, {mark_id=40})
	end

	videogram_mark()

	--videogram_view_packet({width_show_mm=9000, left_coord=100000})
	--videogram_view_single()
end


-- экспорт как модуля
return 
{
	MakeVideogram = MakeVideogram,
	IsVideogramAvailable = IsVideogramAvailable
}
