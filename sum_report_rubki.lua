local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
local excel_helper = require 'excel_helper'
require "ExitScope"
local resty = require "resty.template"


if iup then
	iup.SetGlobal('UTF8MODE', 1)
end

local printf  = mark_helper.printf
local sprintf = mark_helper.sprintf
local table_find = mark_helper.table_find

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
	if not marks then return nil end

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

local function make_rail_image(mark1, mark2)
	local ok, img_data = pcall(function ()
			return mark_helper.MakeMarkImage(mark1, nil, {mark1.prop.SysCoord-500, mark2.prop.SysCoord+500}, true)
		end)
	return ok, img_data
end

local function get_marks(dlg)
	if dlg then
		dlg:Hide()
	end

	local ok, min_length = iup.GetParam("Рубки", nil, "Верхний порог длины рельса (м): %i\n", 30 )
	if dlg then dlg.Show(dlg) end
	if not ok then
		return
	end

	local marks = Driver:GetMarks()

	marks = mark_helper.filter_marks(marks,
		function (mark) -- filter
			return table_find(joints_guids, mark.prop.Guid) and mark.ext.RAWXMLDATA
		end,
		function (all, checked, accepted) -- progress
			if checked % 50 == 0 and dlg then
				dlg:step(checked / all, string.format('Сканирование %d / %d отметок, выбрано %d', checked, all, accepted))
			end
		end
	)
	marks = mark_helper.sort_mark_by_coord(marks)
	return marks, min_length
end

local function dormate_date()
	local psp_date = Passport.DATE --2017:06:08:12:44
	psp_date = string.gsub(psp_date, ":", "")
	psp_date = string.sub(psp_date, 1, 8) .. "_" .. string.sub(psp_date, 9) .. "00"
	return psp_date
end

local function save_msxml_node(node)
	local oWriter = luacom.CreateObject("Msxml2.MXXMLWriter")
	local oReader =  luacom.CreateObject("Msxml2.SAXXMLReader")
	assert(oWriter)
	assert(oReader)

	oWriter.standalone = 0
    oWriter.omitXMLDeclaration = 1
    oWriter.indent = 1
	oWriter.encoding = 'utf-8'

	oReader:setContentHandler(oWriter)
	oReader:putProperty("http://xml.org/sax/properties/lexical-handler", oWriter)
	oReader:putProperty("http://xml.org/sax/properties/declaration-handler", oWriter)

	local unk1 = luacom.GetIUnknown(node)
    oReader:parse(unk1)

	local res = oWriter.output
	return res
end



local function save_res_xml(dst_dir, node)
	local fromKM = Passport.FromKm or string.match(Passport.START_CHOORD, '^(-?%d+):') or ''
	local toKM = Passport.ToKm or string.match(Passport.END_CHOORD, '^(-?%d+):') or ''
	local path_dst = sprintf("%s\\%s_%s_%s.xml", dst_dir, Passport.SOURCE, fromKM, toKM)
	if true then
		-- with formation
		local f = io.open(path_dst, 'w+b')
		f:write(save_msxml_node(node.ownerDocument))
		f:close()
	elseif true then
		-- no format (one line)
		node.ownerDocument:save(path_dst)
	else
		local f = io.open(path_dst, 'w+b')
		f:write('<?xml version="1.0" >')
		f:write(node.xml)
		f:close()
	end
	return path_dst
end

local function add_text_node(parent, name, text)
	local node = parent.ownerDocument:createElement(name)
	parent:appendChild(node)
	node.text = text or ''
	return node
end

local function add_node(parent, name, attrib)
	local dom = parent.ownerDocument or parent
	local node = dom:createElement(name)
	parent:appendChild(node)
	for n, v in pairs(attrib or {}) do
		node:setAttribute(n, v)
	end
	return node
end

local function get_left(mark)
	local pos = mark_helper.GetMarkRailPos(mark) -- возвращает: -1 = левый, 0 = оба, 1 = правый
	-- return pos < 0 and 1 or 0
   	return pos > 0 and 1 or 0  -- 0 левая 1 правая требование окт 2020 
