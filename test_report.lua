require "luacom"
local sqlite3 = require "lsqlite3"
local OOP = require "OOP"

local function read_sum_file(file_path, guids)
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
			m.MARKID as ID, hex(t.GUID) as Guid, m.SYSCOORD as SysCoord, m.LENGTH as Len, m.RAILMASK as RailMask, d.DESCRIPTION as Description
		FROM SumrkMainTable as m
		JOIN SumrkMarkTypeTable as t ON m.TYPEID = t.TYPEID
		LEFT JOIN SumrkDescTable as d ON m.MARKID = d.MARKID
		WHERE ( m.INNERFLAGS & 1) = 0 
		]]
	if tids then
		str_stat = str_stat .. ' AND t.TYPEID in (' .. tids .. ') '
	end
	
	local st = assert( db:prepare(str_stat) )
	local marks = {}
	while st:step() == sqlite3.ROW do
		local prop = st:get_named_values()
		prop.Guid = format_guid(prop.Guid)
		local mark = {
			prop = prop,
			ext = {},
		}
		marks[mark.prop.ID] = mark
	end
	
	for ext_name in db:urows('SELECT NAME FROM SumrkPropDescTable') do
		--print(ext_name)
		for markid, value in db:urows('SELECT * FROM SumrkXtndParamTable_' .. ext_name) do
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
	xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
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


Driver = OOP.class
{
	ctor = function(self, psp_path, sum_path)
		self._passport = psp2table(psp_path)
		
		if not sum_path then
			sum_path = string.gsub(psp_path, '.xml', '.sum')
		end
		self.marks = read_sum_file(sum_path)
		
		_G.Driver = self
		_G.Passport = self._passport
	end,
	
	GetMarks = function(self, filter)
		if filter and filter.GUIDS then
			local fg = {}
			for _, g in ipairs(filter.GUIDS) do	
				fg[g] = true 
			end

			local res = {}
			for _, m in ipairs(self.marks) do
				if fg[m.prop.Guid] then
					res[#res+1] = m
				end
			end
			return res
		else
			return self.marks 
		end
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
	
	GetTemperature = function(self, rail, sys)
		return {head=0, target=0}
	end,
	
	GetFrame = function(self, channel, sys, params)
		local path = string.format("c:\\out\\%s\\img\\%d_%d.jpg", Passport.NAME, sys, channel)
		return path
	end,

}

return Driver





