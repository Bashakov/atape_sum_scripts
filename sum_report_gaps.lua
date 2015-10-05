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

local function dump (o)								-- help function for writing variable
	if type(o) == "number" then
		io.write(o)
	elseif type(o) == "string" then
		io.write(string.format("%q", o))
	elseif type(o) == "table" then
		io.write("{\n")
		for k,v in pairs(o) do
			dump(k)
			io.write(" = ")
			dump(v)
			io.write(",\n")
		end
		io.write("}\n")
	elseif type(o) == "userdata" then
		print(o)		
	else
		error("cannot dump a " .. type(o))
	end
end



-- ==========================================================



-- класс для хранения стыков и поиска по ним
local gap_mark_storage = {
	_storage = {},
	_max_diff = 500, -- 0.5 метра
	
	gap_guids = {
		["{19253263-2C0B-41EE-8EAA-000000000010}"] = true, --ISOSTYK
		["{19253263-2C0B-41EE-8EAA-000000000040}"] = true, --PSEUDOSTYK
	},
	
	_key = function(mark)
		local prop = mark:prop()
		local k = {bit32.band(prop.RailMask, 0x03), math.round(prop.SysCoord + prop.Len / 2.0, 0)}
		return k
	end,
	
	fill = function(self, marks, max_diff)
		self._storage = {} -- список отметок по каждому рельсу
		self._max_diff = max_diff
		
		local filter_fn = function(mark)
			return gap_guids[mark:prop().Guid]
		end
		
		for mark in SortKey( marks:range(), nil, filter_fn) do 
			local key = self._key(mark)
			self._storage[key] = mark
		end
	end,
	
	search = function(self, gap_mark)
		local src_key = self._key(gap_mark)
		
		for key, mark in pairs(self._storage) do				-- пройдем по всем стыкам и поищем
			local diff = math.abs(key[2] - src_key[2]) 			-- вычисляем разницу координат
			print(src_key[1], src_key[2], key[1], key[2], diff)
			if key[1] ~= src_key[1] and diff < self._max_diff then
				return mark 									-- и возвращаем его
			end
		end
	end,
}

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

local processed_gaps = {
	_processed = {{}, {}}, 
	
	clear = function(self)
		self._processed = {{}, {}}
	end,
	
	check = function(self, mark)
		if mark then
			local prop = mark:prop()
			return self._processed[prop.RailMask][prop.SysCoord]
		end
	end,
	
	push = function(self, mark)
		if mark then
			local prop = mark:prop()
			self._processed[prop.RailMask][prop.SysCoord] = true
		end
	end,
}

-- ================================================================

function sum_report_gaps(marks, dest, table_desc)
	
	-- 6. На одной строке допускатся располагать левый и правый стыки только в том случае, если значение забега не превышает 0,5 метра, в противном случае, стыки располагаются в последовательных строках.
	gap_mark_storage:fill(marks, 500) -- заполняем хранилище отметок стыков, чтоб потом искать по нему
	recogn_mark_storage:fill(marks) -- заполняем хранилище отметок распознования, чтоб потом искать по нему
	processed_gaps:clear()
	local offsetMagn = Driver:GetChannelOffset(11)
	
	local key_fn = function(mark)	-- сортируем отметки по координате
		local prop = mark:prop()
		return {prop.SysCoord}
	end
	local filter_fn = function(mark) -- оставляем отметки магнитного и определенного рельса
		local prop = mark:prop()
		return gap_guids[prop.Guid] ~= nil
	end
	local railmask2railname = function(mark) -- лев->1, прав->2
		local left_mask = tonumber(Passport.FIRST_LEFT) + 1
		return left_mask == mark:prop().RailMask and 1 or 2
	end
	
	local process_gap = function(mark, res, res_offset)
		if not mark then return end
		local prop, ext, report = mark:prop(), mark:ext(), mark:report()
		
		local raw_path = report.raw_path
		local km, m = string.match(raw_path, "(%d+):(%d+)")
		m = math.round(m / 1000, 2)
		local temperature = Driver:GetTemperature(bit32.band(prop.RailMask, 0x01) == 0x01 and 0 or 1, prop.SysCoord)
		
		res[1 + res_offset] = km
		res[2 + res_offset] = m
		res[3 + res_offset] = temperature and temperature.target or ""
		
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
	
	for mark1 in SortKey( marks:range(), key_fn, filter_fn) do 
		if not processed_gaps:check(mark1) then
			processed_gaps:push(mark1)
			
			--local prop1, ext1, report1 = mark1:prop(), mark1:ext(), mark1:report()
			local mark_by_rail = {} -- отметки по рельсам (лев-1, прав-2)
			mark_by_rail[railmask2railname(mark1)] = mark1
			
			local mark2 = gap_mark_storage:search(mark1)
			if mark2 then
				processed_gaps:push(mark2)
				mark_by_rail[railmask2railname(mark2)] = mark2
			end
			
			res_row = {}
			for i = 1, 16 do res_row[i] = "" end
			
			process_gap(mark_by_rail[1], res_row, 0)
			process_gap(mark_by_rail[2], res_row, 10)
			
			if not dest:Row(res_row) then 
				break
			end
		end
	end
end