local OOP = require 'OOP'
local xml_utils

local function _get_mark_id(mark)
    return mark and mark.prop and mark.prop.ID
end

local function _get_mark_xml_node(mark)
    if not xml_utils then
        xml_utils = require 'xml_utils'
    end
	local xml_str = mark.ext and mark.ext.RAWXMLDATA
	if xml_str and #xml_str > 0 then
		return xml_utils.load_xml_str(xml_str)
	end
end

local MarkXmlCache = OOP.class{
	ctor = function (self, max_size, get_prop_fn, get_key_fn)
		self._max_size = max_size
        self._get_key_fn = get_key_fn or _get_mark_id
        self._get_value_fn = get_prop_fn or _get_mark_xml_node
		self._items = {}
	end,

	get = function (self, mark)
		local key = self._get_key_fn(mark)
		if not key then return nil end

		local value = self:_get_cached(key)
		if not value then
			value = self._get_value_fn(mark)
			if value then self:_put_cache(key, value) end
		end
		return value
	end,

	clear = function (self)
		self._items = {}
	end,

--    __ipairs = function (self)
--        local i = #self._items + 1
--        return function ()
--            i = i - 1
--            local item = self._items[i]
--            if item then
--                return item[1], item[2]
--            end
--        end
--    end,

	_put_cache = function (self, key, value)
		for i = #self._items, 1, -1 do
			local item = self._items[i]
			if item[1] == key then
				if i ~= #self._items then
					table.remove(self._items, i)
					table.insert(self._items, item)
				end
				return
			end
		end
		if #self._items >= self._max_size then
			table.remove(self._items, 1)
		end
		table.insert(self._items, {key, value})
	end,

	_get_cached = function (self, key)
		for i = #self._items, 1, -1 do
			local item = self._items[i]
			if item[1] == key then
				return item[2]
			end
		end
	end,
}

return {
    MarkXmlCache = MarkXmlCache,
}