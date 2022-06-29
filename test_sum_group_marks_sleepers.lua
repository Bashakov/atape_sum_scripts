local lu = require('luaunit')

package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'


local sum_group_marks_sleepers = require 'sum_group_marks_sleepers'
local SleeperScanner = sum_group_marks_sleepers.SleeperScanner

function testNO()
    lu.assertEquals(1, 1)
end

os.exit( lu.LuaUnit.run() )
