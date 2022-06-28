local lu = require('luaunit')

--print(package.cpath)
package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'
--print(package.cpath)

local group_utils = require 'sum_group_marks_utils'

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


os.exit( lu.LuaUnit.run() )
