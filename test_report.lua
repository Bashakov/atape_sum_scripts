require "luacom"
local sqlite3 = require "lsqlite3"
local OOP = require "OOP"

local function read_sum_file(file_path, guids, mark_id)
	local function format_guid(hex_guid)
		-- print(hex_guid)
		local m = table.pack(string.match(hex_guid, '\z
			(%x%x)(%x%x)(%x%x)(%x%x)\z
			(%x%x)(%x%x)\z
			(%x%x)(%x%x)\z
			(%x%x%x%x)\z
			(%x%x%x%x%x%x%x%x%x%x%x%x)'))
		assert(m.n == 10)
		local s = string.format('{%s%s%s%s-%s%s-%s%s-%s-%s}', m[4], m[3], m[2], m[1], m[6], m[5], m[8], m[7], m[9], m[10])
		-- print(s)
		return s
	end
	
	local db = sqlite3.open(file_path)
	
	local tids = nil
	if guids then
		local ids = {}
		for tid, tg in db:urows('SELECT TYPEID, hex(GUID) FROM SumrkMarkTypeTable') do
			tg = format_guid(tg)
			for _, ig in ipairs(guids) do
				if tg == ig then 
					table.insert(ids, tid)
					break
				end
			end
		end
		tids = table.concat(ids, ',')
		-- print(tids)
	end
	
	local str_stat = [[
		SELECT 
			m.MARKID as ID, 
			hex(t.GUID) as Guid, 
			m.SYSCOORD as SysCoord, 
			m.LENGTH as Len, 
			m.RAILMASK as RailMask, 
			m.ChannelMask as ChannelMask, 
			d.DESCRIPTION as Description
		FROM SumrkMainTable as m
		JOIN SumrkMarkTypeTable as t ON m.TYPEID = t.TYPEID
		LEFT JOIN SumrkDescTable as d ON m.MARKID = d.MARKID
		WHERE ( m.INNERFLAGS & 1) = 0 
		]]
	if tids then
		str_stat = str_stat .. ' AND t.TYPEID in (' .. tids .. ') '
	end
	if mark_id then
		str_stat = str_stat .. ' AND m.MARKID == ' .. mark_id .. ' '
	end
	
	local st = assert( db:prepare(str_stat) )
	local marks = {}
	while st:step() == sqlite3.ROW do
		local prop = st:get_named_values()
		prop.Guid = format_guid(prop.Guid)
		local mark = {
			prop = prop,
			ext = {},
			user = {},
		}
		marks[mark.prop.ID] = mark
	end
	
	for ext_name in db:urows('SELECT NAME FROM SumrkPropDescTable') do
		--print(ext_name)
		local req_params = 'SELECT * FROM SumrkXtndParamTable_' .. ext_name
		if mark_id then
			req_params = req_params .. ' WHERE MARKID == ' .. mark_id .. ' '
		end
		for markid, value in db:urows(req_params) do
			if marks[markid] then
				marks[markid].ext[ext_name] = value
			end
		end
	end

	local res = {}
	for _, mark in pairs(marks) do
		res[#res + 1] = mark
	end
	--print(#res)
	return res
end

local function psp2table(psp_path)						-- открыть xml паспорт и сохранить в таблицу его свойства
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom, 'can not create MSXML object')
	assert(xmlDom:load(psp_path), "can not open xml file: " .. psp_path)
	
	local function parse_attr(node) 						-- извлечение значений из атрибута
		return node.nodeName, node.nodeValue 
	end
	
	local function parse_item(name, value)					-- извлеченеи значений из ноды по именам атрибутов
		return function(node)
			return node.attributes:getNamedItem(name).nodeValue, node.attributes:getNamedItem(value).nodeValue  
		end
	end
	
	local requests = {
		{path = "/DATA_SET/DRIVER/@*",									fn = parse_attr },
		{path = "/DATA_SET/DEVICE/@*",									fn = parse_attr },
		{path = "/DATA_SET/REGISTRATION_DATA/@*",						fn = parse_attr },
		{path = "/DATA_SET/REGISTRATION_DATA/DATA[@INNER and @VALUE]", 	fn = parse_item('INNER', 'VALUE')},
	}
	
	local res = {}
	for _, req in ipairs(requests) do
		local nodes = xmlDom:SelectNodes(req.path)
		while true do
			local node = nodes:nextNode()
			if not node then break end
			local name, value = req.fn(node)
			-- print(name, value)
			res[name] = value
		end
	end
	return res
end

local function read_guids()
	local res = {}
			
	local pathCfg = os.getenv("ProgramFiles") .. '\\ATapeXP\\SpecUserMark.xml'
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom and xmlDom:load(pathCfg), 'can not create MSXML object')
	local nodes = xmlDom:SelectNodes('/SPEC_USER_MARK/SPEC_USER_MARK_DESCRIPTIONS/ITEM[@GUID and @VALUE]')
	while true do
		local node = nodes:nextNode()
		if not node then break end
		local guid = node.attributes:getNamedItem("GUID").nodeValue 
		local name = node.attributes:getNamedItem('VALUE').nodeValue
		res[string.upper(guid)] = name
	end
	return res
end

local function read_EKASUI_cfg()
	local pathCfg = os.getenv("ProgramFiles") .. '\\ATapeXP\\ekasui.cfg'
	
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom, 'can not create MSXML object')
	
	if xmlDom:load(pathCfg) then
		local nodes = xmlDom:SelectNodes('/EKASUI/@*')
		local res = {}
		while true do
			local node = nodes:nextNode()
			if not node then break end
			res[node.nodeName] = node.nodeValue
		end
		return res
	end
end

local function read_XmlC(file_path)
	local function pop_int(state, size)
		assert(#state.stream >= state.pos + size - 1)
		local bytes = table.pack(string.byte(state.stream, state.pos, state.pos+size-1))
		state.pos = state.pos + size
		
		local res = bytes[size]
		for i = size-1, 1, -1 do
			res = res * 0x100 + bytes[i]
		end
		if bytes[1] >= 0x80 then
			res = res - bit32.lshift(1, size*8)
		end
		return res
	end


	local function pop_string(state, length)
		assert(#state.stream + 1 >= state.pos + length)
		local res = string.sub(state.stream, state.pos, state.pos+length-1)
		state.pos = state.pos + length
		return res
	end

	local function pop_header(state)
		local res = {}
		res.idx = pop_int(state, 1)
		res.rail = pop_int(state, 1)
		res.channel = pop_int(state, 1)
		res.type = pop_int(state, 1)
		res.coord = pop_int(state, 4)
		res.value = pop_int(state, 4)
		return res
	end
			
	local file = io.open(file_path, 'rb')
	if not file then return {} end
	local state = {stream=file:read('*a'), pos=1}
	file:close()
	if #(state.stream) == 0 then return {} end
	assert(pop_string(state, 4) == 'XMLc')
	
	local values = {}	
	local idx2names = {}
	
	while #state.stream+1 > state.pos do
		--print(#state.stream, state.pos)
		local h = pop_header(state)
		--print(h.idx, h.rail, h.channel, h.type, h.coord, h.value)
		
		if h.type == 0 then 			-- HWS_CXML_INDEX_NAME
			local name = pop_string(state, h.value)
			assert(not idx2names[h.idx] or idx2names[h.idx] == name)
			idx2names[h.idx] = name
		elseif h.type == 2 then 		-- HWS_CXML_INDEXED_VALUE
			assert(idx2names[h.idx])
			h.name = idx2names[h.idx]
			h.type = nil
			h.idx = nil
			values[#values + 1] = h
		else
			assert()
		end
	end
	return values
end


local Temperature = OOP.class
{
	ctor = function(self, filename)
	end,
}



Driver = OOP.class
{
	ctor = function(self, psp_path, sum_path)
		self._passport = psp2table(psp_path)
		
		if not sum_path then
			sum_path = string.gsub(psp_path, '.xml', '.sum')
		end
		self._sum_path = sum_path
		
		self._gps = read_XmlC(string.gsub(psp_path, '.xml', '.gps'))
		--self._marks = read_sum_file(self._sum_path)
		
		_G.Driver = self
		_G.Passport = self._passport
		_G.EKASUI_PARAMS = read_EKASUI_cfg()
		self._guids = read_guids()
	end,
	
	GetMarks = function(self, filter)
		local g = filter and filter.GUIDS
		local mark_id = filter and filter.mark_id
		local marks = read_sum_file(self._sum_path, g, mark_id)
		return marks
	end,
	
	GetAppPath = function(self)
		local cd = io.popen"cd":read'*l'
		return cd:match('(.+\\)%S+')
	end,
	
	GetPathCoord = function(self, sys)
		local km = math.floor(sys / 1000000)
		local m = math.floor(sys / 1000) % 1000
		local mm = math.floor(sys) % 1000
		return km, m, mm
	end,
	
	GetSumTypeName = function(self, guid)
		return self._guids[string.upper(guid)] or tostring(guid)
	end,
	
	GetTemperature = function(self, rail, sys)
		assert(rail == 0 or rail == 1)
		local head = nil
		local target = nil
		for _, g in ipairs(self._gps) do
			if g.rail == rail+1 then
				if g.name == "TEMP_TARGET" then
					target = g.value / 10
				elseif	g.name == "TEMP_HEAD" then
					head = g.value / 10
				end
			end
			if g.coord > sys then
				break
			end
		end
		return {head=head, target=target}
	end,
	
	GetFrame = function(self, channel, sys, params)
		local path = string.format("c:\\out\\%s\\img\\%d_%d.jpg", Passport.NAME, sys, channel)
		return path
	end,

	GetRunTime = function(self, sys)
		local date = self._passport.DATE
		local year, month, day, hour, min = string.match(date, "(%d+):(%d+):(%d+):(%d+):(%d+)")
		local res = os.time({day=day, month=month, year=year, hour=hour, min=min, sec=0})
		return res
	end,

	GetGPS = function(self, sys)
		local k = 60*60*1000
		local lat = nil
		local lon = nil
		for _, g in ipairs(self._gps) do
			if g.name == "LAT_RAW" then
				lat = g.value / k
			elseif	g.name == "LON_RAW" then
				lon = g.value / k
			end
			if g.coord > sys then
				break
			end
		end
		return lat, lon
	end,
}

return Driver
