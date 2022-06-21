--[[
https://bt.abisoft.spb.ru/view.php?id=600#c2554

Dmitry Alexeyev	(участник)

2020-08-07 20:12

Логика вырисовывается следующая в крайне упрощенном варианте.
Вводится новые типы групповых отметок для зазоров(нулевых),
скреплений, шпал - автоматические и ручные, всего 6 получается.

Автоматические групповые отметки создаются на основании уже
распознанных автоматически - пункт меню ("Сформировать групповые отметки").

Автоматические групповые отметки не являются подтвержденными и следуют обычным правилам подтверждения.
Ручные отметки ставятся с указанием количества либо протяженности.
Оператор может нарисовать отметку длинную покрывающую все дефекты, если сможет,
но принципе достаточно и короткой с указанием количества шпал и скреплений.

При выводе картинки используется максимальное значение из ширины нарисованного дефекта и введенной длины количества.

Для нулевых зазоров ручной режим необязателен.
Оператор будет подтверждать каждый нулевой зазор.
"Сформировать групповые отметки" для нулевых будет действовать особо.

Все подтвержденные нулевые зазоры формируют подтвержденную групповую отметку.
Все неподтвержденные нулевые зазоры формируют неподтвержденную групповую отметку.

Формирование картинки для нулевых либо все, но при такой логике можно слить только кадры нулевых (без рельсов межу ними)
]]

--require("mobdebug").start()

local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local luaiup_helper = require 'luaiup_helper'
local sumPOV = require "sumPOV"
require 'ExitScope'
local TYPES = require 'sum_types'
local group_utils = require 'sum_group_marks_utils'
local gruop_sleepers = require 'sum_group_marks_sleepers'

local printf  = function(fmt, ...)	print(string.format(fmt, ...)) end
local sprintf = function(fmt, ...) return string.format(fmt, ...)  end
local CHECK = group_utils.CHECK

