
if not ATAPE then
	require "iuplua" 
end

if not ATAPE then
	HUN = false
end

local sumPOV = require "sumPOV"
local resty = require "resty.template"

if iup then
 	iup.SetGlobal('UTF8MODE', 1)
end

require 'ExitScope'
mark_helper = require 'sum_mark_helper'
luaiup_helper = require 'luaiup_helper'
excel_helper = require 'excel_helper'
local TYPES = require 'sum_types'

local table_find = mark_helper.table_find
local sprintf = mark_helper.sprintf
local printf = mark_helper.printf
local errorf = mark_helper.errorf

get_rail_name = mark_helper.GetRailName -- non local for html template work https://bt.abisoft.spb.ru/view.php?id=935#c4802
make_mark_uri = mark_helper.MakeMarkUri

if not ShowVideo then
	ShowVideo = 1
end

local SelectNodes = mark_helper.SelectNodes


local gap_rep_filter_guids = 
{
	TYPES.VID_INDT_1,
	TYPES.VID_INDT_2,
	TYPES.VID_INDT_3,
	TYPES.VID_INDT_ATS,
	TYPES.VID_ISO, 	-- ИзоСтык(Видео)
}

local fastener_guids = {
	TYPES.FASTENER
}

local beacon_rep_filter_guids = 
{
	"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}",
	"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",
}

local surface_defects_guids = 
{
	TYPES.VID_SURF,
}


local REPORT_GAPS_IDs =
{
	"000001",--Код
	"vZazorov",--Имя
	"Ведомость стыковых зазоров",--Описание
}

local REPORT_BOLTS_IDs =
{
	"000002",--Код
	"vBoltov",--Имя
	"Ведомость болтовых стыков",--Описание
}

-- ========================================================= 

