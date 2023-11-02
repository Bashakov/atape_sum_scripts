


local function sprintf (s, ...)
	assert(s)
	local args = {...}
	local ok, res = pcall(string.format, s, table.unpack(args))
	if  not ok then
		assert(false, res)  -- place for setup breakpoint
	end
	return res
end

local function printf (s,...)
    return print(sprintf(...))
end

local function errorf(s,...)
    error(sprintf(s, ...))
end

local function round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

-- получить номера установленных битов, вернуть массив с номерами
local function GetSelectedBits(mask)
	local res = {}
	for i = 0, 31 do
		local t = bit32.lshift(1, i)
		if bit32.btest(mask, t) then
			table.insert(res, i)
		end
	end
	return res
end



-- поверхностное копирование
local function shallowcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- глубокое копирование
local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function dump_obj(o)
	if type(o) == 'table' then
	   local s = '{ '
	   for k,v in pairs(o) do
		  if type(k) ~= 'number' then k = '"'..k..'"' end
		  s = s .. '['..k..'] = ' .. dump_obj(v) .. ','
	   end
	   return s .. '} '
	else
	   return tostring(o)
	end
end
 

local function escape(s, ptrn)
	ptrn = ptrn or '[%c%s]'
	local res = string.gsub(s, ptrn, function(c)
		return string.format('\\x%02X', string.byte(c))
	end)
	return res
end

local function GetUtcOffset()
	local ts = 86000 * 5
	local cur, utc = os.date("*t", ts), os.date("!*t", ts)
	local diff = (cur.day - utc.day) * 24 + (cur.hour - utc.hour)
	return diff
end

local function is_file_exists(path)
	local f = io.open(path, 'rb')
	if f then f:close() end
	return f
end

-- ============================================================== --

return {
    sprintf = sprintf,
    printf = printf,
    errorf = errorf,
    round = round,
    GetSelectedBits = GetSelectedBits,
    shallowcopy = shallowcopy,
    deepcopy = deepcopy,
    dump_obj = dump_obj,
    escape = escape,
	is_file_exists = is_file_exists,
}