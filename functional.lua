
-- конвератция генератора в список
local function list(gen)
    local res = {}
    while true do
        local element = gen()
        if element == nil then break end
        table.insert(res, element)
    end
    return res
end

-- генератор применяет функцию к каэдому элементу массива
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

-- применяет функцию к каэдому элементу массива и возвращает новый массив
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

-- возвращает элементы удовлетворяющие фильтру
local function filter(fn, array)
    return list(ifilter(fn, array))
end

local function zip_impl(...)
    local arrays = {...}
    local i = 0
    return function ()
        i = i + 1
        local row = {}
        for j, array in ipairs(arrays) do
            local obj = array[i]
            if type(obj) == "nil" then
                return
            end
            row[j] = obj
        end
        return row
    end
end

--[[
объединение элементов списков, для совместного прохода
    for a, b in izip({1, 2}, {'a', 'b'}) do
        print(a, b)
    end
]]
local function izip(...)
    local gen = zip_impl(...)
    return function ()
        local r = gen()
        if r then
            return table.unpack(r)
        end
    end
end

-- объединение элементов списков в новый список 
-- zip({1,2,3}, {'a', 'b', 'c'}) -> {{1, 'a'}, {2, 'b'}, {3, 'c'}}
local function zip(...)
    return list(zip_impl(...))
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