end


local function make_gap_description(mark)
	local km, m, mm = Driver:GetPathCoord(mark.prop.SysCoord)
	local bolts_cnt, bolts_fault = mark_helper.GetCrewJointCount(mark)
	local gap_step = mark_helper.GetRailGapStep(mark)

	local values = {}
	values.gaptype = mark_helper.GetGapType(mark)
	values.nakltype = (bolts_cnt == 6 and 1) or (bolts_cnt == 4 and 2) -- Тип накладки (1 – шестидырная, 2 – четырехдырная накладка)
	values.temp = mark_helper.GetTemperature(mark)
	values.left = get_left(mark)
	values.km = km
	values.m = string.format('%.3f', m + mm/1000)
	values.zazor = mark_helper.GetGapWidth(mark)
	values.gstup = gap_step and math.abs(gap_step)
	values.nakl = mark_helper.GetFishplateState(mark) > 0 and 1 or 0
	values.bolt = bolts_fault == 0 and 0 or 1

	local img_ok, img_data = pcall(function ()	
		return mark_helper.MakeMarkImage(mark, nil, nil, true)
	end)

	return {
		values = values,
		img_data = img_ok and img_data or '',
		img_error = not img_ok and img_data
	}
end


-- ======================= отчеты =========================

-- отчет по коротким стыкам
local function report_short_rails(params)
	EnterScope(function(defer)
		local dlg = luaiup_helper.ProgressDlg()
		defer(dlg.Destroy, dlg)

		local marks, min_length = get_marks(dlg)
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

			if not dlg:step(line / #short_rails, sprintf('Сохранение %d / %d', line, #short_rails)) then
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



local function report_short_rails_ekasui()
	EnterScope(function(defer)
		if not EKASUI_PARAMS then 
			iup.Message("Генерация отчета", "Конфигурация ЕКАСУИ не обнаружена")
			return
		end

		local ok, road, vagon, proezd, proverka, assetnum =
			iup.GetParam("Параметры проезда", nil,
				"идентификатор дороги (ID БД ЕК АСУИ): %s\n\z
				идентификатор средства диагностики (ID БД ЕК АСУИ): %s\n\z
				дата (ГГГГММДД_ЧЧММСС): %s\n\z
				вид проверки: %o|рабочая|контрольная|дополнительная|\n\z
				ID пути БД ЕК АСУИ: %s\n\z
			", 	Passport.DIR_CODE, "", dormate_date(), 0, Passport.TRACK_CODE
		)
		if not ok then return end

		local dlg = luaiup_helper.ProgressDlg('Отчет ЕКАСУИ')
		defer(dlg.Destroy, dlg)

		local marks, min_length = get_marks(dlg)
		local short_rails = scan_for_short_rail(marks, min_length*1000)
		if #short_rails == 0 then
			iup.Message('Info', "Подходящих отметок не найдено")
			return
		end

		local dom = luacom.CreateObject('Msxml2.DOMDocument.6.0')
		assert(dom)

		local node_videocontrol = add_node(dom, 'videocontrol')
		local node_proezd = add_node(node_videocontrol, 'proezd', {road=road, vagon=vagon, proezd=proezd, proverka=proverka})
		local node_way = add_node(node_proezd, 'way', {assetnum=assetnum})
		local node_relset = add_node(node_way, 'relset')

		for i, mark_pair in ipairs(short_rails) do
			local mark1, mark2 = table.unpack(mark_pair)
			local km1, m1, mm1 = Driver:GetPathCoord(mark1.prop.SysCoord)
			local km2, m2, mm2 = Driver:GetPathCoord(mark2.prop.SysCoord)

			local node_rels = add_node(node_relset, 'rels', {relsid=i})
			add_text_node(node_rels, 'bgapid', mark1.prop.ID)
			add_text_node(node_rels, 'egapid', mark2.prop.ID)
			add_text_node(node_rels, 'left', get_left(mark1))
			add_text_node(node_rels, 'bkm', km1)
			add_text_node(node_rels, 'bm', string.format('%.3f', m1 + mm1/1000))
			add_text_node(node_rels, 'ekm', km2)
			add_text_node(node_rels, 'em', string.format('%.3f', m2 + mm2/1000))

			add_text_node(node_rels, 'length', string.format('%.3f', (mark2.prop.SysCoord - mark1.prop.SysCoord)/1000))

			local node_marking = add_node(node_rels, 'marking')
			add_text_node(node_marking, 'mark', '')

			local ok, img_data = make_rail_image(mark1, mark2)
			add_text_node(node_marking, 'pic', ok and img_data or '')
			if not ok then
				add_text_node(node_marking, 'error', img_data)
			end

			if not dlg:step(i / #short_rails, sprintf('Сохранение рельсов %d / %d', i, #short_rails)) then
				return
			end
		end

		local node_railgapset = add_node(node_way, 'railgapset')

		local gap_param_order = {
			"gaptype", "nakltype", "temp", "left", "speedlimit", "km", "m", "pros", "zazor",
			"vstup", "gstup", "smatie", "nakl", "bolt", "viplesk", "skrepl", "podkl", "shpal",
			"epur", "ballast", "sneg"}

		for i, mark in ipairs(marks) do
			local gap_params = make_gap_description(mark)

			local node_railgap = add_node(node_railgapset, 'railgap', {gapid=mark.prop.ID})
			for _, param_name in ipairs(gap_param_order) do
				add_text_node(node_railgap, param_name, gap_params.values[param_name] or -1)
			end

			local node_picset = add_node(node_railgap, 'picset')
			add_text_node(node_picset, 'pic', gap_params.img_data)
			if gap_params.img_error then
				add_text_node(node_picset, 'error', gap_params.img_error)
			end

			if not dlg:step(i / #marks, sprintf('Сохранение стыков %d / %d', i, #marks)) then
				return
			end
		end

		local dst_dir = EKASUI_PARAMS.ExportFolder
		local path_dst = save_res_xml(dst_dir, node_videocontrol)
		local anwser = iup.Alarm("ATape", sprintf("Сохранен файл: %s", path_dst), "Показать", "Конвертировать в HTML", "Закрыть")
		if 1 == anwser then
			os.execute(path_dst)
		end
        if 2 == anwser then
			os.execute(sprintf("%s//make_short_rail_html.js %s", dst_dir, path_dst))
		end
	end)
end

local function MakeEkasuiGapReport(mark)
	local template = resty.compile([[
<!DOCTYPE html>
<html>
    <head>
        <META http-equiv="Content-Type" content="text/html">
        <meta charset="utf-8">
        <title>Ведомость оценки стыка</title>
        <style type="text/css">
body {
    font-family: "Times New Roman", "Tahoma", Sans-Serif;
    font-size: 15px; 
	width: 500px;
	margin: 20px;
}
.header {
    background-color: blue;
    color: white;
    text-align: center;
    font-weight: 800;
    font-size: 130%;
}
table {
    border-collapse: collapse;
    /* text-align: left; */
    empty-cells: show;
    width: 100%;
}
td {
    border: 1px solid #000;
}
.gap_technical td:nth-child(2) {
    text-align: right;
}
.gap_properties td:nth-child(2) {
    text-align: center;
}
img {
    display: block;
    margin: auto;
}
        </style>
    </head>

    <body>
        <div class="header">
            Ведомость оценки стыка {{gap.km}} км {{gap.m}} м
        </div>
        <br/>
		<b>{{os.date("%d.%m.%Y %H:%M:%S")}}</b>
		<br/>
        Тестовый перегон
        <br/>
        <img src='data:image/jpg;base64,{{image_base64}}'>
        <br/>
        <table class='gap_technical'>
            <tr>
                <td colspan="2">Техническая характеристика стыка</td>
            </tr>
            <tr>
                <td>Тип стыка</td>
                <td>{{gap.gaptype == 0 and 'болтовой' or gap.gaptype == 1 and 'изолированный' or gap.gaptype == 2 and 'сварной' or gap.gaptype}}</td>
            </tr>
            <tr>
                <td>Тип накладки</td>
                <td>{{gap.nakltype == 1 and 'шестидырная' or gap.nakltype == 2 and 'четырехдырная накладка' or gap.nakltype}}</td>
            </tr>
            <tr>
                <td>Тип скрепления</td>
                <td></td>
            </tr>
            <tr>
                <td>Тип шпал</td>
                <td></td>
            </tr>
        </table>
        <br/>
        <table class='gap_properties'>
            <tr>
                <td>Наименование</td>
                <td>Величина параметра</td>
            </tr>
            <tr>
                <td>Просадки в зоне стыка</td>
                <td></td>
            </tr>
            <tr>
                <td>Величина стыкового зазора</td>
                <td>{{gap.zazor}}</td>
            </tr>
            <tr>
                <td>Вертикальный уступ</td>
                <td></td>
            </tr>
            <tr>
                <td>Горизонтальный уступ</td>
                <td>{{gap.gstup}}</td>
            </tr>
            <tr>
                <td>Смятие головки рельсы в зоне стыка (дефект)</td>
                <td></td>
            </tr>
            <tr>
                <td>Дефекты рельсовой накладки <i>(надрыв трещина излом)</i></td>
                <td></td>
            </tr>
            <tr>
                <td>Отсутствие стыковых болтов</td>
                <td>{{gap.bolt}}</td>
            </tr>
            <tr>
                <td>Выплеск балласта</td>
                <td></td>
            </tr>
            <tr>
                <td>Отсутствующие или негодные скрепления</td>
                <td></td>
            </tr>
            <tr>
                <td>Отсутствующие или негодные накладки <i>(выход подошвы рельса из реборд накладок)</i></td>
                <td>{{gap.nakl}}</td>
            </tr>
            <tr>
                <td>Наличие негодных шпал в зоне стыка</td>
                <td></td>
            </tr>
            <tr>
                <td>Отклонение от эпюрных значений укладки деревянных или железобетонных шпал <i>(брусьев)</i></td>
                <td></td>
            </tr>
            <tr>
                <td>Недостаточное, избыточное количество балласта в шпальных ящиках</td>
                <td></td>
            </tr>
            <tr>
                <td>Не вскрытый стык от снега <i>(в зимний период)</i></td>
                <td></td>
            </tr>
            <tr>
                <td>Величина комплексного показателя <b>Кк</b></td>
                <td></td>
            </tr>
        </table>
    </body>
</html>
	]])
	ShowVideo = 1 -- global
	local gap_params = make_gap_description(mark)
	local html = template({image_base64=gap_params.img_data, gap=gap_params.values, Passport=Passport})
	local file_path = string.format("%s\\gap_report_%s.%d.%s.html", os.getenv('tmp'), Passport.SOURCE, mark.prop.SysCoord, os.date('%y%m%d-%H%M%S'))
	local file = assert(io.open(file_path, 'w+b'))
	file:write(html)
	file:close()
	os.execute(file_path)
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
	{
		name = "Короткие рубки|ЕКАСУИ",
		fn = report_short_rails_ekasui,
		guids = joints_guids,
	},
}

-- тестирование
if not ATAPE then

	local test_report = require('test_report')
	test_report('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')

	-- отчет ЕКАСУИ
	if 1 == 1 then
		local r = cur_reports[2]
		r.fn(r.params)
	end

	-- ведомость стыка
	if 1 == 0 then
		local mark = Driver:GetMarks({mark_id=100})[1]
		MakeEkasuiGapReport(mark)
	end
end

return
{
	AppendReports = function (reports)
		for _, report in ipairs(cur_reports) do
			table.insert(reports, report)
		end
	end,
	MakeEkasuiGapReport = MakeEkasuiGapReport,
}