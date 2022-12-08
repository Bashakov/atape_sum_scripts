require "luacom"
local OOP = require "OOP"

local NoteRec = OOP.class
{
	ctor = function (self, node_rec)
		self._node = node_rec
	end,

	_get_header_val = function (self, name)
		local xpath = string.format("@%s", name)
		local res = self._node:SelectSingleNode(xpath)
		return res and res.nodeValue
	end,

	_get_header_int = function (self, name)
		return tonumber(self:_get_header_val(name))
	end,

	_get_field_val = function (self, inner_name)
		local xpath = string.format("FIELD[@INNER_NAME='%s']/@VALUE", inner_name)
		local res = self._node:SelectSingleNode(xpath)
		return res and res.nodeValue
	end,

	_get_field_int = function (self, inner_name)
		return tonumber(self:_get_field_val(inner_name))
	end,

	GetNoteID = function (self)
		return self:_get_header_int('SYST')
	end,

	GetPath = function (self)
		return self:_get_field_int('KM'), self:_get_field_int('M'), self:_get_field_int('MM')
	end,

	GetIncluded = function (self)
		local v = self:_get_header_val('INCLUDED')
		return v ~= 'FALSE'
	end,

	GetPlacement = function (self)
		return self:_get_field_val("PLACEMENT") or ''
	end,

	GetAction = function (self)
		return self:_get_field_val("ACTION") or ''
	end,

	GetDescription = function (self)
		return self:_get_field_val("DESCRIPTION") or ''
	end,

    GetLeftCoord = function (self)
        return tonumber(self:_get_header_val("MM")) or 0
    end,

    GetMarkCoord = function (self)
        return tonumber(self:_get_header_val("MARK_COORD")) or 0
    end,

    GetScale = function (self)
        return tonumber(self:_get_header_val("SCALE")) or 0
    end,

	GetThread = function (self)
		return self:_get_field_val('THREAD')
	end,

	GetRailMask = function (self)
		local thread = self:GetThread()
		local first_left = tonumber(Passport.FIRST_LEFT) == 1
		local mask = 0
		if string.find('лЛlL', thread.sub(1,1)) then
			mask = first_left and 1 or 2
		end
		if string.find('пПrR', thread.sub(1,1)) then
			mask = first_left and 2 or 1
		end
		return mask
	end,

	GetDefectCode = function (self)
		return self:_get_field_val('DEFECT_CODE')
	end,

	GetSpeedLimit = function (self)
		return self:_get_field_int('NUM_OTV')
	end,

	IsODR = function (self)
		return self:GetIncluded() and self:GetAction() == "Замена"
	end,

	IsDR = function (self)
		return self:GetIncluded() and self:GetAction() ~= "Замена"
	end,
}

local function xml2ntb(xmlDom)
	local nodes_record = xmlDom:SelectNodes('NOTEBOOK/RECORD')
	local res = {}
	while true do
		local node_rec = nodes_record:nextNode()
		if not node_rec then break end
		local r = NoteRec(node_rec)
		res[#res+1] = r
	end
	return res
end

local function make_dom()
	local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	return assert(xmlDom, 'Can not create MSXML object')
end

local function load_str(str)
	local xmlDom = make_dom()
	assert(xmlDom:loadXML(str), "can not load xml")
	return xml2ntb(xmlDom)
end

local function load_file(path_psp)
	local path_ntb = string.gsub(path_psp, '%.xml$', '.ntb')
	local xmlDom = make_dom()
	assert(xmlDom:load(path_ntb), "can not open xml file: " .. path_ntb)
    return xml2ntb(xmlDom)
end


return
{
    load_file = load_file,
    load_str = load_str,
}
