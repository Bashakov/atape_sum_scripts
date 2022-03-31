require "luacom"
local sqlite3 = require "lsqlite3"
local OOP = require "OOP"
local GUID = require "guids"

local printf  = function(fmt, ...)	print(string.format(fmt, ...)) end
local sprintf = function(fmt, ...) return string.format(fmt, ...)  end

local function binsearch(tbl, value, fcompval, allow_nearest)
	fcompval = fcompval or function(v) return v end
	local iStart, iEnd, iMid = 1, #tbl, 1
	while iStart < iEnd do
		iMid = math.floor( (iStart+iEnd)/2 )
		local value2 = fcompval( tbl[iMid] )
		if value == value2 then
			return iMid
		elseif value < value2 then
			iEnd = iMid - 1
		else
			iStart = iMid + 1
		end
	end

	if #tbl > 0 and allow_nearest then
		return iMid
	end
end

local function _make_new_mark(prop)
	local mark = {
		prop = prop or {},
		ext = {},
		user = {},
		Delete = function(self)
			printf('Delete %d  %s %d %d', self.prop.ID, self.prop.Guid, self.prop.RailMask, self.prop.SysCoord)
		end,
		Save = function(self)
			printf('Save %s %s %s %d', self.prop.ID, self.prop.Guid, self.prop.RailMask, self.prop.SysCoord)
		end
	}
	return mark
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

