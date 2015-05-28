dofile('scripts/xml_parse.lua')

local printf  = function(s,...)	return io.write(s:format(...)) 	end
local sprintf = function(s,...)	return s:format(...) 			end
local startwith = function(String, Start) return string.sub(String, 1, string.len(Start)) == Start end

function math.round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

function comma_value(num, sep)
  sep = sep or ' '
  local formatted = string.format("%d", num)
  while true do  
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1' .. sep .. '%2')
    if (k==0) then
      break
    end
  end
  return formatted
end

function dump (o)								-- help function for writing variable
	if type(o) == "number" then
		io.write(o)
	elseif type(o) == "string" then
		io.write(string.format("%q", o))
	elseif type(o) == "table" then
		io.write("{\n")
		for k,v in pairs(o) do
			io.write(" ", k, " = ")
			dump(v)
			io.write(",\n")
		end
		io.write("}\n")
	else
		error("cannot dump a " .. type(o))
	end
end

function SortKey(generator, key_fn, filter_fn)
	if not key_fn then
		return function()
			local obj = nil
			while true do
				obj = generator()
				if obj == nil or not filter_fn or filter_fn(obj) then
					break
				end
			end
			return obj
		end
	end

	function array_less(t1, t2)
		for i = 1, #t1 do
			local a,b = t1[i], t2[i]
			if a < b then return true end
			if b < a then return false end
		end
		return false
	end
	
	local data = {}
	local keys = {}
	
	local x = os.clock()
	for obj in generator do	
		if not filter_fn or filter_fn(obj) then
			table.insert(data, obj)
			local key = key_fn(obj)
			key[#key+1] = #data
			table.insert(keys, key)
		end
	end
	print(string.format("fetch time: %.3f", os.clock() - x))
		
	x = os.clock()
	table.sort(keys, array_less)
	print(string.format("sort time: %.3f", os.clock() - x))
	
	local i = 0 -- iterator variable
	return function () -- iterator function
		i = i + 1
		local key = keys[i]
		return key and data[key[#key]]
	end
end

function ChannelMask2videoChannels(ChannelMask, retString)
	local res = {}
	-- print(ChannelMask)
	for i = 1, 32 do
		local t = bit32.lshift(1, i)
		-- print (i, t, bit32.btest(ChannelMask, t))
		if bit32.btest(ChannelMask, t) then
			table.insert(res, i)
		end
	end
	return retString and table.concat(res, ",") or res
end

local function parse_ActionResult(ar)					-- function for parse xml from video_ident and getting found gap width
	if not ar then
		return nil
	end
	
	local r = xml2table(ar)
	
	local parseFN = function(fnum, coords)
		local w = fnum.PARAM.PARAM[2]._attr
		coords[tonumber(fnum._attr.value)] = {fn=fnum._attr.value, crd=fnum._attr.coord, w=w.value}
		--table.insert(coords, {fn=fnum._attr.value, crd=fnum._attr.coord, w=w.value} )
	end
	
	local parseRG = function(prm)
		coords = {}
		if (prm.PARAM) then
			parseFN(prm, coords)
		else
			for _, fnum in pairs(prm) do
				parseFN(fnum, coords)
			end
		end
		return coords
	end
	
	local res = {}
	for _, ar in pairs(r.root.ACTION_RESULTS.PARAM) do
		if startwith(ar._attr.value, 'CalcRailGap') then 
			res[ar._attr.value] = parseRG(ar.PARAM)
		end
	end
	return res
end

local PrepWidth = function(ar, name, sep)
	local t = {}
	if ar and ar[name] then
		for _, w in pairs(ar[name]) do 
			table.insert(t, sprintf('[%d]=%g', w.fn, math.round(w.w/1000, 1))) 
		end
	end
	return table.concat(t, sep or ", ")
end

local GetVIWidth = function(pos, markprop, ar)
	local KWs = { 
		["top"]  = { p="VIDEOIDENTGWT", a="CalcRailGap_Head_Top"}, 
		["side"] = { p="VIDEOIDENTGWS", a="CalcRailGap_Head_Side"} }
	local kw = KWs[pos]

	local w = markprop[kw.p]
	if not w then
		local desc = ar and ar[kw.a]
		w = desc and desc[0] and desc[0].w/1000
	end
	return w or 0
end

local function GetBeaconShift(x, beacon_name) 
	local r = xml2table(x)
	for _, ar in pairs(r.root.ACTION_RESULTS.PARAM) do
		if ar._attr.value == beacon_name then 
			for i, p in pairs(ar.PARAM.PARAM.PARAM) do
				--print(p._attr.name, p._attr.value)
				if p._attr.name == 'Shift_mkm' then
					return tonumber(p._attr.value) / 1000.0
				end
			end
		end
	end
end

function table.path(tbl, path)
	for w in string.gmatch(path, "%a+") do
		tbl = tbl and tbl[w]
	end
	return tbl
end

function expand_template(obj, template)
	function e(mth, var) 
		local tb = obj[mth](obj)
		--print (mth, var, obj, tb[var])
		return tostring(tb[var])
	end
	return string.gsub(template, "%$(%w+)%.([%w_]+)%$", e)
end

-- ==================================================================== --

local vid_ident = function(marks, dest)
	local key_fn = function(mark)
		local prop, ext = mark:prop(), mark:ext()
		return {-tonumber(ext.VIDEOIDENTRLBLT), prop.SysCoord}
	end
	
	local filter_fn = function(mark)
		local ext = mark:ext()
		return ext.VIDEOIDENTRLBLT
	end
	
	local prevReab = nil
	for mark in SortKey(marks:range(), key_fn, filter_fn) do 
		local prop, ext, report = mark:prop(), mark:ext(), mark:report()
		--print (report.human_path)
		local chMask = prop.ChannelMask

		local strCh = ChannelMask2videoChannels(chMask, true)
		local reab = ext.VIDEOIDENTRLBLT or "--"
		local frcoord = ext.VIDEOFRAMECOORD or "--"
		
		local ar = parse_ActionResult(ext.RAWXMLDATA)	-- convert XML to widths
		local wht = PrepWidth(ar, "CalcRailGap_Head_Top")
		local whs = PrepWidth(ar, "CalcRailGap_Head_Side")
		
		if prevReab and prevReab ~= reab then dest:Row({" "}) end
		prevReab = reab
		local res = { report.name, report.human_path, strCh, reab, frcoord, wht, whs }
		if not dest:Row(res) then --если вернулась false значит пользователь нажал отмену
			break
		end
	end
end

local vid_identLarge = function(marks, dest)
	for mark in marks:range() do 
		local prop, ext, report = mark:prop(), mark:ext(), mark:report()
		
		local chMask = prop.ChannelMask

		local strCh = ChannelMask2videoChannels(chMask, true)
		local reab = ext.VIDEOIDENTRLBLT or "--"
		local frcoord = ext.VIDEOFRAMECOORD or "--"
		
		local ar = parse_ActionResult(ext.RAWXMLDATA)	-- convert XML to widths
		local wnt = GetVIWidth("top", ext, ar)
		local wns = GetVIWidth("side", ext, ar)
		if(wnt >= 22 and wns >= 22) then
			local wht = PrepWidth(ar, "CalcRailGap_Head_Top")
			local whs = PrepWidth(ar, "CalcRailGap_Head_Side")
			local wh = sprintf("t:%s | s:%s", wht, whs)
			
			local res = { report.name, report.human_path, strCh, 
						reab, frcoord, math.round(wnt, 1), math.round(wns, 1), "", wh }
			if not dest:Row(res) then -- если вернулась false значит пользователь нажал отмену
				break
			end
		end
	end
end

local FAIL_VR = function(marks, dest)
	for mark in marks:range() do 
		local prop, ext, report = mark:prop(), mark:ext(), mark:report()
		local coord = prop.SysCoord + prop.Len / 2
		local chMask = prop.ChannelMask
		local RailMask = (prop.RailMask == 1) and 1 or 2
		local Description = prop.Description
		
		local offsetVideo = Driver:GetVideoCurrentOffset(RailMask)
		local offsetMagn = Driver:GetChannelOffset(11)
		local framecoord = coord + offsetVideo + offsetMagn
		
		local res = { propsMark.name, propsMark.human_path, RailMask, chMask, Description, coord, framecoord }
		if not dest:Row(res) then -- если вернулась false значит пользователь нажал отмену
			break
		end
	end
end

local miss_contr = function(marks, dest)
	local key_fn = function(mark)
		local prop = mark:prop()
		return {prop.RailMask, -prop.Len, prop.SysCoord}
	end
	
	local filter_fn = function(mark)
		local prop = mark:prop()
		return prop.Guid == "{19FF08BB-C344-495B-82ED-10B6CBAD508F}"
	end
	
	for mark in SortKey( marks:range(), key_fn, filter_fn) do 
		local prop, report = mark:prop(), mark:report()
	
		local RailMask = prop.RailMask
		local r1 = (RailMask == 1) and report.raw_len or ""
		local r2 = (RailMask == 2) and report.raw_len or ""
	
		local res = { report.N, report.human_path, report.human_rail, report.human_len, 
						prop.Description, "", report.raw_sys, r1, RailMask, r2}
		if not dest:Row(res) then 
			break
		end
	end
end

local function images_report(marks, dest)
	for mark in marks:range() do 
		local prop, ext, report = mark:prop(), mark:ext(), mark:report()
		
		local chMask = prop.ChannelMask
		local vdChls = ChannelMask2videoChannels(chMask, false);
		local vdCh = vdChls[1]
	
		local ar = parse_ActionResult(ext.RAWXMLDATA)	-- convert XML to widths
		local wht = PrepWidth(ar, "CalcRailGap_Head_Top", "\n")
		local whs = PrepWidth(ar, "CalcRailGap_Head_Side", "\n")
	
		local reab = ext.VIDEOIDENTRLBLT or "--"
		local frcoord = ext.VIDEOFRAMECOORD
		if not frcoord then
			vdCh = (prop.RailMask == 1) and 1 or 2
			local c = math.round(prop.SysCoord + prop.Len / 2, 0)
			local offsetVideo = Driver:GetVideoCurrentOffset(vdCh)
			local offsetMagn = Driver:GetChannelOffset(11)
			frcoord = c + offsetVideo + offsetMagn
			print(vdCh, c, offsetVideo, offsetMagn, frcoord)
		end
		local strfrcoord = frcoord or "--"
		
		local imgref = (frcoord and vdCh) and sprintf("$frame(%d,%d,%d)", vdCh, frcoord, prop.ID) or ""
		
		local row = {report.N, report.human_path, vdCh, strfrcoord, reab, wht, whs, imgref}
		if not dest:Row(row) then -- если вернулась false значит пользователь нажал отмену
			break
		end
	end
end


local function test_rep(marks, dest, table_desc)
	-- вспомогательная функция для копирования пар ключ-значение таблицы в массив
	function app_row(row, tbl) 
		for n,v in pairs(tbl) do -- цикл по всем свойствам таблицы
			table.insert(row, sprintf('%s=%s', n, tostring(v) ) )
		end
	end
	
	dest:SetCellText(2, 2, "Привет Мир!!")
	-- сначала напечатаем свойства из паспорта, которые хранятся в глобальной переменной "Passport"
	if true then
		dump(Passport)
		local row = {}
		table.insert(row, "Паспорт:")
		app_row(row, Passport)
		dest:Row(row) -- и отправим строку в Excel таблицу
	end
	
	-- теперь напечатаем все отметки, для этого пройдем циклом по ним
	for mark in marks:range() do 
		local row = {}
		-- у отметки есть 3 метода:
		--   prop (возвращает таблицу свойств отметки: SysCoord, Len, GUID), 
		--   ext (возвращает таблицу расширенных свойств), 
		--   report (возвращает таблицу с данных, подготовленных для отчета в XML(HTML))
		local prop, ext, report = mark:prop(), mark:ext(), mark:report()
		
		local temp = Driver:GetTemperature(prop.RailMask==1 and 0 or 1, prop.SysCoord)
		if temp then
			table.insert(row, "Температура:")
			app_row(row, temp)
		end
		
		table.insert(row, "Отметка:")
		app_row(row, prop)
		
		table.insert(row, "")
		table.insert(row, "EXT:")
		app_row(row, ext)
		
		table.insert(row, "")
		table.insert(row, "XML:")
		app_row(row, report)
		
		-- и отправим строку в Excel таблицу	
		if not dest:Row(row) then -- если вернулась false значит пользователь нажал отмену
			break
		end
	end
end


local function test_rep2(marks, dest, table_desc)
	function app_row(row, tbl)
		for n,v in pairs(tbl) do -- цикл по всем свойствам таблицы
			table.insert(row, sprintf('%s=%s', n, tostring(v) ) )
		end
	end
	
	if table_desc.sort then
		local sort_chnk = assert(load("function key_fn(mark) return {" .. table_desc.sort .. "} end"))
		sort_chnk()
	end 
		
	if table_desc.filter then
		local filter_chnk = assert(load("function filter_fn(mark) return " .. table_desc.filter .. " end"))
		filter_chnk()
	end 
	
	local prevReab = nil
	for mark in SortKey(marks:range(), key_fn, filter_fn) do 		
		local row = {}
		for _, tmpl in pairs(table_desc.row) do
			local cell = expand_template(mark, tmpl)
			table.insert(row, cell)
		end
		
		if not dest:Row(row) then -- если вернулась false значит пользователь нажал отмену
			break
		end
	end
end



local recogn_mark_storage = {
	_storage = {},
	
	fill = function(self, marks)
		local recorn_guids = {
			["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = true, --VID_INDT
			["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = true, --VID_INDT
		}
		self._storage = {}
		local filter_fn = function(mark)
		local prop = mark:prop()
			return recorn_guids[prop.Guid]
		end
		local cnt = 0
		for mark in SortKey( marks:range(), nil, filter_fn) do 
			local prop = mark:prop()
			local key = {bit32.band(prop.RailMask, 0x03), prop.SysCoord + prop.Len / 2}
			self._storage[key] = mark
			cnt = cnt + 1
		end
	end,
	
	search = function(self, rail, coord, maxdiff)
		if not maxdiff then maxdiff = 10000 end
		for key, mark in pairs(self._storage) do
			local diff = math.abs(key[2] - coord)
			-- utils.MsgBox( "msg", sprintf('%d %d', key[1], rail))
			if key[1] == rail and diff < maxdiff then
				return mark
			end
		end
	end,
}

local function rep_temperature(marks, dest, table_desc, rep_rail_mask)
	-- функция для генерации ссылки на данные
	local make_link = function(syscoord, desc, markid)
		desc = desc or syscoord
	
		local link = sprintf(" -g %s", Passport.GUID)
		if markid and markid ~= 0 then
			link = link .. sprintf(" -mark %d", markid)
		elseif syscoord and syscoord ~= 0 then
			link = link .. sprintf(" -syscoord %d", syscoord)
		else
			error("syscoord or markid MUST be specified")
		end
		
		link = string.gsub(link, "[%s{}]", function (c)
			return string.format("%%%02X", string.byte(c))
		end)
		return sprintf("$link(atape:%s,%s)", link, desc)
	end
	
	-- функция для дополнительной обработки результирующей строки для отметки типа сварка
	local process_svarka = function(mark, row)
		-- требует добавить изображение с линейных камер
		local prop = mark:prop()
		local vdCh = (prop.RailMask == 1) and 17 or 18
		--local vdCh = (prop.RailMask == 1) and 1 or 2
		local offsetVideo = Driver:GetVideoCurrentOffset(vdCh)
		local offsetMagn = Driver:GetChannelOffset(11)
		local frcoord = prop.SysCoord + prop.Len / 2 + offsetVideo + offsetMagn - 1024
		local imgref = sprintf("$frame(%d,%d)", vdCh, frcoord)	
		row[6] = imgref
		return row
	end
	
	-- функция для дополнительной обработки результирующей строки для отметок типа стык
	local process_stik = function(mark, row)
		-- требует добавить изображение с обычных камер с результатами расспознования
		local prop = mark:prop()
		local sys_coord = prop.SysCoord + prop.Len / 2  + Driver:GetChannelOffset(11)
		
		-- поищем ближайшую отметку распознования
		local recogn_mark = recogn_mark_storage:search(prop.RailMask, sys_coord)
		if recogn_mark then 
			-- если нашли, то печатаем кадр с расспознованием и ширину зазора
			local recogn_prop, recogn_ext = recogn_mark:prop(), recogn_mark:ext()
			local chMask = recogn_prop.ChannelMask
			local vdChls = ChannelMask2videoChannels(chMask, false);
			local vdCh = vdChls[1]
			local vdCh = (prop.RailMask == 1) and 1 or 2
			local frcoord = recogn_ext.VIDEOFRAMECOORD
			if frcoord and vdCh then
				imgref = sprintf("$frame(%d,%d,%d)", vdCh, frcoord, recogn_prop.ID)
				row[6] = imgref
			else
				row[6] = 'error parsing xml'
			end
			-- и заполним ширину
			local ar = parse_ActionResult(recogn_ext.RAWXMLDATA)	-- convert XML to widths
			local wnt = GetVIWidth("top", recogn_ext, ar)
			local wns = GetVIWidth("side", recogn_ext, ar)
			local res_width = (wnt and wns) and math.min(wnt, wns) or wnt or wns
			if res_width then
				row[4] = math.round(res_width, 1)
			end
		else
			-- иначе просто добавим кадр
			local vdCh = (prop.RailMask == 1) and 1 or 2
			local coord_video = sys_coord + Driver:GetVideoCurrentOffset(vdCh)
			local imgref = sprintf("$frame(%d,%d)", vdCh, coord_video)	
			row[6] = imgref
		end
		return row
	end
	
	-- функция для дополнительной обработки результирующей строки для отметок типа распознанных маячных
	local process_beacon = function(mark, row)
		-- требует добавить изображение c камер с результатами расспознования
		local prop, ext = mark:prop(), mark:ext()
		local vdCh = ext.VIDEOIDENTCHANNEL
		local frcoord = ext.VIDEOFRAMECOORD
		if frcoord and vdCh then
			row[6] = sprintf("$frame(%d,%d,%d)", vdCh, frcoord, prop.ID)
			-- print(row[6])
		else
			row[6] = 'no VIDEOIDENTCHANNEL or VIDEOFRAMECOORD property'
		end
		
		-- и заполним смещение
		local shift = GetBeaconShift(ext.RAWXMLDATA, "Beacon_Web")
		if shift then
			row[4] = shift
		end
		return row
	end
	
	-- список гуидов отметок, которые следует обработать, и функции их доп обработки
	local marks_process_fn = {
		["{19253263-2C0B-41EE-8EAA-000000000010}"] = process_stik, -- iso
		["{19253263-2C0B-41EE-8EAA-000000000040}"] = process_stik, -- pseudo
		["{19253263-2C0B-41EE-8EAA-000000000100}"] = process_svarka, -- SVARKA
		["{19253263-2C0B-41EE-8EAA-000000000400}"] = process_svarka, -- SVARKA_REG
		["{19253263-2C0B-41EE-8EAA-000000000800}"] = process_svarka, -- SVARKA_REG_NST
		["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"] = process_beacon, -- recogn_beacon
	}
	--local rep_rail_mask = (tonumber(Passport.FIRST_LEFT) == left_rail) and 1 or 2
	
	-- dest:SetCellText(4, 2, (kup==tonumber(Passport.FIRST_LEFT)) and "Левый" or "Правый")

	local key_fn = function(mark)	-- сортируем отметки по координате
		local prop = mark:prop()
		return {prop.SysCoord}
	end
	local filter_fn = function(mark) -- оставляем отметки магнитного и определенного рельса
		local prop = mark:prop()
		return bit32.band(prop.RailMask, 0x03) == rep_rail_mask and marks_process_fn[prop.Guid] ~= nil
	end
	
	recogn_mark_storage:fill(marks) -- заполняем хранилище отметок распознования, чтоб потом искать по нему
	
	local offsetMagn = Driver:GetChannelOffset(11)
	local max_process = 30000
	
	local current_rail_mask = 0
	local out_rail_name = false
	-- пойдем по отметкам магнитного
	for mark in SortKey( marks:range(), key_fn, filter_fn) do 
		local prop, ext, report = mark:prop(), mark:ext(), mark:report()
		local sys_coord = math.round(prop.SysCoord + prop.Len / 2 + offsetMagn)
--		if current_rail_mask ~= bit32.band(prop.RailMask, 0x03) then
--			current_rail_mask = bit32.band(prop.RailMask, 0x03)
--			dest:Row({"", sprintf("данные отчета по рельсу: %s", report.human_rail)})
--		end
		if not out_rail_name then
			out_rail_name = true
			dest:SetCellText(4, 2, report.human_rail)
		end
		
		local raw_path = report.raw_path
		local km, m = string.match(raw_path, "(%d+):(%d+)")
		m = math.round(m / 1000, 0)
		-- print(sys_coord, raw_path, km, m)

		local temperature = Driver:GetTemperature(bit32.band(prop.RailMask, 0x01) == 0x01 and 0 or 1, prop.SysCoord)
		
		local res_row = { 
			km, 
			m, 
			make_link(0, report.name, prop.ID), 
			"", 										-- placeholder for width
			temperature and temperature.target or "", 
			"", 										-- placeholder for frame
			comma_value(sys_coord, ' '),
			} 
		
		local fn = marks_process_fn[prop.Guid]
		if fn then
			res_row = fn(mark, res_row)
		end
		
		if not dest:Row(res_row) then 
			break
		end
		if max_process < 0 then break end
		max_process = max_process - 1
	end
end

local function rep_temperature_kup(marks, dest, table_desc)
	return rep_temperature(marks, dest, table_desc, 1)
end

local function rep_temperature_kor(marks, dest, table_desc)
	return rep_temperature(marks, dest, table_desc, 2)
end

-- ====================================================================================

local Report_Functions = {
--	{name="Видео Распознование", 			fn=vid_ident,			filename="ProcessSum.xls", 	sheetname="Видео Распознование"},
--	{name="Видео Распознование (>)", 		fn=vid_identLarge,		filename="ProcessSum.xls", 	sheetname="Видео Распознование (>)"},
--	{name="FAIL_VR", 						fn=FAIL_VR,				filename="ProcessSum.xls", 	sheetname="FAIL_VR"},
--	{name="Непроконтролированные участки", 	fn=miss_contr,			filename="ProcessSum.xls", 	sheetname="Непроконтролированные участки"},
--	{name="Изображения", 					fn=images_report,		filename="ProcessSum.xls", 	sheetname="Изображения"},
	{name="test", 							fn=test_rep,			filename="ProcessSum.xls",	sheetname="test"},
--	{name="test2", 							fn=test_rep2,			filename="ProcessSum.xls",	sheetname="test"},
	{name="Температуры (рельс 1)",			fn=rep_temperature_kup,	filename="ProcessSum.xls",	sheetname="Ведомость"},
	{name="Температуры (рельс 2)",			fn=rep_temperature_kor,	filename="ProcessSum.xls",	sheetname="Ведомость"},
}


-- ================================ EXPORT FUNCTIONS ================================= --


function GetAvailableReports() -- exported
	res = {}
	for _, n in ipairs(Report_Functions) do 
		table.insert(res, n.name)
	end
	return res
end

function MakeReport(name, marks, dest) -- exported
	-- utils.MsgBox( "Hi", sprintf("report: [%s]", name) )
	for _, n in ipairs(Report_Functions) do 
		if n.name == name then
			local table_desc = dest:SetTemplate(n.filename, n.sheetname or n.name)
			dump(table_desc)
			n.fn(marks, dest, table_desc)
			name = nil
			break;
		end
	end
	
	if name then -- if reporn not found
		utils.MsgBox( "Error", sprintf("No such report [%s]", name) )
	end
end

