dofile("tests\\setup_test_paths.lua")

local lu = require('luaunit')


local sum_group_marks_sleepers = require 'sum_group_marks_sleepers'
local SleeperScanner = sum_group_marks_sleepers.SleeperScanner

function testNO()
    lu.assertEquals(1, 1)
end

os.exit( lu.LuaUnit.run() )
