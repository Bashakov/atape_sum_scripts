dofile("tests\\setup_test_paths.lua")

local lu = require 'luaunit'
local test_report  = require 'local_data_driver'
local utils = require "utils"
local codecs = require 'process_utf8'
local alg = require "algorithm"

ATAPE = true -- disable in sum_list_pane testing
require "sum_list_pane"

-- ========================================================== 

local function split_file_name(path)
	return string.match(path, "([^/]-)%.([^.]+)$")
end

local function make_expected_file_path(list_name, data_name)
    list_name = string.gsub(list_name, '[\\/:%s]+', " ")
    data_name = split_file_name(data_name)
    local path = "test_data/list_pane/" .. list_name .. '.' .. data_name .. '.csv'
    return codecs.utf8_cp1251(path)
end

local function all_trim(s)
    return s:match( "^%s*(.-)%s*$" )
end

local function get_list_data(list_name, data_name)
    local csv_separator = ';'
    local res = {}

    test_report.Driver("test_data/" .. data_name)
    local columns = GetColumnDescription(list_name)
    local column_names = {}
    for i, col in ipairs(columns) do column_names[i] = col.name end
    table.insert(res, table.concat(column_names, csv_separator))
    local cnt_row = InitMark(list_name)
    for row = 1, cnt_row do
        local values = {}
        for col = 1, #columns do
            local text = GetItemText(row, col)
            text = all_trim(tostring(text or ''))
            values[col] = text
        end
        table.insert(res, table.concat(values, csv_separator))
    end
    return res
end

local function file2array(path)
    local lines = {}
    if utils.is_file_exists(path) then
        for line in io.lines(path) do table.insert(lines, line) end
    end
    return lines
end

local function array2file(path, lines)
    local f = assert(io.open(path, 'w+'))
    for _, line in ipairs(lines) do f:write(line, '\n') end
    f:close()
end

