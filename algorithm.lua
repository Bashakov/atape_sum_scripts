
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

-- разбивает массив на переекающиеся отрезки указанной длинны. enum_group({1,2,3,4,5}, 3) ->  {1,2,3}, {2,3,4}, {3,4,5}
local function enum_group(arr, len)
	local i = 0
	return function()
		i = i + 1
		if i + len <= #arr+1 then
			return table.unpack(arr, i, i + len)
		end
	end
end


local function sort(array, key_fn, inc)
    if type(inc) == "boolean" and not inc then
        inc = false
    else
        inc = true
    end
    if not key_fn then
        key_fn = function (o)
            return o
        end
    end

    assert(type(array) == 'table')
    assert(type(key_fn) == 'function')
	
	local keys = {}	-- массив ключей, который будем сортировать
	for i = 1, #array do
		local mark = array[i]
		local key = {key_fn(mark)}  -- собираем все значения
        key[#key+1] = i             -- добавляем порядковый номер
		keys[#keys+1] = key 	-- и вставим в таблицу ключей
	end

	assert(#keys == #array)

    -- сортируем массив с ключами
	table.sort(keys, function(t1, t2)  -- функция сравнения массивов, поэлементное сравнение
		for i = 1, #t1 do
			local a, b = t1[i], t2[i]
            local ta, tb = type(a), type(b)
            if ta < tb then return inc end
            if tb < ta then return not inc end
			if a < b then return inc end
			if b < a then return not inc end
		end
		return false
	end)

	local res = {}	-- сюда скопируем отметки в нужном порядке
	for i, key in ipairs(keys) do
		local pos = key[#key] -- номер отметки в изначальном списке мы поместили последним элементом ключа
		res[i] = array[pos] -- берем эту отметку и помещаем на нужное место
	end
	return res
end

-- проход по таблице в сортированном порядке
local function sorted(tbl, cmp)
	local keys = {}
	for n, _ in pairs(tbl) do table.insert(keys, n) end
	table.sort(keys, cmp)
	local i = 0
	return function()
		i = i + 1
		return keys[i], tbl[keys[i]]
	end
end

-- итератор разбивающий входной массив на массив массивов заданной длинны, последний может быть короче
-- split_chunks_iter(3, {1,2,3,4,5,6,6,7}) -> 1, {1,2,3}; 2, {4,5,6}; 3, {7}
local function split_chunks_iter(chunk_len, arr)
	assert(chunk_len > 0)
	local i = 0
	local n = 0
	return function()
		if i > #arr - 1 then
			return nil
		end

		local t = {}
		for j = 1, chunk_len do
			t[j] = arr[j+i]
		end
		i = i + chunk_len
		n = n + 1
		return n, t
	end
end

 -- разбивает входной массив на массив массивов заданной длинны, последний может быть короче
local function split_chunks(chunk_len, arr)
	assert(chunk_len > 0)
	local res = {}
	for i = 0, #arr - 1, chunk_len do
		local t = {}
		for j = 1, chunk_len do
			t[j] = arr[j+i]
		end
		res[#res + 1] = t
	end
	return res
end

-- поиск элемента в таблице
local function table_find(tbl, val)
    for i, item in ipairs(tbl) do
		if val == item then return i end
	end
end

-- создать таблицу из переданных аргументов, если аргумент таблица, то она распаковывается рекурсивно
local function table_merge(...)
	local res = {}

	for _, item in ipairs{...} do
		if type(item) == 'table' then
			local v = table_merge(table.unpack(item))
			for _, i in ipairs(v) do
				res[#res+1] = i
			end
		else
			res[#res+1] = item
		end
	end

	return res
end

local function reverse_array(arr)
	local i, j = 1, #arr
	while i < j do
		arr[i], arr[j] = arr[j], arr[i]
		i = i + 1
		j = j - 1
	end
end

local function lower_bound(array, value, pred)
	if not pred then
		pred = function(a,b) return a < b end
	end
    local count = #array
	local first = 1
    while count > 0 do
        local step = math.floor(count / 2)
		local i = first + step
        if pred(array[i], value) then
            first = i+1
            count = count - (step + 1)
        else
            count = step
		end
    end
    return first
end

local function upper_bound(array, value, pred)
	if not pred then
		pred = function(a,b) return a < b end
	end
    local count = #array
	local first = 1
    while count > 0 do
        local step = math.floor(count / 2)
		local i = first + step
        if not pred(value, array[i]) then
            first = i+1
            count = count - (step + 1)
        else
            count = step
		end
    end
    return first
end

local function equal_range(array, value, pred)
	return lower_bound(array, value, pred), upper_bound(array, value, pred)
end

local function starts_with(input, prefix)
	return #input >= #prefix and string.sub(input, 1, #prefix) == prefix
end

local function clean_array_dup_stable(arr)
	local res = {}
	local known = {}
	for _, val in pairs(arr) do
		if not known[val] then
			table.insert(res, val)
			known[val] = true
		end
	end
	return res
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
    sort = sort,
    sorted = sorted,
    enum_group = enum_group,
    split_chunks_iter = split_chunks_iter,
    split_chunks = split_chunks,
    table_find = table_find,
    table_merge = table_merge,
    reverse_array = reverse_array,
    lower_bound = lower_bound,
    upper_bound = upper_bound,
    equal_range = equal_range,
    starts_with = starts_with,
    clean_array_dup_stable = clean_array_dup_stable,
}
