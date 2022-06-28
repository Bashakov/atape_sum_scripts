local mark_helper = require 'sum_mark_helper'
local funcional = require 'functional'
local OOP = require 'OOP'
local TYPES = require 'sum_types'


local function make_progress_cb(dlg, title, step)
    step = step or 1
    return function (cur, all)
        if cur % 300 == 0 then collectgarbage("collect") end
        local text = string.format('%s: %d/%d', title, cur, all)
        if cur % step == 0 and dlg and not dlg:step(cur / all, text) then
            return false
        end
        return true
    end
end

local function filter_rail(marks, rail)
    assert(rail == 1 or rail == 2)
    return funcional.filter(function (mark)
        return bit32.btest(mark.prop.RailMask, rail)
    end, marks)
end

local function filter_pov_operator(marks, pov_operator)
    assert(pov_operator == 0 or pov_operator == 1)
    local function f(mark)
        local accept_operator = (mark.ext.POV_OPERATOR == 1)  -- может быть 0 или отсутствовать (nil)
        return (pov_operator == 1) == accept_operator
    end
    return funcional.filter(f, marks)
end

local function loadMarks(guids, pov_filter, dlg)
    local marks = Driver:GetMarks{GUIDS=guids, ListType='all'}
    marks = mark_helper.sort_mark_by_coord(marks)
	if pov_filter then
		marks = pov_filter(marks, dlg)
    end
    return marks
end

local function makeMark(guid, coord, lenght, rail_mask, object_count)
    local mark = Driver:NewSumMark()

	mark.prop.SysCoord = coord
	mark.prop.Len = lenght
	mark.prop.RailMask = rail_mask + 8   -- video_mask_bit
	mark.prop.Guid = guid
	mark.prop.ChannelMask = 0
	mark.prop.MarkFlags = 0x01 -- MarkFlags.eIgnoreShift

	mark.ext.GROUP_DEFECT_COUNT = object_count

    -- https://bt.abisoft.spb.ru/view.php?id=600#c2643
    -- При формировании групповых тоже им автоматом давать 0000
    mark.ext.POV_OPERATOR = 0
    mark.ext.POV_EAKSUI   = 0
    mark.ext.POV_REPORT   = 0
    mark.ext.POV_REJECTED = 0

    -- sumPOV.UpdateMarks(mark, false)
    return mark
end

local CHECK = {
    ACCEPT          = 1,    -- добавить отметку в группу
    REFUTE          = 2,    -- пропустить отметку и закрыть группу
    SKIP            = 3,    -- пропустить отметку
    ACCEPT_CLOSE    = 4,    -- добавить отметку в группу и закрыть группу
    CLOSE_ACCEPT    = 5,    -- закрыть пред группу и добавить отметку в новую группу
}


