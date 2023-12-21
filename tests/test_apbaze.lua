dofile("tests\\setup_test_paths.lua")

local lu = require "luaunit"

local apbase = require "ApBaze"
local local_driver = require "local_data_driver"

_G.EKASUI_PARAMS = local_driver.read_EKASUI_cfg()

function TestVelocityTable()

    local vt = apbase.VelocityTable()
    vt:load("110000122897", "1")

    local search = function (km, m)
        local item = vt:find(km, m)
        return item and {item.BEGIN_KM, item.BEGIN_M, item.END_KM, item.END_M} or {}
    end

    lu.assertEquals(search(1, 74), {})
    lu.assertEquals(search(1, 75), {1,75, 1,910})
    lu.assertEquals(search(1, 76), {1,75, 1,910})
    lu.assertEquals(search(1, 909), {1,75, 1,910})
    lu.assertEquals(search(1, 910), {1,75, 1,910})
    lu.assertEquals(search(1, 911), {1,910, 2,101})

    lu.assertEquals(search(22, 402), {22,401, 23,1018})
    lu.assertEquals(search(23, 1018), {22,401, 23,1018})
    lu.assertEquals(search(23, 1019), {})
    lu.assertEquals(search(24, 0), {24,1, 24,201})
    lu.assertEquals(search(24, 200), {24,1, 24,201})

    lu.assertEquals(search(650, 164), {650,101, 650,164})

    lu.assertEquals(search(650, 165), {})

    lu.assertEquals(vt:format(1, 74), '')
    lu.assertEquals(vt:format(1, 909), 'сапс 40/лст 40/25/25')
    lu.assertEquals(vt:format(72, 120), 'сапс 220/лст 160/140/90')
    lu.assertEquals(vt:format(643, 510), '120/80')
end

os.exit(lu.LuaUnit.run())
