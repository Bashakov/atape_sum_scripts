if not ATAPE then
	require "iuplua" 
end

-- OOP = require 'OOP'

stuff = require 'stuff'
luaiup_helper = require 'luaiup_helper'
excel_helper = require 'excel_helper'

local sprintf = stuff.sprintf

if not ShowVideo then
	ShowVideo = 1
end

-- итератор по нодам xml
local function SelectNodes(xml, xpath)
	return function(nodes)
		return nodes:nextNode()
	end, xml:SelectNodes(xpath)
end

-- извлечь количество и качество болтов из xml
local function GetCrewJointSafe(xmlDom)
	local count, defect = 0, 0
	local req_tmpl = '\z
/ACTION_RESULTS\z
/PARAM[@name="ACTION_RESULTS" and @value="CrewJoint"]\z
/PARAM[@name="FrameNumber" and @value]\z
/PARAM[@name="Result" and @value="main"]\z
/PARAM[@name="JointNumber" and @value]\z
/PARAM[@name="CrewJointSafe" and @value]/@value'

	for node in SelectNodes(xmlDom, req_tmpl) do
		count = count + 1
		local safe = tonumber(node.nodeValue)
		if safe ~= 1 then
			defect = defect + 1
		end
	end

	return count, defect
end

-- сделать строку ссылку для открытия атейпа на данной отметке
local function make_mark_uri(markid)
	local link = stuff.sprintf(" -g %s -mark %d", Passport.GUID, markid)
	link = string.gsub(link, "[%s{}]", function (c)
			return string.format("%%%02X", string.byte(c))
		end)
	return "atape:" .. link
end

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

