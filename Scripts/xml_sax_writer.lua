local OOP = require "OOP"


local function encode(value)
	value = string.gsub(value, "&", "&amp;") -- '&' -> "&amp;"
	value = string.gsub(value, "<", "&lt;") -- '<' -> "&lt;"
	value = string.gsub(value, ">", "&gt;") -- '>' -> "&gt;"
	--value = string.gsub (value, "'", "&apos;");	-- '\'' -> "&apos;"
	value = string.gsub(value, '"', "&quot;") -- '"' -> "&quot;"
	-- replace non printable char -> "&#xD;"
	value =
		string.gsub(
		    value,
                "([^%w%&%;%p%\t% ])",
            function(c)
                return string.format("&#x%X;", string.byte(c))
                --return string.format("&#x%02X;", string.byte(c))
                --return string.format("&#%02d;", string.byte(c))
            end
	)
	return value
end

local WriterImpl = OOP.class{
    ctor = function (self, dst, indention)
        self._indention = indention
        self._dst = dst
        self._cur_node = {}
        self._first = true
    end,

    start_node = function (self, name, attr)
        local s = self:_get_indent() .. "<" .. encode(name)
        for n, v in pairs(attr or {}) do
            s = s .. ' ' .. encode(n) .. '="' .. encode(v) .. '"'
        end
        s = s .. ">"
        self._dst(s)
        table.insert(self._cur_node, name)
    end,

    end_node = function (self, name, add_newline)
        assert(table.remove(self._cur_node) == name)
        local s = ''
        if add_newline then
            s = self:_get_indent()
        end
        s = s .. "</"  .. name .. ">"
        self._dst(s)
    end,

    add_text = function (self, text)
        self._dst(text, #self._cur_node)
    end,

    _get_indent = function (self)
        local res = ""
        if not self._first and self._indention then
            res = "\n" .. string.rep(' ', #self._cur_node)
        end
        self._first = false
        return res
    end
}

local SaxWriter = OOP.class {
	ctor = function(self, dst, indention)
		self._writer = WriterImpl(dst, indention)
	end,

	add_node = function(self, name, attr, scope)
        local add_newline = false
        self._writer:start_node(name, attr)
        if type(scope) == "string" or type(scope) == "number" then
            self._writer:add_text(tostring(scope))
        end
        if type(scope) == "function" then
            scope(self)
            add_newline = true
        end
        self._writer:end_node(name, add_newline)
	end,
}

return SaxWriter
