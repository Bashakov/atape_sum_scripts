local DEFECT_CODES = require 'report_defect_codes'
local TYPES = require 'sum_types'
local OOP = require 'OOP'
local group_utils = require 'sum_group_marks_utils'
local mark_helper = require 'sum_mark_helper'

local printf  = function(fmt, ...)	print(string.format(fmt, ...)) end
local CHECK = group_utils.CHECK

-- =========================================== --

local FASTENER_PLACE =
{
    CURVE = 1,
    STRAIGHT = 2,
    UNLINED = 3,
    SWITCH = 4,
}

local function fastener_group_to_code(group_len, place)
    if place == FASTENER_PLACE.CURVE then
        if     group_len == 3 then return DEFECT_CODES.FASTENER_DEFECT_CURVE_GROUP_3
        elseif group_len == 4 then return DEFECT_CODES.FASTENER_DEFECT_CURVE_GROUP_4
        elseif group_len >= 5 then return DEFECT_CODES.FASTENER_DEFECT_CURVE_GROUP_5
        end
    end
    if place == FASTENER_PLACE.STRAIGHT then
        if     group_len == 3 then return DEFECT_CODES.FASTENER_DEFECT_STRAIGHT_GROUP_3
        elseif group_len == 4 then return DEFECT_CODES.FASTENER_DEFECT_STRAIGHT_GROUP_4
        elseif group_len == 5 then return DEFECT_CODES.FASTENER_DEFECT_STRAIGHT_GROUP_5
        elseif group_len >= 6 then return DEFECT_CODES.FASTENER_DEFECT_STRAIGHT_GROUP_6
        end
    end
    if place == FASTENER_PLACE.UNLINED then
        if     group_len == 3 then return DEFECT_CODES.FASTENER_DEFECT_UNLINED_GROUP_3
        elseif group_len == 4 then return DEFECT_CODES.FASTENER_DEFECT_UNLINED_GROUP_4
        elseif group_len >= 5 then return DEFECT_CODES.FASTENER_DEFECT_UNLINED_GROUP_5
        end
    end
    if place == FASTENER_PLACE.SWITCH then
        if     group_len == 2 then return DEFECT_CODES.FASTENER_DEFECT_SWITCH_GROUP_2
        elseif group_len == 3 then return DEFECT_CODES.FASTENER_DEFECT_SWITCH_GROUP_3
        elseif group_len == 4 then return DEFECT_CODES.FASTENER_DEFECT_SWITCH_GROUP_4
        elseif group_len >= 5 then return DEFECT_CODES.FASTENER_DEFECT_SWITCH_GROUP_5
        end
    end
end


local FastenerGroups = OOP.class
{
    NAME = 'Скрепления',
    GUID = '{B6BAB49E-4CEC-4401-A106-355BFB2E0021}',
    FastenerMaxDinstanceToSleeperJoin = 100,
    FastenerMaxGroupDistance = 1000000/1840 * 1.5,

    PARAMETERS = {
        {rail=1},
        {rail=2}
    },

    ctor = function (self)
        self.marks = {}                 -- хранилище найденных отметок
        self._switchers = group_utils.Switchers()   -- стрелки
        self._defect_mark_ids = {}      -- таблица id отметки - дефектность
    end,

    _is_fastener_defect = function (self, mark)
        local defect = self._defect_mark_ids[mark.prop.ID]
        if defect == nil then
            if mark.prop.Guid == TYPES.FASTENER_USER then
                defect =
                    mark.ext.CODE_EKASUI == DEFECT_CODES.FASTENER_MISSING_CLAMP_BOLT[1] or
                    mark.ext.CODE_EKASUI == DEFECT_CODES.FASTENER_MISSING_CLAMP[1] or
                    mark.ext.CODE_EKASUI == DEFECT_CODES.FASTENER_MISSING_BOLT[1]
            else
                local prm = mark_helper.GetFastenetParams(mark)
                local FastenerFault = prm and prm.FastenerFault
                defect = not not FastenerFault and FastenerFault > 0
            end
            self._defect_mark_ids[mark.prop.ID] = defect
        end
        assert(type(defect) == 'boolean', type(defect))
        return defect
    end,

    LoadMarks = function (self, param, dlg)
        assert(param and param.rail)
        local guids_fasteners =
        {
            TYPES.FASTENER,	-- Скрепление
            TYPES.FASTENER_USER,	-- Скрепления(Пользователь)
        }
        local progress = group_utils.make_progress_cb(dlg, string.format('загрузка скреплений рельс %d', param.rail), 123)
        local marks = group_utils.loadMarks(guids_fasteners)
        marks = group_utils.filter_rail(marks, param.rail)

        -- https://bt.abisoft.spb.ru/view.php?id=617
        local function is_pair_defect(mark, neighbour)
            if neighbour then
                local dist = math.abs(neighbour.prop.SysCoord - mark.prop.SysCoord)
                if dist < self.FastenerMaxDinstanceToSleeperJoin then
                    return self:_is_fastener_defect(neighbour)
                end
            end
            return false
        end

        -- удалим хорошие отметки, если с другой стороны рельса есть дефектная
        local res = {}
        for i, mark in ipairs(marks) do
            if not progress(i, #marks) then return {} end
            if self:_is_fastener_defect(mark) then
                -- если дефектная, то добавляем
                table.insert(res, mark)
            else
                -- иначе посмотрим на соседей
                if is_pair_defect(mark, marks[i-1]) or
                   is_pair_defect(mark, marks[i+1]) then
                    -- парная дефектная, значит эту пропускаем
                    printf('skip %d/%d, on found pair defect', mark.prop.RailMask, mark.prop.SysCoord)
                else
                    -- нет парных, или они не дефектные. добавляем
                    table.insert(res, mark)
                end
            end
        end
        printf('skip %d fasteners, leave %d', #marks - #res, #res)
        return res
    end,

    Check = function (self, get_near_mark)
        local mark = get_near_mark(0)
        if not self:_is_fastener_defect(mark) then
            -- если отметка хорошая, то пропускаем ее и закрываем группу
            return CHECK.REFUTE
        end
        -- иначе посмотрим расстояние до предыдущей отметки
        local prev = get_near_mark(-1)
        if prev then
            local dist = math.abs(prev.prop.SysCoord - mark.prop.SysCoord)
            if dist > self.FastenerMaxGroupDistance then
                --[[ если больше чем максимально возможное между шпалами,
                значит что возможно хорошие скрепления не писались,
                пред группу надо закрывать и начинать новую ]]
                return CHECK.CLOSE_ACCEPT
            end
        end
        -- иначе добавляем отметку в группу
        return CHECK.ACCEPT
    end,

    OnGroup = function (self, group, param)
        assert(param and param.rail)

        if #group >= 2 then
            local inside_switch = self._switchers:overalped(group[1].prop.SysCoord, group[#group].prop.SysCoord)

            local defect = fastener_group_to_code(#group, inside_switch and FASTENER_PLACE.SWITCH or FASTENER_PLACE.STRAIGHT)
            local code_ekasui = defect and defect[1]
            if code_ekasui then
                local mark = group_utils.makeMark(
                    self.GUID,
                    group[1].prop.SysCoord,
                    group[#group].prop.SysCoord - group[1].prop.SysCoord,
                    param.rail,
                    #group
                )
                mark.ext.CODE_EKASUI = code_ekasui
                table.insert(self.marks, mark)
            end
            -- print('Fastener', #group, table.unpack(map(function (mark) return mark.prop.SysCoord end, group)))
        end
    end,
}


-- =================================================== --

return
{
    FastenerGroups = FastenerGroups,
}