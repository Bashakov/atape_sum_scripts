local lu = require('luaunit')

--print(package.cpath)
package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'
--print(package.cpath)

local group_utils = require 'sum_group_marks_utils'

-- ========================================================== --

function testSwitchers()
    local function make_switcher(coord, len, i)
        return {
            prop = {
                ID = i,
                SysCoord = coord,
                Len = len,
            }
        }
    end

    local marks = {
        make_switcher(1200000, 30000, 3),
        make_switcher(2000000, 30000, 4),
        make_switcher(1100000, 30000, 2),
        make_switcher(1000000, 30000, 1),
    }

    local switchers = group_utils.Switchers(marks)
    lu.assertEquals(nil, switchers:overalped(     10,      20))
    lu.assertEquals(1  , switchers:overalped(      0, 5000000))
    lu.assertEquals(nil, switchers:overalped( 999990,  999999))
    lu.assertEquals(1  , switchers:overalped( 999990, 1000000))
    lu.assertEquals(1  , switchers:overalped(1000000, 1000000))
    lu.assertEquals(1  , switchers:overalped(1000000, 1000010))
    lu.assertEquals(1  , switchers:overalped(1000000, 2000010))
    lu.assertEquals(nil, switchers:overalped(1050000, 1050010))
    lu.assertEquals(2  , switchers:overalped(1100000, 1100010))
    lu.assertEquals(2  , switchers:overalped(1050000, 1150000))
    lu.assertEquals(2  , switchers:overalped(1050000, 1150000))
    lu.assertEquals(nil, switchers:overalped(1999998, 1999998))
    lu.assertEquals(4  , switchers:overalped(2000000, 2000000))
    lu.assertEquals(4  , switchers:overalped(2030000, 2030000))
    lu.assertEquals(nil, switchers:overalped(2030001, 2030001))
    lu.assertEquals(nil, switchers:overalped(5000000, 6000000))

    switchers = group_utils.Switchers({})
    lu.assertEquals(nil, switchers:overalped(0,   0))
    lu.assertEquals(nil, switchers:overalped(0, 100))
end

function testDefectJoiner()
    local defects = {
        {0, false},
        {2, "1"},
        {10, '10'},
        {12, '12'},
        {20, '20'},
        {21, false},
        {22, false},
        {23, false},
        {24, '24'},
        {30, false},
        {40, false},
        {50, '50'},
        {60, '60'},
    }
    local res = {}
    local dj = group_utils.DefectJoiner(5, function (c, ds)
        table.insert(res, {c, ds})
    end)
    for _, cd in ipairs(defects) do
        dj:push(cd[1], cd[2])
    end
    dj:flash()
    lu.assertEquals({
        {1, {'1'}},
        {11, {'10', '12'}},
        {22, {'20', '24'}},
        {30, {}},
        {40, {}},
        {50, {'50'}},
        {60, {'60'}},
    }, res)
end

function testGroupJoiner()
    local objs = {
        {0, false},
        {10, true},
        {11, true},
        {15, true},
        {20, true},
        {40, true},
        {60, true},
        {70, true},
        {75, false},
        {80, true},
        {90, true},
        {120,true},
    }
    local res = {}
    local gj = group_utils.GroupJoiner(10, function (g)
        table.insert(res, g)
    end)
    for _, obj in ipairs(objs) do
        gj:push(obj[1], obj[2])
    end
    gj:flash()
    lu.assertEquals({
        {10, 11, 15, 20},
        {60, 70},
        {80, 90},
    }, res)
end

function testGroupMaker()
    local marks = {
        {0, false},
        {2, "1"},
        {10, '10'},
        {12, '12'},
        {20, '20'},
        {21, false},
        {22, false},
        {23, false},
        {24, '24'},
        {30, false},
        {40, false},
        {50, '50'},
        {60, '60'},
    }
    local gm = group_utils.GroupMaker(15, 5)
    for _, mark in ipairs(marks) do
        gm:insert(mark[1], mark[2])
    end
    local res = {}
    for group in gm:enum_defect_groups() do
        table.insert(res, group)
    end
    lu.assertEquals({
        {1, 11, 22},
        {50, 60},
    }, res)
end


function testGroupMaker2()
    local sc = group_utils.GroupMaker(1000000/1840 * 1.5, 150)
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

    local groups = {}
    for group in sc:enum_defect_groups() do
        table.insert(groups, table.concat(group, ','))
    end
    lu.assertEquals("2000,2500;6300,7000", table.concat(groups, ";"))
end

-- ========================================================== --

os.exit( lu.LuaUnit.run() )
