local lu = require('luaunit')

print(package.cpath)
package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'
print(package.cpath)

local sum_group_marks_sleepers = require 'sum_group_marks_sleepers'
local SleeperScanner = sum_group_marks_sleepers.SleeperScanner

function testSlepperHolderEmpty()
    local sc = SleeperScanner(150)
    sc:prepare()
    local cnt = 0
    for _ in sc:enum_sleepers() do cnt = cnt + 1 end
    lu.assertEquals(cnt, cnt)
end

function testSlepperHolderEnumSleepers()
    local sc = SleeperScanner(150)
    sc:insert(0)
    sc:insert(0, "0")
    sc:insert(0, "0")

    sc:insert(1000)

    sc:insert(2000, '2000')

    sc:insert(3000, '3000')
    sc:insert(3001, '3001')
    sc:insert(3000)

    sc:insert(1500)

    sc:insert(2000, '2001')

    sc:prepare()

    local coords = {}
    local defects = {}
    for coord, defect in sc:enum_sleepers() do
        table.insert(coords, coord)
        table.insert(defects, table.concat(defect, ','))
    end
    lu.assertEquals({2, 1000, 1500, 2001, 3002}, coords)
    lu.assertEquals("0,0;;;2000,2001;3000,3001", table.concat(defects, ";"))
end

function testSlepperHolderEnumGroups()
    local sc = SleeperScanner(150)
    sc:insert(1000)
    sc:insert(1100, "code1")
    sc:insert(1130)

    sc:insert(1500)

    sc:insert(2000, '2000')
    sc:insert(2500, '2500')
    sc:insert(3600)

    sc:insert(3000)
    sc:insert(3500)
    sc:insert(4500)

    sc:insert(5000, "5000")
    sc:insert(5300)
    sc:insert(5600, '5600')
    sc:insert(6000)

    sc:insert(6300, '6300')
    sc:insert(7000, '7000')

    sc:prepare()

    local groups = {}
    for group in sc:enum_defect_groups() do
        table.insert(groups, table.concat(group, ','))
    end
    lu.assertEquals("2000,2500;6300,7000", table.concat(groups, ";"))
end



os.exit( lu.LuaUnit.run() )
