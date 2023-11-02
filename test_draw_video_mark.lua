local lu = require "luaunit"

package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'

local utils = require "utils"
local alg = require "algorithm"
local OOP = require "OOP"
local TYPES = require "sum_types"
require "draw_video_mark"

-- ======================================================= --

local function read_file(path)
    local f = assert(io.open(path, 'rb'))
    local res = f:read('*a')
    if res:sub(1,3) == '\xef\xbb\xbf' then
        res = res:sub(4)
    end
    f:close()
    return res
end

local function file2array(path)
    local lines = {}
    if utils.is_file_exists(path) then
        for line in io.lines(path) do
            if #line > 0 then
                lines[#lines + 1] = line
            end
        end
    end
    return lines
end

local function array2file(path, lines)
    local f = assert(io.open(path, 'w+'))
    for _, line in ipairs(lines) do f:write(line, '\n') end
    f:close()
end

local function obj2str(obj, sep)
    local r = {}
    for n, v in alg.sorted(obj) do table.insert(r, string.format("%s=%s", n, v)) end
    return '{' .. table.concat(r, sep or ',') .. '}'
end

local function color2str(...)
    local clr = {...}
    if type(clr[1]) == "table" then
        return obj2str(clr[1], ',')
    end
    return obj2str(clr)
end

local actions = {}
local function addAction(fmt, ...) table.insert(actions, string.format(fmt, ...)) end

Drawer = OOP.class{
    prop = {
        lineWidth = function (self, lineWidth) addAction("prop.lineWidth: %d", lineWidth) end,
        fillColor = function (self, ...) addAction("prop.fillColor: %s", color2str(...)) end,
        lineColor = function (self, ...) addAction("prop.lineColor: %s", color2str(...)) end,
    },
    fig = {
        line = function (self, x1, y1, x2, y2) addAction("fig.line: %d %d %d %d", x1, y1, x2, y2) end,
        polygon = function (self, points) addAction("fig.polygon: %s", table.concat(points, ",")) end,
        rectangle = function (self, x1, y1, x2, y2) addAction("fig.polygon: %d %d %d %d", x1, y1, x2, y2) end,
        ellipse = function (self, cx, cy, rx, ry) addAction("fig.ellipse: %d %d %d %d",  cx, cy, rx, ry) end,
    },
    text = {
        font = function (self, params) addAction("text.font: %s", obj2str(params)) end,
        alignment = function (self, hor, vert) addAction("text.alignment: %s %s", hor, vert) end,
        calcSize = function (self, text)
            addAction("text.calcSize: %s", text)
            return 10, 10
        end,
        multiline = function (self, params) addAction("text.multiline: %s", obj2str(params)) end
    }
}

Convertor = {
    GetPointOnFrame = function (self, cur_frame_coord, item_frame, x, y)
        local r = x + (item_frame-cur_frame_coord)
        addAction("Convertor.GetPointOnFrame: %d %d, %d %d -> %d", cur_frame_coord, item_frame, x, y, r)
        return r, y
    end,
    ScalePoint = function (self, x, y)
        addAction("Convertor.ScalePoint: %d %d", x, y)
        return x, y
    end,
    SysCoordToOffset = function (self, frame, coord)
        local r = coord - frame
        addAction("Convertor.SysCoordToOffset: %d %d -> %d", frame, coord, r)
        return r
    end,
}

local function draw(ch_num, frame_coord, mark)
    actions = {}
    local frame = {
        channel = ch_num, 
        coord = {raw=frame_coord,},
        size = {current = {x=512, y = 512}, }
    }
    Draw(nil, frame, {mark})
    return actions
end

local function checkActions(expt_file)
    local expected_actions = file2array(expt_file)
    if table.concat(expected_actions, '') ~= table.concat(actions, '') then
        array2file(expt_file .. '.actual', actions)
        lu.assertEquals(expected_actions, actions)
    end
end

-- ======================================================= --

function TestGetMarkGuids()
    local guids = GetMarkGuids()
    table.sort(guids)
    lu.assertEquals(guids, {
        "{0860481C-8363-42DD-BBDE-8A2366EFAC90}",
        "{13A7906C-BBFB-4EB3-86FA-FA74B77F5F35}",
        "{1DEFC4BD-FDBB-4AC7-9008-BEEB56048131}",
        "{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}",
        "{28C82406-2773-48CB-8E7D-61089EEB86ED}",
        "{3401C5E7-7E98-4B4F-A364-701C959AFE99}",
        "{3601038C-A561-46BB-8B0F-F896C2130001}",
        "{3601038C-A561-46BB-8B0F-F896C2130002}",
        "{3601038C-A561-46BB-8B0F-F896C2130003}",
        "{3601038C-A561-46BB-8B0F-F896C2130004}",
        "{3601038C-A561-46BB-8B0F-F896C2130005}",
        "{3601038C-A561-46BB-8B0F-F896C2130006}",
        "{41486CAC-EBE9-46FF-ACCA-041AFAFFC531}",
        "{46DB5861-E172-49A7-B877-A9CA11700101}",
        "{46DB5861-E172-49A7-B877-A9CA11700102}",
        "{46DB5861-E172-49A7-B877-A9CA11700103}",
        "{46DB5861-E172-49A7-B877-A9CA11700201}",
        "{46DB5861-E172-49A7-B877-A9CA11700202}",
        "{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}",
        "{53987511-8176-470D-BE43-A39C1B6D12A3}",
        "{54188BA4-E88A-4B6E-956F-29E8035684E9}",
        "{64B5F99E-75C8-4386-B191-98AD2D1EEB1A}",
        "{75F1CB97-7BE2-4A00-9E90-6B183DDF8B9C}",
        "{7EF92845-226D-4D07-AC50-F23DD8D53A19}",
        "{B6BAB49E-4CEC-4401-A106-355BFB2E0001}",
        "{B6BAB49E-4CEC-4401-A106-355BFB2E0002}",
        "{B6BAB49E-4CEC-4401-A106-355BFB2E0011}",
        "{B6BAB49E-4CEC-4401-A106-355BFB2E0012}",
        "{B6BAB49E-4CEC-4401-A106-355BFB2E0021}",
        "{B6BAB49E-4CEC-4401-A106-355BFB2E0022}",
        "{BB144C42-8D1A-4FE1-9E84-E37E0A47B074}",
        "{CBD41D28-9308-4FEC-A330-35EAED9FC801}",
        "{CBD41D28-9308-4FEC-A330-35EAED9FC802}",
        "{CBD41D28-9308-4FEC-A330-35EAED9FC803}",
        "{CBD41D28-9308-4FEC-A330-35EAED9FC804}",
        "{CBD41D28-9308-4FEC-A330-35EAED9FC805}",
        "{D3736670-0C32-46F8-9AAF-3816DE00B755}",
        "{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}",
        "{DE548D8F-4E0C-4644-8DB3-B28AE8B17431}",
        "{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",
        "{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",
        "{EBAB47A8-0CDC-4102-B21F-B4A90F9D873A}",
        "{EE2FD277-0776-429F-87C4-F435B9A6F760}"
    })
end

function TestDrawBeacon()
    local mark = {
        prop = {Guid=TYPES.VID_BEACON_INDT},
        ext = {RAWXMLDATA = read_file("test_data/beacon1.xml")},
    }
    _G.Passport= {INCREASE == '1'}

    draw(17, 3810632, mark)
    checkActions("test_data/draw/beacon1.17.3810632.txt")

    draw(17, 3811632, mark)
    checkActions("test_data/draw/beacon1.17.3811632.txt")

    draw(18, 3810632, mark)
    checkActions("test_data/draw/beacon1.18.3810632.txt")
    lu.assertEquals(actions, {})
end

function TestDrawRailGap()
    local mark = {
        prop = {Guid=TYPES.VID_BEACON_INDT},
        ext = {RAWXMLDATA = read_file("test_data/gap3.xml")},
    }
    draw(18, 2187341, mark)
    checkActions("test_data/draw/gap3.18.2187341.txt")

    mark.ext.RAWXMLDATA = read_file("test_data/gap8.xml")
    draw(17, 149166118, mark)
    checkActions("test_data/draw/gap8.17.149166118.txt")
end

function  TestSleeper1()
    local mark = {
        prop = {
            Guid=TYPES.SLEEPER, 
            ChannelMask=0,
            SysCoord=2344347},
        ext = {
            RAWXMLDATA = read_file("test_data/sleeper1.xml"),
            DEFECT_CODES='DEFECT_CODES'
        },
    }
    draw(17, 2344013, mark)
    checkActions("test_data/draw/sleeper1.17.2344013.txt")
    draw(19, 2344013, mark)
    checkActions("test_data/draw/sleeper1.19.2344013.txt")
end

function  TestSleeper2()
    local mark = {
        prop = {
            Guid=TYPES.SLEEPER, 
            ChannelMask=0,
            SysCoord=2344347},
        ext = {
            RAWXMLDATA = read_file("test_data/sleeper2.xml"),
            DEFECT_CODES='DEFECT_CODES'
        },
    }
    draw(17, 2344013, mark)
    checkActions("test_data/draw/sleeper2.21.2284621.txt")
end

function  TestTurnout()
    local mark = {
        prop = {
            Guid=TYPES.TURNOUT_VIDEO,
        },
        ext = {
            RAWXMLDATA = read_file("test_data/Turnout.xml"),
        },
    }
    draw(17, 40993779, mark)
    checkActions("test_data/draw/Turnout.17.40993779.txt")
end

function  TestUKSPS()
    local mark = {
        prop = {
            Guid=TYPES.TURNOUT_VIDEO,
        },
        ext = {
            RAWXMLDATA = read_file("test_data/uksps.xml"),
        },
    }
    draw(21, 7511856, mark)
    checkActions("test_data/draw/uksps.21.7511856.txt")
    draw(22, 7511856, mark)
    checkActions("test_data/draw/uksps.22.7511856.txt")
end

os.exit( lu.LuaUnit.run() )
