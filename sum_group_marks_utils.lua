local mark_helper = require 'sum_mark_helper'
local funcional = require 'functional'



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
    local function f(mark)
        return bit32.btest(mark.prop.RailMask, rail)
    end
    return funcional.filter(f, marks)
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
}