-- фильтрация и сортировка отметок
local function FilterSort(marks, fnFilter, fnCmpKey, cbProgress)
	cbProgress = cbProgress or function() end

	if fnFilter then
		local tmp = {}
		for i = 1, #marks do
			local mark = marks[i]
			if fnFilter(mark) then
				table.insert(tmp, mark)
				cbProgress(i / #marks, string.format(' filter %d / %d mark', i, #marks) )
			end
		end
		marks = tmp
	end

	if fnCmpKey then
		local keys = {}

		for i = 1, #marks do
			local key = fnCmpKey(marks[i])
			key[#key+1] = i
			table.insert(keys, key)
		end
		assert(#keys == #marks)

		table.sort(keys, function(t1, t2)
				for i = 1, #t1 do
					local a,b = t1[i], t2[i]
					if a < b then return true end
					if b < a then return false end
				end
				return false
			end)

		local tmp = {}
		for i = 1, #keys do
			local key = keys[i]
			tmp[i] = marks[key[#key]]
			cbProgress(i / #keys, string.format(' sort %d / %d mark', i, #keys) )
		end

		assert(#tmp == #marks)
		marks = tmp
	end

	return marks
end

local function make_filter_progress_fn(dlg)
	return function(all, checked, accepted)
		if checked % 20 == 0 then
			dlg:step(checked / all, string.format('Check %d / %d mark, accept %d', checked, all, accepted))
		end
	end
end

-- вернуть ключь сортировки по системной координате
local function get_sys_coord_key(mark)
	return {mark.prop.SysCoord} 
end

-- отсортировать отметки по системной координате
local function sort_mark_by_coord(marks)
	return mark_helper.sort_marks(marks, get_sys_coord_key, true)
end

-- разбивает отметки на пары, marks должен быть отсортирован по сиситемной координате
local function BuildMarkPairs(marks, dist)
	local res = {}
	local prev_mark

	for i = 1, #marks do
		local mark = marks[i]
		--print(mark)
		if prev_mark and mark.prop.SysCoord - prev_mark.prop.SysCoord <= dist then
			res[#res+1] = {prev_mark, mark}
			prev_mark = nil
		else
			if prev_mark then
				res[#res+1] = {prev_mark}
			end
			prev_mark = mark
		end
	end

	if prev_mark then
		res[#res+1] = {prev_mark}
	end

	for i = 1, #res do
		local out = {}
		for _, m in pairs(res[i]) do
			out[bit32.band(m.prop.RailMask, 3)] = m
		end
		res[i] = out
	end
	return res
end

-- получить доустимую ширину зазора в зав от температуры
local function get_nominal_gape_width(rail_len, temperature)
	if rail_len > 17000 then
		-- рельс 25 метров
		if temperature > 30  then return 0   	end
		if temperature > 25  then return 1.5 	end	
		if temperature > 20  then return 3.0 	end
		if temperature > 15  then return 4.5 	end
		if temperature > 10  then return 6.0 	end
		if temperature > 5   then return 7.5 	end
		if temperature > 0   then return 9.0 	end
		if temperature > -5  then return 10.5 	end
		if temperature > -10 then return 12.0 	end
		if temperature > -15 then return 13.5 	end
		if temperature > -20 then return 15.0 	end
		if temperature > -25 then return 16.5 	end
		if temperature > -30 then return 18.0 	end
		if temperature > -35 then return 19.5 	end
		if temperature > -40 then return 21.0 	end
		return   22.0 	
	else 
		-- рельс 12 метров
		if temperature > 55  then return 0 	 	end	
		if temperature > 45  then return 1.5 	end
		if temperature > 35  then return 3.0 	end
		if temperature > 25  then return 4.5 	end
		if temperature > 15  then return 6.0 	end
		if temperature > 5 	 then return 7.5 	end
		if temperature > -5  then return 9.0 	end
		if temperature > -15 then return 10.5 	end
		if temperature > -25 then return 12.0 	end
		if temperature > -35 then return 13.5 	end
		if temperature > -45 then return 15.0 	end
		if temperature > -55 then return 16.5 	end
		return 18 	 
	end
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

-- сгенерировать видео изображение отметки закодированное в base64
local function make_video_frame_base64(mark)
	local image_data
	local ok, msg = pcall(function ()
			image_data = mark_helper.MakeMarkImage(mark, nil, nil, true)
		end)
	if not ok then
		image_data = msg and #msg and msg or 'Error'
	end
	return image_data
end

-- шаблон xml с выводом в одну колонку
local eksui_template_column = resty.compile([[
<?xml version="1.0" encoding="UTF-8"?>
<report name="{{report_name}}" date="{{os.date('%Y-%m-%d')}}" time="{{os.date('%H:%M:%S')}}"
	{% for name, value in pairs(os.date('*t')) do %}
		{{name}}="{{value}}"
	{% end %}
	>
	<passport>
	{% for name, value in pairs(Passport) do %}
		<PARAM name="{{name}}" value="{{value}}" {% if Driver.GetPassportParamDescription and #Driver:GetPassportParamDescription(name) ~= 0 then %} description="{{ Driver:GetPassportParamDescription(name) }}" {% end %}/>
	{% end %}
	</passport>
	
	{% for i, mark in ipairs(marks) do %}
	<mark>
	{% for _, param in ipairs(mark) do %}
		<PARAM name="{{param.name}}" value="{{param.value}}" {%if param.desc then %} description="{{param.desc}}" {% end %}/>
	{% end %}
	{% if ShowVideo ~= 0 then %}
		<base64>{* get_encoded_frame(mark.mark) *}</base64>
	{% end %}
	</mark>
	{% end %}
</report>]])

-- шаблон xml с выводом по строкам
local eksui_template_rows = resty.compile([[
<?xml version="1.0" encoding="UTF-8"?>
<report code="{{report_code}}" name="{{report_name}}" desc="{{report_desc}}" report_filter="{{report_filter}}" date="{{os.date('%Y-%m-%d')}}" time="{{os.date('%H:%M:%S')}}"
	{% for name, value in pairs(os.date('*t')) do %}
		{{name}}="{{value}}"
	{% end %}
	>
	<passport>
	{% for name, value in pairs(Passport) do %}
		<PARAM name="{{name}}" value="{{value}}" {% if Driver.GetPassportParamDescription and #Driver:GetPassportParamDescription(name) ~= 0 then %} description="{{ Driver:GetPassportParamDescription(name) }}" {% end %}/>
	{% end %}
	</passport>
	
	{% for line, row in ipairs(rows) do %}
	<row num="{{line}}">
		{% for r = 1, 2 do %}
		{% local mark = row[r] %}
		{% if mark then %}
		<mark rail="{{r}}" thread="{{get_rail_name(r)}}">
		{% for _, param in ipairs(mark) do %}
			<PARAM name="{{param.name}}" value="{{param.value}}" {%if param.desc then %} description="{{param.desc}}" {% end %}/>
		{% end %}
		{% if ShowVideo ~= 0 then %}
			<base64>{* get_encoded_frame(mark.mark) *}</base64>
		{% end %}
		</mark>
		{% end %}
		{% end %}
		{% if row.ext then %}
		{% for _, param in ipairs(row.ext) do %}
		<EXT name="{{param.name}}" value="{{param.value}}" {%if param.desc then %} description="{{param.desc}}" {% end %}/>
		{% end %}
		{% end %}
	</row>
	{% end %}
</report>]])

-- счетчик прогресса выполнения, на каждый вызов увеличиваем значение на 1
local function ProgressCounter(dlg, desc, all_count)
	local i = 0
	return function()
		i = i + 1
		if not dlg:step(i / all_count, sprintf('%s: %d / %d', desc, i, all_count)) then 
			error("Прервано пользователем") 
		end
		return i
	end
end

-- по списку отметок создает таблицу id отметки -> длинна рельса перед ней
local function make_rail_len_table(marks)
	local prev_rail_end = {}
	local mark_rail_len = {}
	
	for _, mark in ipairs(marks) do
		local prop = mark.prop
		local prev_coord = prev_rail_end[prop.RailMask]
		if prev_coord then
			mark_rail_len[prop.ID] = prop.SysCoord - prev_coord
		end
		prev_rail_end[prop.RailMask] = prop.SysCoord
	end
	return mark_rail_len
end

-- =================================================================================



-- Ведомость болтовых стыков 
local function report_crew_join(params)
	local right_rail_mask = tonumber(Passport.FIRST_LEFT) + 1

	local res, filter_mode, show_accepted, show_rejected = iup.GetParam("Параметры отчета", nil, 
		"Тип отчета: %l|Показать все|Дефектные|Нормальные|\n\z
		Показать подтвержденные: %b[Нет,Да]\n\z
		Показать Отброшенные: %b[Нет,Да]\n",
		1, 1, 0)
	
	if not res then
		return
	end
	filter_mode = filter_mode + 1
	
	local function filter_fn(mark)
		local accept = table_find(gap_rep_filter_guids, mark.prop.Guid) and mark.ext.RAWXMLDATA
		
		if accept then
			local ua = mark.ext.ACCEPT_USER or -1
			if ua == 1 then
				accept = show_accepted == 1
			elseif ua == 0 then
				accept = show_rejected == 1
			else
				--accept = false
			end
			-- print(ua, accept)
		end
		
		if accept and filter_mode ~= 1 then  -- если отметка еще подходит и нужно выбрать не все (только тефектные или только нормальные)
			local valid_on_half = mark_helper.CalcValidCrewJointOnHalf(mark)
			accept = valid_on_half and valid_on_half >= 2  		-- нормальные те, у которых как минимум 2 болта
			if filter_mode == 2 then accept = not accept end	-- если нужны ненормальные, инвертируем
		end
		return accept
	end
	
	local dlg = luaiup_helper.ProgressDlg()
	local marks = Driver:GetMarks()
	
	marks = mark_helper.filter_marks(marks, filter_fn, make_filter_progress_fn(dlg))
	marks = sort_mark_by_coord(marks)
	print('accept mark count = ', #marks)
	
	local mark_pairs = BuildMarkPairs(marks, 500)
	if params.filename then
		local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
		excel:ApplyPassportValues(Passport)
		local data_range = excel:CloneTemplateRow(#mark_pairs) -- data_range - область, куда вставлять отметки

		assert(#mark_pairs == 0 or #mark_pairs == data_range.Rows.count, 'mismatch count of mark_pairs and table rows')

		local function insert_mark(line, rail, mark)
			local column_offset = (rail == right_rail_mask) and 5 or 0
			local prop = mark.prop
			
			local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
			local count, defect = mark_helper.GetCrewJointCount(mark)
			
			local uri = make_mark_uri(prop.ID)

			excel:InsertLink(data_range.Cells(line, 1 + column_offset), uri, km)
			data_range.Cells(line, 2 + column_offset).Value2 = sprintf("%.02f", m + mm/1000)
			data_range.Cells(line, 3 + column_offset).Value2 = count
			data_range.Cells(line, 4 + column_offset).Value2 = defect

			insert_frame(excel, data_range, mark, line, 5 + column_offset)

			--data_range.Cells(line, 12+rail).Value2 = prop.SysCoord
		end

		for line, mark_pair in ipairs(mark_pairs) do
			for r, mark in pairs(mark_pair) do
				insert_mark(line, r, mark)
			end
			
			if not dlg:step(line / #mark_pairs, sprintf(' Process %d / %d line', line, #mark_pairs)) then 
				break
			end
		end 

		if data_range and ShowVideo == 0 then  -- спрячем столбцы с видео
			excel:AutoFitDataRows()
			data_range.Cells(nil, 5).ColumnWidth = 1
			data_range.Cells(nil, 10).ColumnWidth = 1
		end
		excel:SaveAndShow()
	
	elseif params.eksui then
		local frame_counter = ProgressCounter	(dlg, "Generate Frame", #marks)
		local mark_counter = ProgressCounter	(dlg, "Generate Mark", #marks)
		
		local function get_encoded_frame(mark)
			frame_counter()
			return make_video_frame_base64(mark)
		end
		
		local rows = {}
		for line, mark_pair in ipairs(mark_pairs) do
			local row = {}
			rows[line] = row
			for r, mark in pairs(mark_pair) do
				local prop = mark.prop
				local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
				local count, defect = mark_helper.GetCrewJointCount(mark)
				
				local res = {
					{name='ID', value=prop.ID, desc='Mark ID'},
					{name='KM', value=km},
					{name='M', value=sprintf("%.02f", m + mm/1000)},
					{name='rail', value=r, desc='Номер рельса'},
					{name='thread', value=get_rail_name(mark), desc='Название рельса'},
					{name='all_joint',value=count, desc='Тип накладки  (число отверстий)'},
					{name='defect_joint', value=defect, desc='Количество отсутствующих болтов'},
				}
				
				local other = mark_pair[bit32.bxor(r, 0x03)]
				if other then
					res[#res+1] = {name='pair_mark_id', value=other.prop.ID, desc='отметка на другом рельсе'}
				end
				res.mark = mark

				row[r] = res
				
				mark_counter()
			end
		end
		
		local filters_names = {"Показать все", "Дефектные", "Нормальные"}
		local res = eksui_template_rows{rows=rows, get_encoded_frame=get_encoded_frame, report_code=REPORT_BOLTS_IDs[1], report_name=REPORT_BOLTS_IDs[2],report_desc=REPORT_BOLTS_IDs[3], report_filter=filters_names[filter_mode]}

		local file_name = sprintf("c:\\%s.xml", REPORT_BOLTS_IDs[2]) 		
		local dst_file = assert(io.open(file_name, 'w+'))
		dst_file:write(res)
		dst_file:close()
		
		if not DONT_OPEN_RESULT then
			os.execute("start " .. file_name)
		end
	else
		errorf('для отчета должен быть задан файл шаблона или флаг отчета ЕКСУИ')
	end
end

-- отчет Ведомость Зазоров
local function report_gaps(params)
	local pov_fltr = sumPOV.MakeReportFilter(params.eksui)
	if not pov_fltr then return end
	
	local right_rail_mask = tonumber(Passport.FIRST_LEFT) + 1
	
	local res, filter_mode, show_accepted, show_rejected = iup.GetParam("Параметры отчета", nil, 
		"Тип отчета: %l|Меньше 3 мм|Все|Больше 22 мм|Слепые подряд|Больше 35 мм|\n\z
		Показать подтвержденные: %b[Нет,Да]\n\z
		Показать Отброшенные: %b[Нет,Да]\n",
		1, 1, 0)
	
	if not res then
		return
	end

	filter_mode = filter_mode + 1
	local ua_filter = {[-1] = true, [0] = show_rejected==1, [1] = show_accepted==1}
	
	local dlg = luaiup_helper.ProgressDlg()
	local marks = Driver:GetMarks({guids=params.guids})
	
	local function filter_type_fn(mark)
		return table_find(gap_rep_filter_guids, mark.prop.Guid) and mark.ext.RAWXMLDATA and pov_fltr(mark)
	end
	
	marks = mark_helper.filter_marks(marks, filter_type_fn, make_filter_progress_fn(dlg))
	marks = sort_mark_by_coord(marks)
	
	local mark_rail_len = make_rail_len_table(marks)
	
	marks = mark_helper.filter_user_accept(marks, ua_filter, make_filter_progress_fn(dlg))

	if filter_mode == 1 or filter_mode == 3 or filter_mode == 5 then
		local function filter_width_fn(mark)
			local width = mark_helper.GetGapWidth(mark)
			return width and ((filter_mode == 1 and width <= 3) or (filter_mode == 3 and width >= 22) or (filter_mode == 5 and width >= 35))
		end
		marks = mark_helper.filter_marks(marks, filter_width_fn, make_filter_progress_fn(dlg))

	elseif filter_mode == 4 then -- слепые подряд
		local mark_ids = {}
		local prev_gap_width = {}
		
		for i, mark in ipairs(marks) do
			local width = mark_helper.GetGapWidth(mark) or 100000
			local prev = prev_gap_width[mark.prop.RailMask] 
			if prev and prev.width <= 3 and width <= 3 then
				mark_ids[prev.ID] = true
				mark_ids[mark.prop.ID] = true
			end
			prev_gap_width[mark.prop.RailMask] = {ID = mark.prop.ID, width = width}
			dlg:step(i / #marks, string.format('scan for blind joint %d / %d mark', i, #marks))
		end
		
		marks = mark_helper.filter_marks(marks, function(mark) return mark_ids[mark.prop.ID] end, make_filter_progress_fn(dlg))
	end

	local mark_pairs = BuildMarkPairs(marks, 500)
	if params.filename then
		local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
		excel:ApplyPassportValues(Passport)
		local data_range = excel:CloneTemplateRow(#mark_pairs)

		assert(#mark_pairs == 0 or #mark_pairs == data_range.Rows.count, 'misamtch count of mark_pairs and table rows') -- https://bt.abisoft.spb.ru/view.php?id=935#c4801
		
		
		local function insert_mark(line, rail, mark)
			local column_offset = (rail == right_rail_mask) and 9 or 0
			local prop = mark.prop
			local ext = mark.ext
			
			local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
			local temperature = Driver:GetTemperature(bit32.band(prop.RailMask, 3)-1, prop.SysCoord)

			
			local uri = make_mark_uri(prop.ID)
			
			temperature = temperature and temperature.target

			data_range.Cells(line, 1 + column_offset).Value2 = km
			excel:InsertLink(data_range.Cells(line, 2 + column_offset), uri, sprintf("%.02f", m + mm/1000))
			data_range.Cells(line, 3 + column_offset).Value2 = temperature 
			
			local rail_len = mark_rail_len[prop.ID]
			local norm_gap_width
			if rail_len then
				data_range.Cells(line, 7 + column_offset).Value2 = sprintf("%.02f", rail_len/1000)
				if temperature then
					norm_gap_width = get_nominal_gape_width(rail_len, temperature)
					data_range.Cells(line, 5 + column_offset).Value2 = norm_gap_width
				end
			end

		
			local width, video_channel = mark_helper.GetGapWidth(mark)
			insert_frame(excel, data_range, mark, line, 8 + column_offset, video_channel)
			
			if width then
				data_range.Cells(line, 4 + column_offset).Value2 = width
				if norm_gap_width then
					data_range.Cells(line, 6 + column_offset).Value2 = sprintf('%.1f', width - norm_gap_width)
				end
			end
			
	--		data_range.Cells(line, 12+rail).Value2 = prop.SysCoord
			
		end

		for line, mark_pair in ipairs(mark_pairs) do
			for r, mark in pairs(mark_pair) do
				insert_mark(line, r, mark)
			end
			
			if mark_pair[1] and mark_pair[2] then
				local c1, c2 = mark_pair[1].prop.SysCoord, mark_pair[2].prop.SysCoord
				data_range.Cells(line, 9).Value2 = sprintf('%.02f', (c2 - c1) / 1000)
			end
		
			if not dlg:step(line / #mark_pairs, sprintf(' Process %d / %d line', line, #mark_pairs)) then 
				break
			end
		end 
		
		if data_range and ShowVideo == 0 then 
			excel:AutoFitDataRows()
			data_range.Cells(nil, 8).ColumnWidth = 0
			data_range.Cells(nil, 17).ColumnWidth = 0
		end
		excel:SaveAndShow()
	elseif params.eksui then
		local frame_counter = ProgressCounter	(dlg, "Generate Frame", #marks)
		local mark_counter = ProgressCounter	(dlg, "Generate Mark", #marks)
		
		local function get_encoded_frame(mark)
			frame_counter()
			return make_video_frame_base64(mark)
		end
		
		local rows = {}
		for line, mark_pair in ipairs(mark_pairs) do
			local row = {}
			rows[line] = row
			for r, mark in pairs(mark_pair) do
				local prop = mark.prop
				local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
				local temperature = Driver:GetTemperature(bit32.band(prop.RailMask, 3)-1, prop.SysCoord)
				temperature = temperature and temperature.target
				
				local rail_len = mark_rail_len[prop.ID]
				local norm_gap_width 
				if rail_len then
					if temperature then
						norm_gap_width = get_nominal_gape_width(rail_len, temperature)
					end
				end

				local dif_norm_width = ''
				local width = mark_helper.GetGapWidth(mark)
				if width and norm_gap_width then
					dif_norm_width = sprintf('%.1f', width - norm_gap_width)
				end
		
				local other = mark_pair[bit32.bxor(r, 0x03)]
				local cur_zabeg = other and prop.SysCoord - other.prop.SysCoord
				
		
				local res = {
					{name='ID', value=prop.ID, desc='Mark ID'},
					{name='KM', value=km},
					{name='M', value=sprintf("%.02f", m + mm/1000)},
					{name='rail', value=r, desc='Номер рельса'},
					{name='thread', value=get_rail_name(mark), desc='Название рельса'},
					{name='temperature',value=temperature, desc='Т рельса, °С'},
					{name='gap_width', value=width or '', desc='Зазор, мм'},
					{name='norm_gap_width', value=norm_gap_width or '', desc='Ном. зазор, мм'},
					{name='dif_norm_width', value=dif_norm_width, desc='Откл. от ном., мм'},
					{name='rail_len', value=rail_len and sprintf("%.02f", rail_len/1000) or '', desc='Длина рельса'},
					{name='pair_mark_id', value=other and other.prop.ID or '', desc='Отметка на другом рельсе'},
					{name='cur_zabeg', value=cur_zabeg and sprintf('%.02f', cur_zabeg / 1000) or '', desc='Относительный забег'},
				}
				
				res.mark = mark
				row[r] = res
				row.ext = {}
				
				if mark_pair[1] and mark_pair[2] then
					local c1, c2 = mark_pair[1].prop.SysCoord, mark_pair[2].prop.SysCoord
					row.ext[1] = {name='zabeg', value=sprintf('%.02f', (c2 - c1) / 1000), desc='Забег'}
				end
			
				mark_counter()
			end
		end
		
		local filters_names = {"Меньше 3 мм", "Все", "Больше 22 мм", "Слепые подряд", "Больше 35 мм"}
		local res = eksui_template_rows{rows=rows, get_encoded_frame=get_encoded_frame, report_code=REPORT_GAPS_IDs[1], report_name=REPORT_GAPS_IDs[2],report_desc=REPORT_GAPS_IDs[3], report_filter=filters_names[filter_mode]}

		local file_name = sprintf("c:\\%s.xml", REPORT_GAPS_IDs[2]) 
		local dst_file = assert(io.open(file_name, 'w+'))
		dst_file:write(res)
		dst_file:close()
		
		if not DONT_OPEN_RESULT then
			os.execute("start " .. file_name)
		end
	end
	dlg:Destroy()
end

-- отчет по маячнам отметкам
local function report_welding(params)
	return EnterScope(function (defer)
	local right_rail_mask = tonumber(Passport.FIRST_LEFT) + 1
	local ok, setup_temperature = iup.GetParam(params.sheetname, nil, "Температура закрепления: %i\n", 35)
	if not ok then	
		return
	end
	
	local guids = {
		["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"] = true, -- VID_BEACON_INDT
		["{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}"] = true, -- VID_BEACON_INDT
		}
	
	local dlg = luaiup_helper.ProgressDlg()
	defer(dlg.Destroy, dlg)
	local marks = Driver:GetMarks()
	
	marks = FilterSort(marks, 
		function(mark) return guids[mark.prop.Guid] and mark.ext.RAWXMLDATA end,
		get_sys_coord_key,
		function(val, desc) dlg:step(val, desc) end)

	local mark_pairs = BuildMarkPairs(marks, 500)

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#mark_pairs)

	assert(#mark_pairs == 0 or #mark_pairs == data_range.Rows.count, 'misamtch count of mark_pairs and table rows')

	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom, 'can not create MSXML object')

	local prev_mark_offset = {}

	local function insert_mark(line, rail, mark)
		local column_offset = (rail == right_rail_mask) and 8 or 0
		local prop = mark.prop
		local ext = mark.ext
		
		local vch = bit32.btest(prop.RailMask, 1) and 17 or 18
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		local temperature = Driver:GetTemperature(bit32.band(prop.RailMask, 3)-1, prop.SysCoord)
		local img_path = ShowVideo ~= 0 and Driver:GetFrame( 
			vch, 
			prop.SysCoord, {
				mark_id=(ShowVideo == 1) and prop.ID or 0,
				mode=3,
				panoram_width=1500, 
				frame_count=3, 
				width=400, 
				height=300,
			} )
		local uri = make_mark_uri(prop.ID)
		
		temperature = temperature and temperature.target

		data_range.Cells(line, 1 + column_offset).Value2 = km
		excel:InsertLink(data_range.Cells(line, 2 + column_offset), uri, sprintf("%.02f", m + mm/1000))
		data_range.Cells(line, 3 + column_offset).Value2 = temperature 
		
		local shift = mark_helper.GetBeaconOffset(mark)
		if shift then
			if not prev_mark_offset[prop.RailMask] then prev_mark_offset[prop.RailMask] = 0 end
			local diff_dist = shift - prev_mark_offset[prop.RailMask]
			local diff_neitral_temp = diff_dist / 1.18
		
			data_range.Cells(line, 4 + column_offset).Value2 = shift
			data_range.Cells(line, 5 + column_offset).Value2 = sprintf('%d', diff_dist)
			data_range.Cells(line, 6 + column_offset).Value2 = sprintf('%d', diff_neitral_temp)
			data_range.Cells(line, 7 + column_offset).Value2 = sprintf('%d', setup_temperature + diff_neitral_temp)
		end
		
		if img_path and #img_path then
			excel:InsertImage(data_range.Cells(line, 8 + column_offset), img_path)
		end
	end

	for line, mark_pair in ipairs(mark_pairs) do
		for r, mark in pairs(mark_pair) do
			insert_mark(line, r, mark)
		end
			
		if not dlg:step(line / #mark_pairs, sprintf(' Process %d / %d line', line, #mark_pairs)) then 
			break
		end
	end 

	if data_range and ShowVideo == 0 then 
		excel:AutoFitDataRows()
		data_range.Cells(nil, 8).ColumnWidth = 0
		data_range.Cells(nil, 16).ColumnWidth = 0
	end
	excel:SaveAndShow()
	end)
end

-- отчет по скреплениям 
local function report_fasteners(params)
	return EnterScope(function (defer)
		
	local filter_mode = 2
	if not HIDE_PROGRESS_DLG then
		filter_mode = luaiup_helper.ShowRadioBtn('Тип отчета', {"Показать все", "Дефектные", "Нормальные"}, filter_mode)
	end
	
	if not filter_mode then
		return
	end

	local function filter_fn(mark)
		local accept = table_find(fastener_guids, mark.prop.Guid) and mark.ext.RAWXMLDATA
		
		if accept and filter_mode ~= 1 then  -- если отметка еще подходит и нужно выбрать не все (только дефектные или только нормальные)
			accept = mark_helper.IsFastenerDefect(mark)
			if filter_mode == 3 then accept = not accept end	-- если нужны нормальные, инвертируем
		end
		return accept
	end
	
	local dlg = luaiup_helper.ProgressDlg()
	defer(dlg.Destroy, dlg)
	local marks = Driver:GetMarks()
	
	marks = mark_helper.filter_marks(marks, filter_fn, make_filter_progress_fn(dlg))
	marks = sort_mark_by_coord(marks)

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#marks)

local fastener_type_names = {
	[0] = 'КБ-65', 
	[1] = 'Аpc',  
	[2] = 'ДО', -- скрепление на деревянной шпале на костылях 
	[3] = 'КД', -- скрепление на деревянной шпале как КБ-65 но на двух шурупах 
}
	
local fastener_fault_names = {
	[0] = 'норм.',
	[1] = 'От.КБ',  -- отсутствие клемного болта kb65
	[2] = 'От.КЛМ',	-- отсуствие клеммы apc
	[10] = 'От.ЗБ',  -- отсутствие закладного болта kb65
	[11] = 'От.КЗБ',  -- отсутствие клемного и закладного болта kb65	
}


	assert(#marks == 0 or #marks == data_range.Rows.count, 'misamtch count of mark and table rows')

	for line, mark in ipairs(marks) do
		local prop, ext = mark.prop, mark.ext
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		local fastener_params = mark_helper.GetFastenetParams(mark) or {}
		
		local uri = make_mark_uri(prop.ID)
		excel:InsertLink(data_range.Cells(line, 1), uri, sprintf("%d km %.3f m", km, m + mm/1000))
		data_range.Cells(line, 2).Value2 = get_rail_name(mark)
		data_range.Cells(line, 3).Value2 = Driver:GetSumTypeName(prop.Guid)
		data_range.Cells(line, 4).Value2 = fastener_type_names[fastener_params['FastenerType']] or '??'
		data_range.Cells(line, 5).Value2 = fastener_fault_names[fastener_params['FastenerFault']] or '??'
		insert_frame(excel, data_range, mark, line, 6)
		
		if not dlg:step(line / #marks, sprintf(' Process %d / %d mark', line, #marks)) then 
			break
		end
	end 

	if data_range and ShowVideo == 0 then 
		excel:AutoFitDataRows()
		data_range.Cells(6).ColumnWidth = 0
	end
	
	excel:SaveAndShow()
	end)
end


-- отчет по сткпенькам на стыках
local function report_recog_joint_step(params)
	return EnterScope(function (defer)
	local ok, min_height = iup.GetParam(params.sheetname, nil, "Пороговая высота ступеньки: %i мм\n", 20)
	if not ok then	
		return
	end

	local function filter_fn(mark)
		local accept = table_find(gap_rep_filter_guids, mark.prop.Guid) and mark.ext.RAWXMLDATA
		if accept then 
			local step = mark_helper.GetRailGapStep(mark)
			accept = step and step >= min_height
		end
		return accept
	end
	
	local dlg = luaiup_helper.ProgressDlg()
	defer(dlg.Destroy, dlg)
	local marks = Driver:GetMarks()
	
	marks = mark_helper.filter_marks(marks, filter_fn, make_filter_progress_fn(dlg))
	marks = sort_mark_by_coord(marks)
	
	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#marks)

	assert(#marks == 0 or #marks == data_range.Rows.count, 'misamtch count of mark and table rows')

	for line, mark in ipairs(marks) do
		local prop, ext = mark.prop, mark.ext
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		local step = mark_helper.GetRailGapStep(mark)
		
		local uri = make_mark_uri(prop.ID)
		excel:InsertLink(data_range.Cells(line, 1), uri, sprintf("%d km %.3f m", km, m + mm/1000))
		data_range.Cells(line, 2).Value2 = get_rail_name(mark)
		--data_range.Cells(line, 3).Value2 = Driver:GetSumTypeName(prop.Guid)
		data_range.Cells(line, 3).Value2 = sprintf("%d", step)
		insert_frame(excel, data_range, mark, line, 4)
		
		if not dlg:step(line / #marks, sprintf(' Process %d / %d mark', line, #marks)) then 
			break
		end
	end 

	if data_range and ShowVideo == 0 then 
		excel:AutoFitDataRows()
		data_range.Cells(4).ColumnWidth = 0
	end
	
	excel:SaveAndShow()
	end)
end


-- отчет по неспецифицированным объектам
local function report_surface_defects(params)
	return EnterScope(function (defer)
	local res, user_width, user_lenght, user_area = iup.GetParam("Фильтрация дефектов", nil, 
		"Ширина (мм): %s\n\z
		Высота (мм): %s\n\z
		Площадь (мм): %i\n",
		'', '', 1000)
	if not res then
		return
	end
	
	user_width = #user_width > 0 and tonumber(user_width)
	user_lenght = #user_lenght > 0 and tonumber(user_lenght)
	
	local function filter_fn(mark)
		local accept = table_find(surface_defects_guids, mark.prop.Guid) and mark.ext.RAWXMLDATA
		local surf_prm = accept and mark_helper.GetSurfDefectPrm(mark)
		
		if surf_prm  then
			-- https://bt.abisoft.spb.ru/view.php?id=251#c592
			local mark_length = surf_prm.SurfaceLength
			local mark_width = surf_prm.SurfaceWidth	
			local mark_area = surf_prm.SurfaceArea
			
			if mark_length and mark_length >= 60 then
				accept = true
			else
				accept =
					(not user_width or (mark_width and mark_width >= user_width)) and
					(not user_lenght or (mark_length and mark_length >= user_lenght)) and
					(mark_area >= user_area)
			end
			print(user_width, user_lenght, user_area, '|', mark_width, mark_length,  mark_area,  '=', accept)
		end
		
		return accept
	end
	
	local dlg = luaiup_helper.ProgressDlg()
	defer(dlg.Destroy, dlg)
	local marks = Driver:GetMarks()
	
	marks = mark_helper.filter_marks(marks, filter_fn, make_filter_progress_fn(dlg))
	marks = sort_mark_by_coord(marks)

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#marks)

	assert(#marks == 0 or #marks == data_range.Rows.count, 'misamtch count of mark and table rows')

	for line, mark in ipairs(marks) do
		
		local prop = mark.prop
		local ext = mark.ext
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		
		local uri = make_mark_uri(prop.ID)
		
		data_range.Cells(line, 1).Value2 = get_rail_name(mark)
		data_range.Cells(line, 2).Value2 = km
		excel:InsertLink(data_range.Cells(line, 3), uri, sprintf("%.02f", m + mm/1000))
		
		local prm = mark_helper.GetSurfDefectPrm(mark)
		--data_range.Cells(line, 4).Value2 = sprintf('%d (%s, %s)', prm.SurfaceArea, prm.SurfaceLength, prm.SurfaceWidth)
		data_range.Cells(line, 4).Value2 = sprintf('%d', prm.SurfaceArea)
		
		insert_frame(excel, data_range, mark, line, 5)
		
		if not dlg:step(line / #marks, sprintf(' Process %d / %d mark', line, #marks)) then 
			break
		end
	end 

	if data_range and ShowVideo == 0 then 
		excel:AutoFitDataRows()
		data_range.Cells(5).ColumnWidth = 0
	end
	excel:SaveAndShow()
	end)
end

local function report_show_passport()
	os.execute("mkdir " .. TEST_EKASUI_OUT_PREFIX)
	local file = assert(io.open(TEST_EKASUI_OUT_PREFIX .. "\\psp.csv", 'w+'))
	for name, value in mark_helper.sorted(Passport) do
		file:write(string.format("%s;%s;\n", name, value))
	end
	for name, value in mark_helper.sorted(EKASUI_PARAMS) do
		file:write(string.format("%s;%s;\n", name, value))
	end
	file:close()
end

local function report_not_implemented()
	iup.Message("ATape", "Отчет не реализован")
end

-- ====================================================================================
local ProcessSumFile = "Scripts\\ProcessSum.xlsm"

local Report_Functions = {}

local cur_file_reports = {
	---------------------------------------
	-- c ЕКАСУИ 
	{name="Стыковые зазоры|Excel" ,  fn=report_gaps      , params={ filename=ProcessSumFile, sheetname="Ведомость Зазоров", guids=gap_rep_filter_guids }, guids=gap_rep_filter_guids},
	{name="Стыковые зазоры|ЕКАСУИ ", fn=report_gaps      , params={ eksui=true,                                             guids=gap_rep_filter_guids }, guids=gap_rep_filter_guids},	
	{name="Болтовые стыки|Excel",    fn=report_crew_join , params={ filename=ProcessSumFile, sheetname="Ведомость Болтов",  guids=gap_rep_filter_guids }, guids=gap_rep_filter_guids},
	{name="Болтовые стыки|ЕКАСУИ ",  fn=report_crew_join , params={ eksui=true,                                             guids=gap_rep_filter_guids }, guids=gap_rep_filter_guids},	

	-- без ЕКАСУИ
	--{name="Ведомость Стыковых зазоров"       , fn=report_gaps            , params={ filename=ProcessSumFile, sheetname="Ведомость Зазоров"       }, guids=gap_rep_filter_guids   },
	--{name="Ведомость Болтовых стыков"        , fn=report_crew_join       , params={ filename=ProcessSumFile, sheetname="Ведомость Болтов"        }, guids=gap_rep_filter_guids   },	
	------------------------------------------
	{name="Скрепления"             , fn=report_fasteners       , params={ filename=ProcessSumFile, sheetname="Ведомость Скреплений"    }, guids=fastener_guids         },
	{name="Горизонтальные уступы" , fn=report_recog_joint_step, params={ filename=ProcessSumFile, sheetname="Горизонтальные ступеньки"}, guids=gap_rep_filter_guids   },
	{name="Поверхностные дефекты" , fn=report_surface_defects , params={ filename=ProcessSumFile, sheetname="Поверхн. дефекты"        }, guids=surface_defects_guids  }, 
	{name="Маячные метки"          , fn=report_welding         , params={ filename=ProcessSumFile, sheetname="Ведомость сварной плети" }, guids=beacon_rep_filter_guids},
}


prev_ATAPE = ATAPE -- disable test code execute
ATAPE = true

if not HUN then
	local report_rails = require 'sum_report_rails'
	report_rails.AppendReports(Report_Functions)

	local report_sleepers = require 'sum_report_sleepers'
	report_sleepers.AppendReports(Report_Functions)

	local report_joints = require 'sum_report_joints'
	report_joints.AppendReports(Report_Functions)

	local report_fastener = require 'sum_report_fastener'
	report_fastener.AppendReports(Report_Functions)

	local report_beacon = require 'sum_report_beacon'
	report_beacon.AppendReports(Report_Functions)

	local report_ballast = require 'sum_report_ballast'
	report_ballast.AppendReports(Report_Functions)

	local report_summory = require 'sum_report_summary'
	report_summory.AppendReports(Report_Functions)

	local report_rubki = require 'sum_report_rubki'
	report_rubki.AppendReports(Report_Functions)

	local report_npu = require 'sum_report_npu'
	report_npu.AppendReports(Report_Functions)

	for _, report in ipairs(cur_file_reports) do
		table.insert(Report_Functions, report)
	end

	local report_us_ekasui = require 'sum_report_us_ekasui'
	report_us_ekasui.AppendReports(Report_Functions)
else
	local report_hun_video = require 'sum_report_hun'
	report_hun_video.AppendReports(Report_Functions)
end

if SHOW_TEST_REPORTS then
	local r1 = {name="параметры"          , fn=report_show_passport}
	table.insert(Report_Functions, r1)
end

ATAPE = prev_ATAPE

-- ================================ EXPORT FUNCTIONS ================================= --

function GetAvailableReports() -- exported
	local res = {}
	for _, n in ipairs(Report_Functions) do 
		if not string.find(n.name, "ЕКАСУИ") or EKASUI_PARAMS then
			table.insert(res, n.name)
		end
	end
	return res
end

function MakeReport(name) -- exported
	for _, n in ipairs(Report_Functions) do 
		if n.name == name then
			if not n.fn then
				errorf('report function (%s) not defined', name)
			end
			name = nil
			n.fn(n.params)
			break
--			ok, msg = pcall(n.fn, n.params)
--			if not ok then 
--				error(msg)
--			end
		end
	end

	if name then -- if reporn not found
		errorf('can not find report [%s]', name)
	end
end

function GetFilterGuids(reportName)
	local guids = {}
	
	for _, n in ipairs(Report_Functions) do 
		if n.name == reportName then
			return n.guids
		end
	end
	
	-- код для обслуживания отчетов с подотчетами, 
	-- когда открывается диалог генерации отчетов, там нужно показать количество отметок каждого типа
	-- но конкретный отчет еще не задан, известен только префикс, по нему и ищем
	reportName = reportName .. '|'
	for _, n in ipairs(Report_Functions) do 
		local item_name = n.name:sub(1, reportName:len())
		if item_name == reportName and n.guids then
			for _, g in ipairs(n.guids) do
				guids[g] = true;
			end
		end
	end

	local res = {}
	for k,_ in pairs(guids) do table.insert(res, k) end
	-- print('GetFilterGuids:', table.concat(res, ','))
	return res
end

-- https://bt.abisoft.spb.ru/view.php?id=895
function MakeVideogram(name, params)
	local sum_videogram = require 'sum_videogram'
	sum_videogram.MakeVideogram(name, params)
end

-- =======================================================================

-- тестирование
if not ATAPE then
	local test_report  = require('local_data_driver')
	test_report.Driver('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml')
	--test_report.Driver('D:\\d-drive\\ATapeXP\\Main\\test\\1\\[987]_2020_11_30_01.xml')
	
	--MakeReport('Дефекты УЗК в екасуи')
	MakeReport('Ведомость отступлений в содержании рельсовых стыков|ЕКАСУИ Ширина стыкового зазора, мм')
	--local guids = GetFilterGuids('Ведомость отступлений в содержании рельсов')
	--print(guids)

end