-- получить ширины распознанных или отредактрованных ширин зазоров
local function GetRailGap(mark)
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom)
	local res = {}
	
	local ext = mark.ext
	if ext.RAWXMLDATA then
		xmlDom:loadXML(ext.RAWXMLDATA)	
	end

	local KWs = { 
		user = { a="CalcRailGap_User"}, 
		top  = { p="VIDEOIDENTGWT", a="CalcRailGap_Head_Top"}, 
		side = { p="VIDEOIDENTGWS", a="CalcRailGap_Head_Side"} 
	}
	
	local min_width
	local max_width
	for k, v in pairs(KWs) do
		local w = v.p and ext[v.p]
		if not w and ext.RAWXMLDATA then
			local node = xmlDom:SelectSingleNode(sprintf('ACTION_RESULTS\z
				/PARAM[@name="ACTION_RESULTS" and @value="%s"]\z
				/PARAM[@name="FrameNumber"]\z
				/PARAM[@name="Result" and @value="main"]\z
				/PARAM[@name="RailGapWidth_mkm" and @value]/@value', v.a))
			if node then
				w = tonumber(node.nodeValue) / 1000
			end
		end
		if w and not res.user then 
			res[k] = w
			min_width = w and min_width and math.min(w, min_width) or w
			max_width = w and max_width and math.max(w, max_width) or w
		end
	end
	
	return res, min_width, max_width
end

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


-- =================================================================================


local function dump_mark_list(template_name, sheet_name)
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

	local marks = Driver:GetMarks()
	local dlg = luaiup_helper.ProgressDlg()

	local out = {}
	for i = 1, #marks do 
		local mark = marks[i]
		local prop = mark.prop
		local vch = bit32.btest(prop.RailMask, 1) and 17 or 18
		out[i] = {
			prop = prop, 
			ext = mark.ext, 
			path = { Driver:GetPathCoord(prop.SysCoord) }, 
			name = Driver:GetSumTypeName(prop.Guid),
			img_path = Driver:GetFrame(
				vch, 
				prop.SysCoord, {
					mark_id = prop.ID,
					file_path = stuff.sprintf('%s\\img\\%d_%d.jpg', out_dir, prop.SysCoord, vch),
					width = 400,          -- ширина кадра
					height = 300,          -- высота кадра
				}
			),
		}

		if not dlg:step(1.0 * i / #marks, stuff.sprintf('progress %d / %d mark', i, #marks)) then 
			return 
		end
	end

	dlg:step(1, 'Dump saving ...');

	local prev_output = io.output()
	io.output(out_dir .. "\\dump.lua")
	stuff.save("marks", out)
	io.output(prev_output)
end


local function mark2excel(params)
	local marks = Driver:GetMarks()
	
	local dlg = luaiup_helper.ProgressDlg()

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#marks)

	assert(#marks == data_range.Rows.count, 'misamtch count of marks and table rows')

	for i = 1, #marks do 
		local mark = marks[i]
		local c = 1

		for n, v in pairs(mark.prop) do
			data_range.Cells(i, c).Value2 = stuff.sprintf('%s=%s', n, v)
			c = c + 1
		end
		for n, v in pairs(mark.ext) do
			data_range.Cells(i, c).Value2 = stuff.sprintf('%s=%s', n, v)
			c = c + 1
		end

		--excel_helper.InsertLink(data_range.Cells(i, 10), 'http://google.com', 'google')
		--excel_helper.InsetImage(data_range.Cells(i, 8), mark.img_path)

		if not dlg:step(1.0 * i / #marks, stuff.sprintf(' Process %d / %d mark', i, #marks)) then 
			return 
		end
	end

	excel:SaveAndShow()
end


local function report_crew_join(params)
	local filter_mode = luaiup_helper.ShowRadioBtn('Тип отчета', {"Показать все", "Дефектные", "Нормальные"}, 2)
	if not filter_mode then
		return
	end
	
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom)
	
	local function make_filter_fn()
		
		local guids = {
			["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = true,
			["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = true,
			["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = true,
			["{CBD41D28-9308-4FEC-A330-35EAED9FC804}"] = true,
		}
	
		return function(mark)
			if not (guids[mark.prop.Guid] and mark.ext.RAWXMLDATA and  mark.ext.VIDEOIDENTCHANNEL) then
				return false
			end
			if filter_mode == 1 then
				return true
			end
			
			xmlDom:loadXML(mark.ext.RAWXMLDATA)
			local cnt, defect = GetCrewJointSafe(xmlDom)
			
			local is_defect = true
			if cnt == 6 then
				is_defect = defect >= 3
			elseif cnt == 4 then
				is_defect = defect >= 2
			end

			if filter_mode == 2 then
				return is_defect
			end
				
			-- filter_mode == 3 
			return not is_defect
		end
	end
	
	local dlg = luaiup_helper.ProgressDlg()
	local marks = Driver:GetMarks()
	marks = FilterSort(marks, make_filter_fn(),
		function(mark) return {mark.prop.SysCoord} end,
		function(val, desc) dlg:step(val, desc) end)

	local mark_pairs = BuildMarkPairs(marks, 500)
	if #mark_pairs == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#mark_pairs)

	assert(#mark_pairs == data_range.Rows.count, 'misamtch count of mark_pairs and table rows')

	local function insert_mark(line, rail, mark)
		local column_offset = (rail == 1) and 0 or 5
		local prop = mark.prop
		local ext = mark.ext
		
		xmlDom:loadXML(ext.RAWXMLDATA)

		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		local count, defect = GetCrewJointSafe(xmlDom)
		local img_path = ShowVideo ~= 0 and Driver:GetFrame( 
			ext.VIDEOIDENTCHANNEL, 
			prop.SysCoord, {
				mark_id=(ShowVideo == 1) and prop.ID or 0,
				mode=3, 
				panoram_width=1500, 
				frame_count=3, 
				width=400, 
				height=300,
			})
		local uri = make_mark_uri(prop.ID)

		excel:InsertLink(data_range.Cells(line, 1 + column_offset), uri, km)
		data_range.Cells(line, 2 + column_offset).Value2 = sprintf("%.02f", m + mm/1000)
		data_range.Cells(line, 3 + column_offset).Value2 = count
		data_range.Cells(line, 4 + column_offset).Value2 = defect

		if img_path and #img_path then
			excel:InsertImage(data_range.Cells(line, 5 + column_offset), img_path)
		end

		data_range.Cells(line, 12+rail).Value2 = prop.SysCoord
	end

	for line, mark_pair in ipairs(mark_pairs) do
		for r, mark in pairs(mark_pair) do
			insert_mark(line, r, mark)
		end
		
		if not dlg:step(line / #mark_pairs, stuff.sprintf(' Process %d / %d line', line, #mark_pairs)) then 
			break
		end
	end 

	if ShowVideo == 0 then 
		excel:AutoFitDataRows()
		data_range.Cells(nil, 5).ColumnWidth = 0
		data_range.Cells(nil, 10).ColumnWidth = 0
	end
	excel:SaveAndShow()
end

local function report_gaps(params)
	local filter_mode = luaiup_helper.ShowRadioBtn('Тип отчета', {"Меньше 3 мм", "Все", "Больше 22 мм", "Слепые подряд", "Больше 35 мм"}, 2)
	if not filter_mode then
		return
	end
	
	local guids = {
			["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = true,
			["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = true,
			["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = true,
			["{CBD41D28-9308-4FEC-A330-35EAED9FC804}"] = true,
	}
	
	local dlg = luaiup_helper.ProgressDlg()
	local marks = Driver:GetMarks()
	marks = FilterSort(marks, 
		function(mark) return guids[mark.prop.Guid] and mark.ext.RAWXMLDATA and  mark.ext.VIDEOIDENTCHANNEL end,
		function(mark) return {mark.prop.SysCoord} end,
		function(val, desc) dlg:step(val, desc) end)

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

	if filter_mode == 1 or filter_mode == 3 then
		local function ff(mark)
			local widths, min_width, max_width = GetRailGap(mark)
			return (filter_mode == 1 and min_width and min_width <= 3) or (filter_mode == 3 and max_width and max_width >= 22)
		end
		marks = FilterSort(marks, ff, nil, function(val, desc) dlg:step(val, desc) end)
		
	elseif filter_mode == 5 then
		local function ff(mark)
			local widths, min_width, max_width = GetRailGap(mark)
			return ( max_width and max_width >= 35 )
		end
		marks = FilterSort(marks, ff, nil, function(val, desc) dlg:step(val, desc) end)		
		
	elseif filter_mode == 4 then
		local mark_ids = {}
		local prev_gap_width = {}
		
		for _, mark in ipairs(marks) do
			local _, min_width, _ = GetRailGap(mark)
			min_width = min_width or 100000
			local prev = prev_gap_width[mark.prop.RailMask] 
			if prev and prev.width <= 3 and min_width <= 3 then
				mark_ids[prev.ID] = true
				mark_ids[mark.prop.ID] = true
			end
			prev_gap_width[mark.prop.RailMask] = {ID=mark.prop.ID, width=min_width}
		end
		
		marks = FilterSort(marks, 
			function(mark) return mark_ids[mark.prop.ID] end,
			nil, 
			function(val, desc) dlg:step(val, desc) end)
	end

	local mark_pairs = BuildMarkPairs(marks, 500)
	if #mark_pairs == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#mark_pairs)

	--print(#mark_pairs, data_range.Rows.count)
	assert(#mark_pairs == data_range.Rows.count, 'misamtch count of mark_pairs and table rows')
	
	local function insert_mark(line, rail, mark)
		local column_offset = (rail == 1) and 0 or 9
		local prop = mark.prop
		local ext = mark.ext
		
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		local temperature = Driver:GetTemperature(bit32.band(prop.RailMask, 3)-1, prop.SysCoord)
		
		local img_path = ShowVideo ~= 0 and Driver:GetFrame( 
			ext.VIDEOIDENTCHANNEL, 
			prop.SysCoord, {
				mark_id = (ShowVideo == 1) and prop.ID or 0,
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
		
		local rail_len = mark_rail_len[prop.ID]
		local norm_gap_width
		if rail_len then
			data_range.Cells(line, 7 + column_offset).Value2 = sprintf("%.02f", rail_len/1000)
			if temperature then
				norm_gap_width = get_nominal_gape_width(rail_len, temperature)
				data_range.Cells(line, 5 + column_offset).Value2 = norm_gap_width
			end
		end

		if img_path and #img_path then
			excel:InsertImage(data_range.Cells(line, 8 + column_offset), img_path)
		end
		
		local widths, min_width, max_width = GetRailGap(mark)
		if min_width then
			data_range.Cells(line, 4 + column_offset).Value2 = min_width
			if norm_gap_width then
				data_range.Cells(line, 6 + column_offset).Value2 = sprintf('%.1f', min_width - norm_gap_width)
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
	
		if not dlg:step(line / #mark_pairs, stuff.sprintf(' Process %d / %d line', line, #mark_pairs)) then 
			break
		end
	end 
	
	if ShowVideo == 0 then 
		excel:AutoFitDataRows()
		data_range.Cells(nil, 8).ColumnWidth = 0
		data_range.Cells(nil, 17).ColumnWidth = 0
	end
	excel:SaveAndShow()
end


local function report_welding(params)
	local ok, setup_temperature = iup.GetParam(params.sheetname, nil, "Температура закрепления: %i\n", 35)
	if not ok then	
		return
	end
	
	local guids = {
		["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"] = true, -- VID_BEACON_INDT
		["{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}"] = true, -- VID_BEACON_INDT
		}
	
	local dlg = luaiup_helper.ProgressDlg()
	local marks = Driver:GetMarks()
	
	marks = FilterSort(marks, 
		function(mark) return guids[mark.prop.Guid] and mark.ext.RAWXMLDATA and  mark.ext.VIDEOIDENTCHANNEL end,
		function(mark) return {mark.prop.SysCoord} end,
		function(val, desc) dlg:step(val, desc) end)

	local mark_pairs = BuildMarkPairs(marks, 500)
	if #mark_pairs == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#mark_pairs)

	assert(#mark_pairs == data_range.Rows.count, 'misamtch count of mark_pairs and table rows')

	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom, 'can not create MSXML object')

	local prev_mark_offset = {}

	local function GetBeaconOffset(mark)
		xmlDom:loadXML(mark.ext.RAWXMLDATA)
		local node = xmlDom:SelectSingleNode('\z
			/ACTION_RESULTS\z
			/PARAM[@name="ACTION_RESULTS" and @value="Beacon_Web"]\z
			/PARAM[@name="FrameNumber" and @value and @coord]\z
			/PARAM[@name="Result" and @value="main"]\z
			/PARAM[@name="Shift_mkm" and @value]/@value')
		return node and tonumber(node.nodeValue)/1000
	end
	
	local function insert_mark(line, rail, mark)
		local column_offset = (rail == 1) and 0 or 8
		local prop = mark.prop
		local ext = mark.ext
		
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		local temperature = Driver:GetTemperature(bit32.band(prop.RailMask, 3)-1, prop.SysCoord)
		local img_path = ShowVideo ~= 0 and Driver:GetFrame( 
			ext.VIDEOIDENTCHANNEL, 
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
		
		local shift = GetBeaconOffset(mark)
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
			
		if not dlg:step(line / #mark_pairs, stuff.sprintf(' Process %d / %d line', line, #mark_pairs)) then 
			break
		end
	end 

	if ShowVideo == 0 then 
		excel:AutoFitDataRows()
		data_range.Cells(nil, 8).ColumnWidth = 0
		data_range.Cells(nil, 16).ColumnWidth = 0
	end
	excel:SaveAndShow()
end



local unspec_obj_filter_guids = 
{
	"{0860481C-8363-42DD-BBDE-8A2366EFAC90}",
}

local function report_unspec_obj(params)
	local left_mask = tonumber(Passport.FIRST_LEFT) + 1
	
	local dlg = luaiup_helper.ProgressDlg()
	local marks = Driver:GetMarks()
	local guids = {}
	for _, g in ipairs(unspec_obj_filter_guids) do guids[g] = true end 
	
	marks = FilterSort(marks, 
		function(mark) return guids[mark.prop.Guid] and mark.ext.VIDEOFRAMECOORD and mark.ext.VIDEOIDENTCHANNEL and mark.ext.UNSPCOBJPOINTS end,
		function(mark) return {mark.prop.SysCoord} end,
		function(val, desc) dlg:step(val, desc) end)

	if #marks == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#marks)

	assert(#marks == data_range.Rows.count, 'misamtch count of mark and table rows')

	for line, mark in ipairs(marks) do
		
		local prop = mark.prop
		local ext = mark.ext
		local rail = left_mask == bit32.band(prop.RailMask, 0x3) and "Левый" or "Правый"
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		
		local img_path = ShowVideo ~= 0 and Driver:GetFrame( ext.VIDEOIDENTCHANNEL, prop.SysCoord, {mode=3, panoram_width=1500, frame_count=3, width=400, height=300} )
		local uri = make_mark_uri(prop.ID)
		
		data_range.Cells(line, 1).Value2 = rail
		data_range.Cells(line, 2).Value2 = km
		excel:InsertLink(data_range.Cells(line, 3), uri, sprintf("%.02f", m + mm/1000))
		data_range.Cells(line, 4).Value2 = prop.Description 
		
		if img_path and #img_path then
			excel:InsertImage(data_range.Cells(line, 5), img_path)
		end
			
		if not dlg:step(line / #marks, stuff.sprintf(' Process %d / %d mark', line, #marks)) then 
			break
		end
	end 

	if ShowVideo == 0 then 
		excel:AutoFitDataRows()
		data_range.Cells(5).ColumnWidth = 0
	end
	excel:SaveAndShow()
end


local joint_filter_guids = 
{
	"{19253263-2C0B-41EE-8EAA-000000000010}",
	"{19253263-2C0B-41EE-8EAA-000000000040}",
}

local function report_coord(params)
	local dlg = luaiup_helper.ProgressDlg()
	local marks = Driver:GetMarks()
	local guids = {}
	for _, g in ipairs(joint_filter_guids) do guids[g] = true end 
	
	marks = FilterSort(marks, 
		function(mark) return guids[mark.prop.Guid] end,
		function(mark) return {mark.prop.SysCoord} end,
		function(val, desc) dlg:step(val, desc) end)

	if #marks == 0 then
		iup.Message('Info', "Подходящих отметок не найдено")
		return
	end

	local excel = excel_helper(Driver:GetAppPath() .. params.filename, params.sheetname, false)
	excel:ApplyPassportValues(Passport)
	local data_range = excel:CloneTemplateRow(#marks)
	local vdCh = params.ch

	assert(#marks == data_range.Rows.count, 'misamtch count of mark and table rows')

	for line, mark in ipairs(marks) do
		local prop, ext = mark.prop, mark.ext
		local km, m, mm = Driver:GetPathCoord(prop.SysCoord)
		
		local coord = prop.SysCoord + prop.Len / 2, 0
		local offsetVideo = Driver:GetVideoCurrentOffset(vdCh)
		local offsetMagn = Driver:GetChannelOffset(11)
		local frcoord = coord + offsetVideo + offsetMagn
		print( vdCh, coord, offsetVideo, offsetMagn, frcoord )

		data_range.Cells(line, 1).Value2 = sprintf("%d km %d m %d mm", km, m, mm)
		data_range.Cells(line, 2).Value2 = coord
		data_range.Cells(line, 3).Value2 = coord + offsetMagn
		data_range.Cells(line, 4).Value2 = coord + offsetMagn + offsetVideo
		data_range.Cells(line, 5).Value2 = vdCh
		data_range.Cells(line, 6).Value2 = frcoord
		
		local img_path = Driver:GetFrame( vdCh, coord + offsetMagn, {mode=3, panoram_width=1500, frame_count=3, width=400, height=300} )
		if img_path and #img_path then
			excel:InsertImage(data_range.Cells(line, 7), img_path)
		end
		
		if not dlg:step(line / #marks, stuff.sprintf(' Process %d / %d mark', line, #marks)) then 
			break
		end
	end 

	excel:SaveAndShow()
end

-- ====================================================================================

local gap_rep_filter_guids = 
{
	"{CBD41D28-9308-4FEC-A330-35EAED9FC801}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
	"{CBD41D28-9308-4FEC-A330-35EAED9FC804}",
}

local beacon_rep_filter_guids = 
{
	"{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}",
	"{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",
}

local Report_Functions = {
	---{name="Сделать дамп отметок",			fn=dump_mark_list,		params={} },
	--{name="Сохранить в Excel",			fn=mark2excel,			params={ filename="Scripts\\ProcessSum.xls",	sheetname="test",}, 					},
	{name="Ведомость болтовых стыков",		fn=report_crew_join,	params={ filename="Scripts\\ProcessSum.xls",	sheetname="Ведомость Болтов",}, 		guids=gap_rep_filter_guids},
	{name="Ведомость Зазоров",				fn=report_gaps,			params={ filename="Scripts\\ProcessSum.xls",	sheetname="Ведомость Зазоров",}, 		guids=gap_rep_filter_guids},
	{name="Ведомость сварной плети",		fn=report_welding,		params={ filename="Scripts\\ProcessSum.xls",	sheetname="Ведомость сварной плети",}, 	guids=beacon_rep_filter_guids},
	{name="Ведомость ненормативных объектов",fn=report_unspec_obj,	params={ filename="Scripts\\ProcessSum.xls",	sheetname="Ненормативные объекты",},	guids=unspec_obj_filter_guids},	
	--{name="КоордСтыков | 1",				fn=report_coord,		params={ filename="Scripts\\ProcessSum_КоордСтыков.xls",sheetname="КоордСтыковКадр", ch=1}, 	guids=joint_filter_guids},
	--{name="КоордСтыков | 2",				fn=report_coord,		params={ filename="Scripts\\ProcessSum_КоордСтыков.xls",sheetname="КоордСтыковКадр", ch=2}, 	guids=joint_filter_guids},
	--{name="КоордСтыков | 17",				fn=report_coord,		params={ filename="Scripts\\ProcessSum_КоордСтыков.xls",sheetname="КоордСтыковКадр", ch=17}, 	guids=joint_filter_guids},
	--{name="КоордСтыков | 18",				fn=report_coord,		params={ filename="Scripts\\ProcessSum_КоордСтыков.xls",sheetname="КоордСтыковКадр", ch=18}, 	guids=joint_filter_guids},
}


-- ================================ EXPORT FUNCTIONS ================================= --

function GetAvailableReports() -- exported
	res = {}
	for _, n in ipairs(Report_Functions) do 
		table.insert(res, n.name)
	end
	return res
end

function MakeReport(name) -- exported
	for _, n in ipairs(Report_Functions) do 
		if n.name == name then
			if not n.fn then
				stuff.errorf('report function (%s) not defined', name)
			end
			name = nil
			n.fn(n.params)
--			ok, msg = pcall(n.fn, n.params)
--			if not ok then 
--				error(msg)
--			end
		end
	end

	if name then -- if reporn not found
		stuff.errorf('can not find report [%s]', name)
	end
end

function GetFilterGuids(reportName)
	local guids = {}
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
	return res;
end