--[[ defect_type должен быть классом с 3 методами:
- LoadMarks: строит список отметок, которые нужно проверить
- Check: проверить отметку на дефектность, должна вернуть значение из таблицы CHECK
- OnGroup: обработать полученную группу
]]
local function scanGroupDefect(defect_type, dlg, pov_filter)
    local params = defect_type.PARAMETERS or {1}
    local search_group_progress = make_progress_cb(dlg, string.format('%s: обработка', defect_type.NAME), 23)
    for _, param in ipairs(params) do
        local marks = defect_type:LoadMarks(param, dlg, pov_filter)

        local group = {}
        for i, mark in ipairs(marks) do
            if i % 100 == 0 then collectgarbage("collect") end

            if not search_group_progress(i, #marks) then return end

            local function get_near_mark(index) return marks[i+index] end
            local result = defect_type:Check(get_near_mark)
            --print(i, accept, mark.prop.SysCoord)
            if result == CHECK.ACCEPT then
                table.insert(group, mark)
            elseif result == CHECK.REFUTE then
                defect_type:OnGroup(group, param)
                group = {}
            elseif result == CHECK.SKIP then
                -- skip
            elseif result == CHECK.ACCEPT_CLOSE then
                table.insert(group, mark)
                defect_type:OnGroup(group, param)
                group = {}
            elseif result == CHECK.CLOSE_ACCEPT then
                defect_type:OnGroup(group, param)
                group = {mark}
            else
                assert(false, 'Unknow value' .. tostring(result))
            end
        end
        if #group > 0 then
            defect_type:OnGroup(group, param)
        end
    end
end


local function remove_old_marks(guids_to_delete, dlg)
    local marks = loadMarks(guids_to_delete)
    for i, mark in ipairs(marks) do
        mark:Delete()
        if i % 17 == 1 and dlg then
            local text = string.format('Удаление %d / %d отметок', i, #marks)
            if not dlg:step(i / #marks, text) then
                return
            end
        end
    end
end

local function save_marks(marks, dlg)
    for i, mark in ipairs(marks) do
        mark:Save()
        if i % 17 == 1 and dlg then
            local text = string.format('Сохранение %d / %d отметок', i, #marks)
            if not dlg:step(i / #marks, text) then
                return false
            end
        end
    end
end

-- список стрелок
local Switchers = OOP.class
{
    ctor = function (self, marks)
        if not marks then
            local switch_guids = {
                TYPES.STRELKA1, TYPES.STRELKA2, TYPES.STRELKA3, TYPES.STRELK4
            }
            -- найти все стрелки
            marks = Driver:GetMarks{ListType='all', GUIDS=switch_guids}
        end

        self._items = {}
        for i = 1, #marks do
            local mark = marks[i]
            local prop = mark.prop
            table.insert(self._items, {from=prop.SysCoord, to=prop.SysCoord + prop.Len, id=prop.ID})
            table.sort(self._items, self._cmp)
        end
    end,

    -- проверить что координата находится в стрелке
    overalped = function(self, c1, c2)
        assert(c1 <= c2)

        local i1 = mark_helper.lower_bound(self._items, {from=c1}, self._cmp)
        local i2 = mark_helper.lower_bound(self._items, {from=c2}, self._cmp)
        for i = i1-1, i2 do
            local switch = self._items[i]
            if switch then
                local l = math.max(c1, switch.from)
                local r = math.min(c2, switch.to)
                if l <= r then
                    return switch.id
                end
            end
        end
        return nil
    end,

    _cmp = function (a, b)
        return a.from < b.from
    end
}

-- список координат стыков для определения кода дефекта шпал
local Joints =  OOP.class{
    ctor = function (self, dlg, scan_dist)
        local video_joints_juids =
        {
            TYPES.VID_INDT_1,	    -- Стык(Видео)
            TYPES.VID_INDT_2,	    -- Стык(Видео)
            TYPES.VID_INDT_3,	    -- СтыкЗазор(Пользователь)
            TYPES.VID_INDT_ATS,	    -- АТСтык(Видео)
            TYPES.RAIL_JOINT_USER,	-- Рельсовые стыки(Пользователь)
            TYPES.VID_ISO,          -- ИзоСтык(Видео)
        }
        local joints = loadMarks(video_joints_juids, nil, dlg)
        local coords = {}
        for _, mark in ipairs(joints) do
            table.insert(coords, mark.prop.SysCoord)
        end
        table.sort(coords)
        self._coords = coords
        self._scan_dist = scan_dist
    end,

    check_group = function (self, group)
        local c1 = group[1] - self._scan_dist
        local c2 = group[#group] + self._scan_dist
        local i1 = mark_helper.lower_bound(self._coords, c1)
        local i2 = mark_helper.lower_bound(self._coords, c2)
        return i1 < i2
    end,
}

-- ===============================================

return
{
    filter_rail = filter_rail,
    filter_pov_operator = filter_pov_operator,
    make_progress_cb = make_progress_cb,
    loadMarks = loadMarks,
    makeMark = makeMark,
    CHECK = CHECK,
    scanGroupDefect = scanGroupDefect,
    remove_old_marks = remove_old_marks,
    save_marks = save_marks,
    Switchers = Switchers,
    Joints = Joints,
}
