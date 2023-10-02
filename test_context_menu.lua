local lu = require("luaunit")

package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'
ATAPE = true -- disable dubag code

local iup = require 'iuplua'
iup.SetGlobal('UTF8MODE', 1)

local algorithm = require 'algorithm'
local TYPES = require 'sum_types'
local context_menu = require 'sum_context_menu'


local function read_file(path)
    local f = assert(io.open(path, 'rb'))
    local res = f:read('*a')
    if res:sub(1,3) == '\xef\xbb\xbf' then
        res = res:sub(4)
    end
    f:close()
    return res
end

-- ===================================================================  

function TestItems()
    local mark = {
        prop = {Guid = TYPES.VID_INDT_1},
        ext = {RAWXMLDATA = read_file('test_data/gap4.xml')},
    }
    local items = context_menu.GetMenuItems(mark)
    local names = algorithm.map(function (item) return type(item) == "table" and item.name or '' end, items)
    names = algorithm.filter(function (n) return #n > 0 and not algorithm.starts_with(n, "Сценарий") end, names)
    lu.assertEquals(names, {
        "Показать XML распознавания",
        "Редактировать ширину зазора",
        "Редактировать наличие болтов",
        "Удалить отметку",
        "Сформировать выходную форму видеофиксации",
        "Настройка сценария установки ПОВ",
        "Отметка: ",
        "Подтвердить отметку",
        "Подтвердить отметку не по сценарию установки",
        "Отвергнуть дефектность (без удаления отметки)",
        "Ведомость оценки стыка"
    })
end

function Tes1tEditBolt()
    local mark = {
        prop = {Guid = TYPES.VID_INDT_1},
        ext = {RAWXMLDATA = read_file('test_data/gap2.xml')},
        Save = function (self)
            print(self.ext.RAWXMLDATA)
        end,
    }
    context_menu.EditBold(mark)
    -- lu.assertEquals(1,1)
end


os.exit(lu.LuaUnit.run())
