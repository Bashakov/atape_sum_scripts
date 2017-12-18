socket = require "socket"
require "luacom"

local dump_path = 'C:\\1\\[494]_2017_06_08_12\\dump.lua'
dofile(dump_path)

os.sleep = function(sec)
	socket.select(nil, nil, sec)
end

function Passport2Table(psp_path)						-- открыть xml паспорт и сохранить в таблицу его свойства
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


-- Passport = Passport2Table('C:\\1\\[480]_2013_11_09_14\\[480]_2013_11_09_14.xml')
Passport = data.Passport
marks = data.marks

local sys2path_coord = {}

Driver = 
{
	GetMarks = function()
		for _, m in ipairs(marks) do
			sys2path_coord[m.prop.SysCoord] = m.path
		end
		return marks
	end	,
	
	GetAppPath = function()
		local cd = io.popen"cd":read'*l'
		return cd:match('(.+\\)%S+')
	end,
	
	GetPathCoord = function(self, sys)
		t = sys2path_coord[sys] 
		if t then 
			return table.unpack(t)
		end
		return 0, 0, 0
	end,
	
	GetTemperature = function(self, rail, sys)
		return {head=0, target=0}
	end,
	
	GetFrame = function(self, channel, sys, params)
		local path = string.format("c:\\out\\%s\\img\\%d_%d.jpg", Passport.NAME, sys, channel)
		return  path
	end,
}


dofile('sum_report.lua')

--MakeReport("Ведомость болтовых стыков")
--MakeReport("Сохранить в Excel")
--MakeReport("Ведомость Зазоров")
--MakeReport("Ведомость ненормативных объектов")
--MakeReport("Ведомость сварной плети")
-- MakeReport("Ведомость болтовых стыков ЕКСУИ")
MakeReport("Ведомость болтовых стыков|Excel")