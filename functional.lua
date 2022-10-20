
local function list(gen)
    local res = {}
    while true do
        local element = gen()
        if element == nil then break end
        table.insert(res, element)
    end
    return res
end

local function imap(fn, array)
    local i = 0
    return function ()
        i = i + 1
        local obj = array[i]
        if obj ~= nil then
            return fn(obj)
        end
    end
end

local function map(fn, array)
    return list(imap(fn, array))
end

local function ifilter(fn, array)
    local i = 0
    return function ()
        while i < #array do
            i = i + 1
            local obj = array[i]
            if fn(obj) then
                return obj
            end
        end
    end
end

local function filter(fn, array)
    return list(ifilter(fn, array))
end

local function izip(...)
    local arrays = {...}
    local i = 0
    return function ()
        i = i + 1
        local row = {}
        for _, array in arrays do
            local obj = array[i]
            if type(obj) == "nil" then
                return
            end
            table.insert(row)
        end
        if not row then
            return
        end
        return table.unpack(row)
    end
end

local function zip(...)
    return list(izip(...))
end

-- ============================================================= --

return
{
    list = list,
    imap = imap,
    map = map,
    ifilter = ifilter,
    filter = filter,
    zip = zip,
    izip = izip,
}
