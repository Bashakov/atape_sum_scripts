if not ATAPE then
	require "iuplua" 
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end


luaiup_helper = require 'luaiup_helper'
excel_helper = require 'excel_helper'
mark_helper = require 'sum_mark_helper'

local stuff = require 'stuff'
local sprintf = stuff.sprintf
local printf = stuff.printf

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

local function filter_included_mark(records, dlg)
	local res = mark_helper.filter_marks(records, is_record_included, make_filter_progress_fn(dlg))
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

-- =================== Отчеты =====================

-- отчет по отметкам записой книжки с выводом в excel
local function vedomost_with_US_images_excel(records)
	local insert_us_img = true
	local insert_video_img = true
	
	local dlg = luaiup_helper.ProgressDlg()
	
	records = filter_included_mark(records, dlg)

	if #records == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end

	local excel = excel_helper(Driver:GetAppPath() .. 'Telegrams\\VedomostTemplate.xls', nil, true)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#records, 1)
	
	if insert_us_img then
		data_range.Columns(18).ColumnWidth = 40.0
	end
	if insert_video_img then
		data_range.Columns(19).ColumnWidth = 40.0
	end

	assert(#records == data_range.Rows.count, 'misamtch count of mark and table rows')

	for line, record in ipairs(records) do
		local km, m, mm = Driver:GetPathCoord(record.MARK_COORD)
		
		local dst_row = data_range.Rows(line)
		excel:ReplaceTemplates(dst_row, {record,})
		
		if insert_us_img or insert_video_img then
			data_range.Rows(line).RowHeight = 100.0
		end
		
		if insert_us_img and Driver.GetUltrasoundImage then
			local us_img_path = Driver:GetUltrasoundImage{note_rec=record, width=800, height=600, color=1, coord=record.MARK_COORD}
			if us_img_path and #us_img_path then
				excel:InsertImage(data_range.Cells(line, 18), us_img_path)
				increase_height = true
			end
		end
		
		if insert_video_img and Driver.GetFrame then
			local rail = get_record_rail(record)
			local video_channel = rail==1 and 18 or 17
			local video_img_path = Driver:GetFrame( video_channel, record.MARK_COORD, {mode=3, panoram_width=700, width=400, height=300} )
			if video_img_path and #video_img_path then
				excel:InsertImage(data_range.Cells(line, 19), video_img_path)
				increase_height = true
				data_range.Cells(line, 20).Value2 = video_channel
			end
		end

--		local img_path = ShowVideo ~= 0 and Driver:GetFrame( ext.VIDEOIDENTCHANNEL, prop.SysCoord, {mode=3, panoram_width=1500, frame_count=3, width=400, height=300} )
--		local uri = make_mark_uri(prop.ID)
		
--		data_range.Cells(line, 1).Value2 = get_rail_name(mark)
--		data_range.Cells(line, 2).Value2 = km
--		excel:InsertLink(data_range.Cells(line, 3), uri, sprintf("%.02f", m + mm/1000))
--		data_range.Cells(line, 4).Value2 = prop.Description 
			
		if not dlg:step(line / #records, stuff.sprintf(' Process %d / %d mark', line, #records)) then 
			break
		end
	end 

--	if ShowVideo == 0 then 
--		excel:AutoFitDataRows()
--		data_range.Cells(5).ColumnWidth = 0
--	end
	excel:SaveAndShow()
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


	local folter = os.getenv('USERPROFILE') .. '\\ATapeReport\\' .. os.date('%y%m%d-%H%M%S') .. '\\'
	os.execute('mkdir ' .. folter)
	local file_name = folter .. 'report.html'
	
	local filtred_records = {}
	for _, record in ipairs(records) do
		if is_record_included(record) then
			local img_path = sprintf('%sultrasound_%s.png', folter, record.SYST)
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

local function report_make_dump(records)
	local filedlg = iup.filedlg{
		dialogtype = "dir", 
		title = "Select dir for dump mark", 
		directory = "c:\\out",
	} 
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)
	if filedlg.status == -1 then
		return
	end
	
	local out_dir = filedlg.value .. '\\' .. Passport.NAME
	os.execute('mkdir ' .. out_dir)

	local prev_output = io.output()
	io.output(out_dir .. "\\dump.lua")
	stuff.save("data", {records=records, Passport=Passport})
	io.output(prev_output)
end

-- =================== Описание отчетов =====================

local REPORTS = 
{
	{ name = 'Создать дамп отметок', fn = report_make_dump },
	{ name = 'Ведомость HTML с изображениями УЗ', fn = vedomost_with_US_images_html },
	{ name = 'Ведомость EXCEL с изображениями УЗ', fn = vedomost_with_US_images_excel },
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

function MakeReport(name, records) -- exported
	for _, n in ipairs(REPORTS) do 
		if n.name == name then
			if not n.fn then
				stuff.errorf('report function (%s) not defined', name)
			end
			name = nil
			n.fn(records)
		end
	end

	if name then -- if reporn not found
		stuff.errorf('can not find report [%s]', name)
	end
end

