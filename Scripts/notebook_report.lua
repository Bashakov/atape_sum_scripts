if not ATAPE then
	require "luacom"
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end


luaiup_helper = require 'luaiup_helper'
excel_helper = require 'excel_helper'
mark_helper = require 'sum_mark_helper'
require 'ExitScope'

local function errorf(s, ...)     
	error(string.format(s, ...))
end

local function make_filter_progress_fn(dlg)
	return function(all, checked, accepted)
		if dlg then
			dlg:step(checked / all, string.format('Check %d / %d mark, accept %d', checked, all, accepted))
		end
	end
end

local function is_record_included(record)
	local ok = record.INCLUDED ~= "FALSE"
	return ok
end

local function is_record_selected(record)
	local ok = record.USER_SELECTED == "1"
	return ok
end

local function filter_included_mark(records, dlg)
	local res = mark_helper.filter_marks(records, is_record_included, make_filter_progress_fn(dlg))
	return res
end

local function filter_selected_mark(records, dlg)
	local res = mark_helper.filter_marks(records, is_record_selected, make_filter_progress_fn(dlg))
	return res
end

local function get_record_rail(record)
	local thread = record.THREAD
	local record_left_rail = false
	if thread then
		for _, t in ipairs{'^л', '^Л', '^l', '^L'} do
			-- print(t, thread, thread:match(t), record_left_rail)
			record_left_rail = record_left_rail or thread:match(t)
		end
	end

	local res = tonumber(Passport.FIRST_LEFT)
	if record_left_rail then
		res = bit32.bxor(res, 1)
	end
	return res
end

local function make_report_dir()
	local folter = os.getenv('USERPROFILE') .. '\\ATapeReport\\' .. os.date('%y%m%d-%H%M%S') .. '\\'
	os.execute('mkdir ' .. folter)
	return folter
end

local function format_path_coord(record)
	local km, m, mm = Driver:GetPathCoord(record.MARK_COORD)
	local res = string.format('%d км %.1f м', km, m + mm/1000)
	return res
end

local function get_str_sved(record)
	local desc = {"Без сведения", "Сведение сдвигом", "Полное сведение", "Сечение рельса"}
	local res = desc[record.SVED+1]
	return res
end

local function GetBase64EncodedFrame(record)
	local rail = get_record_rail(record)
	local video_channel = rail==1 and 18 or 17
	local video_img
	local ok, err = pcall(function()
		video_img = Driver:GetFrame(video_channel, record.MARK_COORD, {mode=3, panoram_width=700, width=400, height=300, base64=true} )
	end)
	if not ok then
		video_img = err
	end
	return video_img
end


local function InsertVideoFrame(excel, cell, record)
	local rail = get_record_rail(record)
	local video_channel = rail==1 and 18 or 17
	local prms = {mode=3, panoram_width=700, width=800, height=500, base64=base64}

	local ok, res = pcall(function()
		return Driver:GetFrame(video_channel, record.MARK_COORD, prm)
	end)

	if ok then
		if res and #res > 1 then
			excel:InsertImage(cell, res)
		end
	else
		cell.Value2 = res
		--cell.RowHeight = 2
	end
end


local function insertVideoScreen(excel, cell, record, width_mm)
	local ok, res = pcall(function()
		local frame_prm = {
			width 		= excel:point2pixel(cell.MergeArea.Width) * 2,
			height 		= excel:point2pixel(cell.MergeArea.Height) * 2,
			rail 		= get_record_rail(record),
			width_mm	= width_mm, }
		return Driver:GetVideoImage(0, record.MARK_COORD, frame_prm)
	end)

	if ok then
		if res and #res > 1 then
			excel:InsertImage(cell, res)
		end
	else
		cell.Value2 = res
	end
end

