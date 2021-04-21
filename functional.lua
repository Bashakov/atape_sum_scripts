
local function list(itrable)
    local res = {}
    while true do
        local element = itrable()
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

-- ============================================================= --

return
{
    list = list,
    imap = imap,
    map = map,
    ifilter = ifilter,
    filter = filter
}