-- список стрелок
local Switchers = OOP.class{

    ctor = function (self)
        local switch_guids = {
            "{19253263-2C0B-41EE-8EAA-000000100000}",
            "{19253263-2C0B-41EE-8EAA-000000200000}",
            "{19253263-2C0B-41EE-8EAA-000000400000}",
            "{19253263-2C0B-41EE-8EAA-000000800000}",
        }
        -- найти все стрелки
        local marks = Driver:GetMarks{ListType='all', GUIDS=switch_guids}
        self._items = {}
        for i = 1, #marks do
            local mark = marks[i]
            local prop = mark.prop
            table.insert(self._items, {from=prop.SysCoord, to=prop.SysCoord + prop.Len, id=prop.ID})
        end
        printf('found %d switches', #self._items)
    end,

    -- проверить что координата находится в стрелке
    overalped = function(self, c1, c2)
        for _, switch in ipairs(self._items) do
            local l = math.max(c1, switch.from)
            local r = math.min(c2, switch.to)
            if l <= r then
                return switch.id
            end
        end
        return nil
    end,
}

local function supress_warning_211(...)
    local _ =...
end

-- ==================================================

local GapGroups = OOP.class
{
    NAME = 'Слепые зазоры',
    GUID = '{B6BAB49E-4CEC-4401-A106-355BFB2E0001}',
    PARAMETERS = {
        {rail=1, pov_operator=1},
        {rail=2, pov_operator=1},
        {rail=1, pov_operator=0},
        {rail=2, pov_operator=0},
    },

    ctor = function (self, width_threshold)
        self.width_threshold = width_threshold
        self.marks = {}
    end,

    LoadMarks = function (self, param, dlg)
        supress_warning_211(self ,dlg)
        assert(param and param.rail and param.pov_operator)
        local video_joints_juids =
        {
            TYPES.VID_INDT_1,	-- Стык(Видео)
            TYPES.VID_INDT_2,	-- Стык(Видео)
            TYPES.VID_INDT_3,	-- СтыкЗазор(Пользователь)
            TYPES.VID_INDT_ATS,	-- АТСтык(Видео)
            TYPES.RAIL_JOINT_USER,	-- Рельсовые стыки(Пользователь)
            TYPES.VID_ISO,   -- ИзоСтык(Видео)
        }
        local marks = group_utils.loadMarks(video_joints_juids)
        marks = group_utils.filter_rail(marks, param.rail)
        marks = group_utils.filter_pov_operator(marks, param.pov_operator)
        return marks
    end,

    Check = function (self, get_near_mark)
        local mark = get_near_mark(0)
        if mark.prop.Guid == TYPES.RAIL_JOINT_USER then
            if  mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP[1] or
                mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_TWO[1] or
                mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT[1] or
                mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_RIGHT[1]
            then
                return CHECK.ACCEPT
            else
                return CHECK.REFUTE
            end
        else
            local width = mark_helper.GetGapWidth(mark) or 100000
			if width <= self.width_threshold then
                return CHECK.ACCEPT
            else
                return CHECK.REFUTE
            end
        end
    end,

    OnGroup = function (self, group, param)
        if #group > 1 then
            assert(param and param.rail and param.pov_operator)

            local mark = group_utils.makeMark(
                self.GUID,
                group[1].prop.SysCoord,
                group[#group].prop.SysCoord - group[1].prop.SysCoord,
                param.rail,
                #group
            )

            -- 2020.08.05 Классификатор ред для ATape.xlsx
			--!!! актуальный 2021.02.18 Классфикатор ред  для ATape.xlsx
            if #group == 2 then
                mark.ext.CODE_EKASUI = DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_TWO[1] -- Наличие двух подряд слитых зазоров
            else
                if mark_helper.GetMarkRailPos(mark) == -1 then
                    -- Три и более слепых (нулевых) зазоров подряд по левой нити
                    mark.ext.CODE_EKASUI = DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT[1]
                else
                    -- Три и более слепых (нулевых) зазоров подряд по правой нити
                    mark.ext.CODE_EKASUI = DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_RIGHT[1]
                end
            end

            if param.pov_operator == 1 then
                sumPOV.UpdateMarks(mark)
            end

            table.insert(self.marks, mark)

            --print('Gaps', param.rail, #group, table.unpack(map(function (mark) return mark.prop.SysCoord end, group)))
        end
    end,
}


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
        self._switchers = Switchers()   -- стрелки
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
        local progress = group_utils.make_progress_cb(dlg, sprintf('загрузка скреплений рельс %d', param.rail), 123)
        local marks = group_utils.loadMarks(guids_fasteners)
        marks = group_utils.filter_rail(marks, param.rail)

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

-- =========================================

local function SearchGroupAutoDefects(guids)
    return EnterScope(function (defer)
		local pov_filter = sumPOV.MakeReportFilter(false)
		if not pov_filter then return {} end

        local dlg = luaiup_helper.ProgressDlg('Поиск групповых дефектов')
        defer(dlg.Destroy, dlg)

        local defect_types =
        {
            GapGroups(5),
            gruop_sleepers.SleeperGroups(),
            FastenerGroups()
        }
        local message = 'Найдено:\n'
        local marks = {}
        local guids_to_delete = {}
        for _, defect_type in ipairs(defect_types) do
            if not guids or mark_helper.table_find(guids, defect_type.GUID) then
                group_utils.scanGroupDefect(defect_type, dlg, pov_filter)
                message = message .. string.format('    %s: %d отметок\n', defect_type.NAME, #defect_type.marks)
                for _, mark in ipairs(defect_type.marks) do
                    table.insert(marks, mark)
                end
                table.insert(guids_to_delete, defect_type.GUID)
            end
        end
        message = message .. '\nСохранить?'
        local buttons = {"Да (удалить старые)", "Да (оставить старые)", "Нет"}

        -- print(#marks)
        local anwser = iup.Alarm("ATape", message, table.unpack(buttons))
        if 3 == anwser then return end
        if 1 == anwser then
            group_utils.remove_old_marks(guids_to_delete, dlg)
        end
        group_utils.save_marks(marks, dlg)
        return #marks
    end)
end

-- =========================================

if not ATAPE then
    local local_data_driver  = require('local_data_driver')

    -- local path = 'D:\\d-drive\\ATapeXP\\Main\\494\\video_recog\\2019_05_17\\Avikon-03M\\30346\\[494]_2019_03_15_01.xml'
    local path = 'D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml'
    --local path = 'C:/1/2/data_24_25.xml'
    local_data_driver.Driver(path, nil, {0, 10000000})

    local t = os.clock()
    local save_count = SearchGroupAutoDefects({
        --'{B6BAB49E-4CEC-4401-A106-355BFB2E0001}',
        '{B6BAB49E-4CEC-4401-A106-355BFB2E0011}',
        --'{B6BAB49E-4CEC-4401-A106-355BFB2E0021}',
    })
    printf("work %f sec, found %d mark", os.clock() - t, save_count or 0)
end

-- =========================================

return {
    SearchGroupAutoDefects = SearchGroupAutoDefects,
}
