﻿local lu = require 'luaunit'

package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'

ATAPE = true -- disable in sum_list_pane testing
require "sum_list_pane"

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
        "Стрелочные переводы",
    })
    lu.assertEquals(GetFilterNames("Шпалы"),  {
        "III Шпалы: эпюра",
        "III Шпалы: дефекты",
        "III Шпалы: разворот"
    })
end

os.exit( lu.LuaUnit.run() )