local function checkList(list_name, data_name)
    local expected_file_path = make_expected_file_path(list_name, data_name)
    local expected_data = file2array(expected_file_path)
    local actual_data = get_list_data(list_name, data_name)
    if #actual_data == 1 and #expected_data == 0 then
        -- no data, only header, skip
        return
    end
    for i = 1, math.max(#actual_data, #expected_data) do
        local actual_row = actual_data[i] or ''
        local expected_row = expected_data[i] or ''
        if actual_row ~= expected_row then
            array2file(expected_file_path .. '.actual', actual_data)
            local msg = string.format("on %d row for data: %s, filter [%s]", i, data_name, list_name)
            lu.assertEquals(actual_row, expected_row, msg)
        end
    end
end

-- ========================================================== 

function TestGetGroupNames()
    lu.assertEquals(GetGroupNames(), {
        "АвтоРаспознавание УЗ",
        "ВИДЕОРАСПОЗНАВАНИЕ",
        "Групповые дефекты",
        "ЖАТ",
        "НПУ",
        "Пользовательский фильтр",
        "РАСПОЗНАВАНИЕ МАГНИТНОГО",
        "СТЫКИ",
        "Тест:видео",
        "Шпалы",
    })
end

function TestGetFilterNames()
    lu.assertEquals(GetFilterNames("no_group"),  {})

    lu.assertEquals(GetFilterNames(""),  {
        "I Все ограничения скорости",
        "I Стыковые зазоры",
        "I Отсутствие болтов в стыках",
        "Тест нетиповые болты",
        "I Кустовые дефекты",
        "I Дефекты накладок",
        "II Маячные отметки",
        "Маячные шпалы",
        "III Соединитель: штепсельный",
        "III Соединитель: приварной",
        "III Соединители и перемычки",
        "III Устройства ЖАТ",
        "III Шпалы: эпюра",
        "III Шпалы: дефекты",
        "III Шпалы: разворот",
        "III Дефектные скрепления",
        "Ненормативный объект",
        "Горизонтальные уступы",
        "Поверхностные дефекты",
        "Запуски распознавания",
        "Слепые зазоры",
        "Стрелочные переводы",
        "Тест УКСПС",
        "Магнитные Стыки",
        "Нпу",
        "Глобальный фильтр",
        "Введенные пользователем",
        "УЗ Дефекты",
        "УЗ дефекты Шейка\\подошва Все",
        "УЗ дефекты Шейка\\подошва 1 уровень",
        "УЗ Дефекты Головка Все",
        "УЗ Дефекты Головка 1 уровень",
        "УЗ Дефекты Головка 2 уровень"
    })

    lu.assertEquals(GetFilterNames("АвтоРаспознавание УЗ"),  {
        "УЗ Дефекты",
        "УЗ дефекты Шейка\\подошва Все",
        "УЗ дефекты Шейка\\подошва 1 уровень",
        "УЗ Дефекты Головка Все",
        "УЗ Дефекты Головка 1 уровень",
        "УЗ Дефекты Головка 2 уровень"
    })
    lu.assertEquals(GetFilterNames("ВИДЕОРАСПОЗНАВАНИЕ"),  {
        "I Все ограничения скорости",
        "I Стыковые зазоры",
        "I Отсутствие болтов в стыках",
        "I Кустовые дефекты",
        "I Дефекты накладок",
        "II Маячные отметки",
        "III Соединители и перемычки",
        "III Устройства ЖАТ",
        "III Шпалы: эпюра",
        "III Шпалы: дефекты",
        "III Шпалы: разворот",
        "III Дефектные скрепления",
        "Ненормативный объект",
        "Слепые зазоры",
        "Глобальный фильтр",
        "Введенные пользователем"
    })
    lu.assertEquals(GetFilterNames("Групповые дефекты"),  {"I Кустовые дефекты"})
    lu.assertEquals(GetFilterNames("ЖАТ"),  {
        "III Соединители и перемычки",
        "III Устройства ЖАТ"
    })
    lu.assertEquals(GetFilterNames("НПУ"),  {"Нпу", "Глобальный фильтр"})
    lu.assertEquals(GetFilterNames("Пользовательский фильтр"),  {"Глобальный фильтр"})
    lu.assertEquals(GetFilterNames("РАСПОЗНАВАНИЕ МАГНИТНОГО"),  {"Магнитные Стыки"})
    lu.assertEquals(GetFilterNames("СТЫКИ"),  {
        "I Все ограничения скорости",
        "I Стыковые зазоры",
        "I Отсутствие болтов в стыках",
        "Слепые зазоры",
        "Магнитные Стыки",
        "Введенные пользователем"
    })
    lu.assertEquals(GetFilterNames("Тест:видео"),  {
        "Тест нетиповые болты",
        "Маячные шпалы",
        "III Соединитель: штепсельный",
        "III Соединитель: приварной",
        "Горизонтальные уступы",
        "Поверхностные дефекты",
        "Запуски распознавания",
        "Стрелочные переводы",
        "Тест УКСПС",
    })
    lu.assertEquals(GetFilterNames("Шпалы"),  {
        "III Шпалы: эпюра",
        "III Шпалы: дефекты",
        "III Шпалы: разворот"
    })
end

function TestListData()
    local source_data = {
        "fragment1.xml",
        "fragment2.xml",
        "fragment3.xml",
        "fragment4.xml",
        "fragment5.xml",
        "fragment6.xml",
        "fragment7.xml",
        "fragment8.xml",
    }
    local skip_filters = {
        "Глобальный фильтр",
    }
    local filters = GetFilterNames("")
    for _, data_name in ipairs(source_data) do
        for _, list_name in ipairs(filters) do
            if not alg.table_find(skip_filters, list_name) then
                checkList(list_name, data_name)
            end
        end
    end
    
end

os.exit( lu.LuaUnit.run() )
