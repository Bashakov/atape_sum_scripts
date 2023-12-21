dofile("tests\\setup_test_paths.lua")

local lu = require("luaunit")
local utils = require 'utils'

function testRound()
    lu.assertEquals(utils.round(-123.45, -2), -100)
    lu.assertEquals(utils.round(-123.45, -1), -120)
    lu.assertEquals(utils.round(-123.45, 0), -123)
    lu.assertEquals(utils.round(-123.45, 0), -123)
    lu.assertEquals(utils.round(-123.45, 1), -123.4)
    lu.assertEquals(utils.round(-123.45, 2), -123.45)
end

function testGetSelectedBits()
    lu.assertEquals(utils.GetSelectedBits(0), {})
    lu.assertEquals(utils.GetSelectedBits(1), {0})
    lu.assertEquals(utils.GetSelectedBits(2), {1})
    lu.assertEquals(utils.GetSelectedBits(0x10), {4})
    lu.assertEquals(utils.GetSelectedBits(0xf1), {0, 4, 5, 6, 7})
    lu.assertEquals(utils.GetSelectedBits(0x12345678), {3, 4, 5, 6, 9, 10, 12, 14, 18, 20, 21, 25, 28})
end

function TestEscape()
    lu.assertEquals(utils.escape('hi\nevery\0one'), "hi\\x0Aevery\\x00one")
end

os.exit(lu.LuaUnit.run())
