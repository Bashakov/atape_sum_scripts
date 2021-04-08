
local test_report = require('test_report')
test_report('D:\\ATapeXP\\Main\\494\\video\\[494]_2017_06_08_12.xml')

local marks = Driver:GetMarks{mark_id=20000015}

require 'draw_video_mark'

if false then
    local guids = GetMarkGuids()
    for _, g in ipairs(guids) do print(g) end
end

local drawer = {
    prop = {
        lineWidth = function (self, lineWidth) end,
        fillColor = function (self, clr)  end,
        lineColor = function (self, clr)  end,
    },
    fig = {
        polygon = function (self, points) end,
    },
    text = {
        font = function (aprams) end,
        alignment = function (hor, vert) end,
        calcSize = function (self, text)
            return 10, 10
        end,
        multiline = function (params) end
    }
}

Convertor = {
    GetPointOnFrame = function (self, cur_frame_coord, item_frame, x, y)
        return x, y
    end,
    ScalePoint = function (self, x, y)
        return x, y
    end
}

local frame = {
    channel = 21,
    coord = {
        raw=118713,
    },
}


Draw(drawer, frame, marks)