local function read_pref_cfg_param(name)
	local pref_path = os.getenv("ProgramFiles") .. '\\ATapeXP\\preferences.cfg'
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom, 'can not create MSXML object')
	assert(xmlDom:load(pref_path), "can not open xml file: " .. pref_path)
	local xpath = "//FIELD[@INNER_NAME='" .. name .. "']/@VALUE"
	local value = xmlDom:selectSingleNode(xpath)
	return value and value.nodeValue
end

local function read_pref_cfg_param_num(name)
	return tonumber(read_pref_cfg_param(name))
end

-- =================== Отчеты =====================

-- отчет по отметкам записой книжки с выводом в excel
local function vedomost_with_US_images_excel(records)
	local insert_us_img = true
	local insert_video_img = true

	local dlg = luaiup_helper.ProgressDlg()

	records = filter_included_mark(records, dlg)

	if #records == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		dlg:Destroy()
		return
	end

	local excel = excel_helper(Driver:GetAppPath() .. 'Telegrams\\VedomostTemplate.xls', nil, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#records, 1)

	if insert_us_img then
		data_range.Columns(18).ColumnWidth = 40.0
	end
	if insert_video_img then
		data_range.Columns(19).ColumnWidth = 40.0
	end

	assert(#records == 0 or #records == data_range.Rows.count, 'misamtch count of mark and table rows')

	for line, record in ipairs(records) do
		local km, m, mm = Driver:GetPathCoord(record.MARK_COORD)

		local dst_row = data_range.Rows(line)
		excel:ReplaceTemplates(dst_row, {record, {N=line}})

		if insert_us_img or insert_video_img then
			data_range.Rows(line).RowHeight = 100.0
		end

		if insert_us_img and Driver.GetUltrasoundImage then
			local us_img_path = Driver:GetUltrasoundImage{note_rec=record, width=800, height=600, color=1, coord=record.MARK_COORD}
			if us_img_path and #us_img_path then
				excel:InsertImage(data_range.Cells(line, 18), us_img_path)
			end
		end

		if insert_video_img and Driver.GetFrame then
			InsertVideoFrame(excel, data_range.Cells(line, 19), record)
		end

		if not dlg:step(line / #records, string.format(' Process %d / %d mark', line, #records)) then
			break
		end
	end

	dlg:Destroy()
	excel:SaveAndShow()
end

local function report_html_properties(records)
	local resty = require "resty.template"
	local view = resty.compile[[
<!DOCTYPE html>
<html>
	<head>
		<meta charset="utf-8">
		<title>{{Passport.NAME}}</title>
	</head>

<body>
	<h1>Список Свойств отметок</h1>

	<table>
	{% for i, record in ipairs(records) do %}
		<tr>
			<th>Отметка: {{i}}</th>
		</tr>
		{% for name, value in pairs(record) do %}
			<tr>
				<td>{{name}}</td>
				<td>{{value}}</td>
			</tr>
		{% end %}
	{% end %}
	<table>
	<br/>
</body>
</html>]]

	local folter = make_report_dir()
	local file_name = folter .. 'record_propertyes.html'

	local res = view{records=records}

	local dst_file = assert(io.open(file_name, 'w+'))
	dst_file:write(res)
	dst_file:close()

	os.execute("start " .. file_name)
end


local function vedomost_with_US_images_html(records)
	local resty = require "resty.template"

	local css_style = [[
html {
    font-family: Times New Roman;
	font-size: 14px;
}

body {
    margin: 0;
}

h1 {
    font-size: 16px;
}

h1, h2, h3{
	text-align: center;
}

table {
    border-collapse: collapse;
    border-spacing: 0;
}

th{
	padding: 6px 10px
}

td {
	padding: 4px 9px
}


.Records th,
.Records td {
	border: 1px solid #ccc;
}

table.DataDesc {
	width: 100%;
}

.DataDesc th,
.DataDesc td {
	border: none;
	font-size: 14px;

}
]]

	local view = resty.compile[[
<!DOCTYPE html>
<html>
	<head>
		<meta charset="utf-8">
		<title>{{Passport.NAME}}</title>
	</head>
	<style type="text/css">{{css_style}}</style>
<body>
	<h1>Начальнику дистанции пути ПЧ<br/>
	ВЕДОМОСТЬ №
	</h1>

	<table class='DataDesc'>
		<tr>
			<td>
				результатов контроля совмещенным вагоном-дефектоскопом № {{Passport.FORMED}} на участке:
			</td>
		</tr>
		<tr>
			<td>{{Passport.DIRECTION}} {{Passport.TRACK_NUM}} путь.</td>
			<td>ПЧ- </td>
			<td>{{string.gsub(Passport.DATE, '(%d+):(%d+):(%d+):(%d+):(%d+)', '%1.%2.%3')}}</td>
		</tr>
	</table>

	<table class='Records'>
	<tr>
		<th>№</th>
		<th>Перегон</th>
		<th>Путь</th>
		<th>Км</th>
		<th>Пк</th>
		<th>метр</th>
		<th>Звено/плеть</th>
		<th>Нитка</th>
		<th>Шпала</th>
		<th>Дополнительные ориентиры о расположении дефекта</th>
		<th>Вид дефекта по результатам расшифровки, заключение начальника вагона.</th>
		<th>Дата, результаты вторичного контроля, № и тип дефектоскопа, принятые меры, ФИО, роспись оператора.</th>
		<th>Дата замены рельса, № пред., время</th>
		<th>Примечание, вид осмотра</th>
	</tr>
	<tr>
	{% for i = 1, 13 do %}
		<td><small>{{i}}</small></td>
		{% if i == 5 then %}
			<td></td>
		{% end %}
	{% end %}
	</tr>
	{% for i, record in ipairs(records) do %}
		<tr>
			<td>{{i}}</td>
			<td>{{Passport.DIRECTION}} </td>
			<td>{{Passport.TRACK_NUM}}</td>
			<td>{{record.KM}}</td>
			<td>{{record.PK}}</td>
			<td>{{record.M}}</td>
			<td>{{record.UCHASTOK}}</td>
			<td>{{record.THREAD}}</td>
			<td></td>
			<td>{{record.PLACEMENT}}</td>
			<td>{{record.DEFECT_CODE}}</td>
			<td>{{record.EXAM}}</td>
			<td></td>
			<td>{{record.ACTION}}</td>
			<td><img src="file://{{record.img_path}}"></td>
		</tr>
	{% end %}
	<table>
	<br/>
	ПС-{{Passport.FORMED}} &nbsp;&nbsp;&nbsp;&nbsp; {{Passport.SIGNED}}
</body>
</html>]]


	local folter = make_report_dir()
	local file_name = folter .. 'report.html'

	local filtred_records = {}
	for _, record in ipairs(records) do
		if is_record_included(record) then
			local img_path = string.format('%sultrasound_%s.png', folter, record.SYST)
			record.img_path = Driver:GetUltrasoundImage{note_rec=record, file_path=img_path, width=800, height=600}
			table.insert(filtred_records, record)
		end
	end

	local res = view{Passport=Passport, records=filtred_records, css_style=css_style}

	local dst_file = assert(io.open(file_name, 'w+'))
	dst_file:write(res)
	dst_file:close()

	os.execute("start " .. file_name)
end


local function excel_defectogram(records, params)
	return EnterScope(function (defer)
	local insert_us_img = true
	local insert_video_img = params.insert_video_img
	local dlg = luaiup_helper.ProgressDlg()
	defer(dlg.Destroy, dlg)

	records = filter_selected_mark(records, dlg)

	if #records == 0 then
		iup.Message('Info', "Выделенных отметок не найдено")
		return
	end

	local excel = excel_helper(Driver:GetAppPath() .. 'Telegrams\\Defectogram.xlsx', nil, false)

	excel:ApplyPassportValues(Passport)
	for line, dst_tbl in excel:EnumDstTable(#records) do
		local record = records[line]
		record.PATH = format_path_coord(record)
		record.STR_SVED = get_str_sved(record)
		excel:ReplaceTemplates(dst_tbl, {record})

		local hide_video_cell = true
		if insert_us_img and Driver.GetUltrasoundImage then
			local params = {
				note_rec=record,
				width=800,
				height=600,
				color=1,
				coord=record.MARK_COORD
			}
			local first_length = read_pref_cfg_param_num('DEFECTOGRAM_US_FIRST_LENGTH')
			if first_length and first_length > 1 then
				params.length =  first_length
			end

			local us_img_path = Driver:GetUltrasoundImage(params)
			if us_img_path and #us_img_path then
				excel:InsertImage(dst_tbl.Cells(11, 1), us_img_path)
			end
			-- https://bt.abisoft.spb.ru/view.php?id=727
			-- https://bt.abisoft.spb.ru/view.php?id=749
			local second_length = read_pref_cfg_param_num('DEFECTOGRAM_US_SECOND_LENGTH')
			if not insert_video_img and second_length and second_length > 1 then
				hide_video_cell = false
				params.length =  second_length
				local us_img_path = Driver:GetUltrasoundImage(params)
				if us_img_path and #us_img_path then
					excel:InsertImage(dst_tbl.Cells(12, 1), us_img_path)
				end
			end
		else
			dst_tbl.Cells(11, 1).RowHeight = 1
		end

		if insert_video_img and Driver.GetFrame then
			-- InsertVideoFrame(excel, dst_tbl.Cells(12, 1), record)
			insertVideoScreen(excel, dst_tbl.Cells(12, 1), record, 700)
			-- https://bt.abisoft.spb.ru/view.php?id=727
			local second_scale = read_pref_cfg_param_num('DEFECTOGRAM_VIDEO_SECOND_SCALE')
			if second_scale and second_scale > 10 then
				insertVideoScreen(excel, dst_tbl.Cells(13, 1), record, second_scale)
			end
		elseif hide_video_cell then
			dst_tbl.Cells(12, 1).RowHeight = 1
		end

		if not dlg:step(line / #records, string.format(' Process %d / %d mark', line, #records)) then
			break
		end
	end

	excel:SaveAndShow()
	end)
end

local function report_EKSUI(records)
	local resty = require "resty.template"
	local view = resty.compile[[
<?xml version="1.0" encoding="UTF-8"?>
<report>
	<passport>
	{% for name, value in pairs(Passport) do %}
		<PARAM name="{{name}}" value="{{value}}"/>
	{% end %}
	</passport>

	{% for i, record in ipairs(records) do %}
	<record>
	{% for name, value in pairs(record) do %}
		<PARAM name="{{name}}" value="{{value}}"/>
	{% end %}
		<base64>{*get_encoded_frame(record)*}</base64>
	</record>
	{% end %}
</report>]]

	local dlg = luaiup_helper.ProgressDlg()

	records = filter_selected_mark(records, dlg)

	if #records == 0 then
		iup.Message('Info', "Выделенных отметок не найдено")
		return
	end

	local mark_processed = 0
	local function get_encoded_frame(record)
		if not dlg:step(mark_processed / #records, string.format(' Process %d / %d mark', mark_processed, #records)) then
			error("Прервано пользователем")
		end
		mark_processed = mark_processed + 1
		return GetBase64EncodedFrame(record)
	end

	local res = view{Passport=Passport, records=records,get_encoded_frame=get_encoded_frame}

	local file_name = "c:\\1.xml"
	local dst_file = assert(io.open(file_name, 'w+'))
	dst_file:write(res)
	dst_file:close()

	os.execute("start " .. file_name)

end



local function AddCustomRecordProperties(record)
	record.PATH = format_path_coord(record)
	record.STR_SVED = get_str_sved(record)
end

local function GetRailImages(record)
	local rail = get_record_rail(record)
	local video_channels = {}

	if rail == 0 then
		video_channels = {
			{19, 1},
			{21, 1},
			{17, 1},}
	else
		video_channels = {
			{18, 3},
			{22, 1},
			{20, 3},}
	end

	local prms = {mode=3, panoram_width=700, width=500, height=800, rotate_fixed=0}

	local frames = {}
	local errors = {}

	for i, num_rot in ipairs(video_channels) do
		local num = num_rot[1]
		prms.rotate_fixed = num_rot[2]

		local ok, res = pcall(function()
			return Driver:GetFrame(num, record.MARK_COORD, prms)
		end)

		if ok and res and #res > 1 then
			table.insert(frames, res)
		else
			table.insert(errors, res)
			print(res)
		end
	end
	return frames, errors
end


local function report_videogram(records)
	local dlg = luaiup_helper.ProgressDlg()

	records = filter_selected_mark(records, dlg)

	if #records == 0 then
		dlg:Destroy()
		iup.Message('Info', "Выделенных отметок не найдено")
		return
	end
	local common_name = Passport.NAME .. os.date('%y%m%d-%H%M%S') .. '_'

	for line, record in ipairs(records) do
		local excel = excel_helper(Driver:GetAppPath() .. 'Telegrams\\Videogram.xlsm', nil, false, common_name .. record.INNER)
		local user_range = excel._worksheet.UsedRange

		excel:ApplyPassportValues(Passport)

		AddCustomRecordProperties(record)
		excel:ReplaceTemplates(user_range, {record})

		local cell_video = nil

		for n = 1, user_range.Cells.count do						-- пройдем по всем ячейкам
			local cell = user_range.Cells(n)
			local val = cell.Value2
			if val == '$VIDEO$' then
				cell_video = cell
				break
			end
		end

		if cell_video and Driver.GetFrame then
			local frames, errors = GetRailImages(record)
			if #frames > 1 then
				local width = cell_video.MergeArea.Width / #frames
				local shapes = cell_video.worksheet.Shapes

				for i, img_path in ipairs(frames) do
					local left = cell_video.Left + (i-1) * width

					local picture = shapes:AddPicture(img_path, false, true, left, cell_video.Top, width, cell_video.MergeArea.Height)
					picture.Placement = 1
				end
			end
		end

		if not dlg:step(line / #records, string.format(' Process %d / %d mark', line, #records)) then
			break
		end

		dlg:Destroy()
		excel:SaveAndShow()
	end
end

-- =================== Описание отчетов =====================

local REPORTS =
{
	{ name = 'Видеограмма Выделенных', fn = report_videogram, user_select_range=false },
	--{ name = 'Создать дамп отметок', fn = report_make_dump, user_select_range=true },
	--{ name = 'Свойства отметок', fn = report_html_properties, user_select_range=true },
	--{ name = 'Ведомость HTML с изображениями УЗ', fn = vedomost_with_US_images_html, user_select_range=true },
	{ name = 'Ведомость EXCEL с изображениями УЗ', fn = vedomost_with_US_images_excel, user_select_range=true },
	{ name = 'Дефектограмма', fn = excel_defectogram, user_select_range=false, insert_video_img=false },
	{ name = 'Дефектограмма с видео', fn = excel_defectogram, user_select_range=false, insert_video_img=true },
	-- { name = 'Выделенные в отчет ЕКСУИ', fn = report_EKSUI, user_select_range=false },
}

-- =================== EXPORT FUNCTION =====================

-- получить список названий доступных отчетов
function GetAvailableReports()
	local res = {}
	for n = 1, #REPORTS do
		res[n] = REPORTS[n].name
	end
	return res
end

function UserSelectRange(name)
	for _, n in ipairs(REPORTS) do
		if n.name == name then
			return n.user_select_range
		end
	end

	errorf('can not find report [%s] [%s]', name, REPORTS[2].name)
end

function MakeReport(name, records) -- exported
	for _, n in ipairs(REPORTS) do
		if n.name == name then
			if not n.fn then
				errorf('report function (%s) not defined', name)
			end
			name = nil
			n.fn(records, n)
		end
	end

	if name then -- if reporn not found
		errorf('can not find report [%s]', name)
	end
end