local Stream = OOP.class{
	ctor = function (self, file_path, error_if_no_file)
		self.pos = 1
		self.stream = ''
		local file = io.open(file_path, 'rb')
		if file then
			self.stream = file:read('*a')
			file:close()
		elseif error_if_no_file then
			error('Can no open file:' .. file_path)
		end
	end,

	left = function (self)
		return #self.stream + 1 - self.pos
	end,

	if_empty = function (self)
		return self:left() <= 0
	end,

	pop_num = function(self, size)
		assert(#self.stream >= self.pos + size - 1)
		local bytes = table.pack(string.byte(self.stream, self.pos, self.pos+size-1))
		self.pos = self.pos + size

		local res = bytes[size]
		for i = size-1, 1, -1 do
			res = res * 0x100 + bytes[i]
		end
		if bytes[1] >= 0x80 then
			res = res - bit32.lshift(1, size*8)
		end
		return res
	end,

	pop_string = function (self, length)
		assert(#self.stream + 1 >= self.pos + length)
		local res = string.sub(self.stream, self.pos, self.pos+length-1)
		self.pos = self.pos + length
		return res
	end
}



local function read_XmlC(file_path)
	local stream = Stream(file_path)
	if stream:left() == 0 then return {} end
	assert(stream:pop_string(4) == 'XMLc')


	local values = {}
	local idx2names = {}

	while not stream:if_empty() do
		--print(#state.stream, state.pos)
		local h = {}
		h.idx = stream:pop_num(1)
		h.rail = stream:pop_num(1)
		h.channel = stream:pop_num(1)
		h.type = stream:pop_num(1)
		h.coord = stream:pop_num(4)
		h.value = stream:pop_num(4)
		--print(h.idx, h.rail, h.channel, h.type, h.coord, h.value)

		if h.type == 0 then 			-- HWS_CXML_INDEX_NAME
			local name = stream:pop_string(h.value)
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

local Deltas = OOP.class{
	ctor = function (self, psp_path, start_km, start_pk, increase)
		self.items = {}
		local filename = string.gsub(psp_path, '%.xml$', '')
		local stream
		for chunk = 0, 10 do
			local schunk = chunk == 0 and '' or string.format('(%d)', chunk)
			local path = filename .. schunk .. '.dlt'
			stream = Stream(path)
			if stream:if_empty() then
				break
			end
			while not stream:if_empty() do
				table.insert(self.items, {
					coord = stream:pop_num(4),
					delta = stream:pop_num(4)
				})
			end
		end
		stream = nil
		self.start_km = start_km
		self.start_pk = start_pk
		self.increase = increase
	end,

	by_coord = function (self, coord)
		local item = nil
		for _, cur_item in ipairs(self.items) do
			if cur_item.coord > coord then break end
			item = cur_item
		end

		if item then
			-- CRegFileBasket::TranslateToPathCoord
			local nMmFromStart = coord + item.delta

			local start_pk = self.start_pk ~= 0 and self.start_pk - 1 or self.start_pk
			local realPath = (self.start_km * 10 + start_pk) * 100000

			if self.increase ~= '0' then
				realPath = realPath + nMmFromStart
			else
				realPath = realPath - nMmFromStart
			end

			local MMinKM = 1000*1000

			local m_mm = realPath % MMinKM;
			local km = math.floor(realPath / MMinKM);
			if m_mm < 0 then
				m_mm = m_mm + MMinKM
				km = km - 1
			end
			local mm = math.floor (m_mm % 1000)
			local m =  math.floor (m_mm / 1000)
			return km, m, mm
		else
			local km = math.floor(coord / 1000000)
			local m = math.floor(coord / 1000) % 1000
			local mm = math.floor(coord) % 1000
			return km, m, mm
		end
	end,
}


local function read_temerature(gps)
	local res = {}
	for _, g in ipairs(gps) do
		if g.name == "TEMP_TARGET" or g.name == "TEMP_HEAD" then
			if not res[g.rail] then res[g.rail] = {} end
			if not res[g.rail][g.name] then res[g.rail][g.name] = {} end
			table.insert(res[g.rail][g.name], {g.coord, g.value / 10})
		end
	end
	for _, r in pairs(res) do
		for _, rr in pairs(r) do
			table.sort(rr, function	(a,b) return a[1] < b[1] end)
		end
	end
	return res
end


local SumMarks = OOP.class
{
	ctor = function (self, file_path, sys_range)
		assert(string.sub(file_path, -4) == '.sum')
		self:_load_types(file_path)
		self._sys_range = sys_range or {}
	end,

	GetMarks = function(self, filter)
		local tids
		if filter and filter.GUIDS then
			tids = {}
			for _, g in ipairs(filter.GUIDS) do
				local tid = self._guid2tid[g]
				if tid then
					table.insert(tids, tid)
				end
			end
			tids = table.concat(tids, ',')
		end
		local FromSys = filter and filter.FromSys or self._sys_range[1]
		local ToSys = filter and filter.ToSys or self._sys_range[2]
		local mark_id = filter and filter.mark_id
		local marks = {}
		for _, db in ipairs(self._db) do
			self:_read_marks(db, marks, tids, mark_id, {FromSys, ToSys})
		end
		local res = {}
		for _, mark in pairs(marks) do
			res[#res+1] = mark
		end
		return res
	end,

	_read_marks = function (self, db, marks, tids, mark_id, sys_range)
		assert(db:execute("CREATE TEMP TABLE IF NOT EXISTS MIDS (MID INT);"))
		assert(db:execute("DELETE FROM MIDS;"))

		local fill_MIDS = [[
			INSERT INTO
				MIDS
			SELECT
				m.MARKID
			FROM
				SumrkMainTable as m
			WHERE ( m.INNERFLAGS & 1) = 0
			]]
		if tids then
			fill_MIDS = fill_MIDS .. ' AND m.TYPEID in (' .. tids .. ') '
		end
		if mark_id then
			fill_MIDS = fill_MIDS .. ' AND m.MARKID == ' .. mark_id .. ' '
		end
		if sys_range and sys_range[1] then
			fill_MIDS = fill_MIDS .. ' AND m.SYSCOORD >= ' .. sys_range[1] .. ' '
		end
		if sys_range and sys_range[2] then
			fill_MIDS = fill_MIDS .. ' AND m.SYSCOORD <= ' .. sys_range[2] .. ' '
		end
		assert(db:execute(fill_MIDS))

		local str_stat = [[
		SELECT
			m.MARKID as ID,
			m.TYPEID as Guid,
			m.SYSCOORD as SysCoord,
			m.LENGTH as Len,
			m.RAILMASK as RailMask,
			m.ChannelMask as ChannelMask,
			d.DESCRIPTION as Description
		FROM
			SumrkMainTable as m
		LEFT JOIN
			SumrkDescTable as d
			ON m.MARKID = d.MARKID
		WHERE m.MARKID in (SELECT MID FROM MIDS);
		]]

		local st = db:prepare(str_stat)
		if not st then
			error(db:errmsg())
		end
		while st:step() == sqlite3.ROW do
			local prop = st:get_named_values()
			prop.Guid = self._tid2guid[prop.Guid]
			marks[prop.ID] = _make_new_mark(prop)
		end

		for ext_name in db:urows('SELECT NAME FROM SumrkPropDescTable') do
			--print(ext_name)
			local req_params = 'SELECT * FROM SumrkXtndParamTable_' .. ext_name ..
			' WHERE MARKID in (SELECT MID FROM MIDS);'

			for markid, value in db:urows(req_params) do
				if marks[markid] then
					marks[markid].ext[ext_name] = value
				end
			end
		end
	end,

	_load_types = function(self, file_path)
		local nums = {}
		self._tid2guid = {}
		self._guid2tid = {}

		local db = sqlite3.open(file_path)
		local sqlType = 'SELECT typeid, name, guid FROM SumrkMarkTypeTable'
		for typeid, name, guid in db:urows(sqlType) do
			local g = GUID.bin2str(guid, true)
			-- print(typeid, name, g)
			self._tid2guid[typeid] = g
			self._guid2tid[g] = typeid

			local m = string.match(name, 'group_(%d+)') or '0'
			nums[m] = true
		end
		db:close()

		self._db = {}
		for num, _ in pairs(nums) do
			local file = file_path
			if num ~= '0' then
				file = string.sub(file_path, 1, -4) .. num .. string.sub(file_path, -4)
			end

			local db = sqlite3.open(file)
			if db:prepare('SELECT * FROM SumrkVersion') then -- check db not empty
				table.insert(self._db, db)
			end
		end
	end,
}


local Driver = OOP.class
{
	ctor = function(self, psp_path, sum_path, load_marks_range)
		self._passport = psp2table(psp_path)

		if not sum_path then
			sum_path = string.gsub(psp_path, '%.xml$', '.sum')
		end
		self._sum = SumMarks(sum_path, load_marks_range)

		self._gps = read_XmlC(string.gsub(psp_path, '%.xml$', '.gps'))
		self._temerature = read_temerature(self._gps)
		self.deltas = Deltas(psp_path, self._passport.START_KM, self._passport.START_PK, self._passport.INCREASE)

		_G.Driver = self
		_G.Passport = self._passport
		_G.EKASUI_PARAMS = read_EKASUI_cfg()
		self._guids = read_guids()
	end,

	GetMarks = function(self, filter)
		return self._sum:GetMarks(filter)
	end,

	GetAppPath = function(self)
		local cd = io.popen"cd":read'*l'
		return cd:match('(.+\\)%S+')
	end,

	GetPathCoord = function(self, sys)
		return self.deltas:by_coord(sys)
	end,

	GetSumTypeName = function(self, guid)
		return self._guids[string.upper(guid)] or tostring(guid)
	end,

	GetTemperature = function(self, rail, sys)
		assert(rail == 0 or rail == 1)
		local head = nil
		local target = nil
		local rail_temp = self._temerature[rail+1]
		if rail_temp then
			local i_t = binsearch(rail_temp.TEMP_TARGET or {}, sys, function(v) return v[1] end, true)
			if i_t then
				target = rail_temp.TEMP_TARGET[i_t][2]
			end
			local i_h = binsearch(rail_temp.TEMP_HEAD   or {}, sys, function(v) return v[1] end, true)
			if i_h then
				target = rail_temp.TEMP_HEAD[i_h][2]
			end
		end
		return {head=head, target=target}
	end,

	GetFrame = function(self, channel, sys, params)
		local text = sprintf('Test GetFrame:\\n  channel = %d\\n  system = %d', channel, sys)
		for n, v in pairs(params) do
			text = text .. sprintf('\\n  %s = %s', n, v)
		end

		local width = params.width or 600
		local height = params.height or 400

		local cmd = sprintf('ImageMagick_convert.exe convert -size %dx%d xc:skyblue -fill black -gravity West -annotate 0,0 "%s" ', width, height, text)
		if params.base64 then
			cmd = cmd .. ' INLINE:JPG:-'
			local f = assert(io.popen(cmd, 'r'))
			local data = assert(f:read('*a'))
			f:close()
			local hdr = 'data:image/jpeg;base64,'
			if data:sub(1, #hdr) ~= hdr then
				error( 'bad output file header: [' .. data:sub(1, #hdr) .. ']')
			end
			return data:sub(#hdr+1)
		else
			local path = os.tmpname() .. ".jpg"
			cmd = cmd .. path
			if not os.execute(cmd) then
				error('command [' .. cmd .. '] failed')
			end
			return path
		end
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

	NewSumMark = function (self)
		return _make_new_mark()
	end,

	SaveMarks = function (self, marks)
		for _, mark in ipairs(marks) do
			mark:Save()
		end
	end
}

Driver.GUID = GUID

return Driver
