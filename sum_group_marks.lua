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

local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local luaiup_helper = require 'luaiup_helper'
local sumPOV = require "sumPOV"
require 'ExitScope'
local funcional = require 'functional'

local printf  = function(fmt, ...)	print(string.format(fmt, ...)) end
local sprintf = function(fmt, ...) return string.format(fmt, ...)  end

-- =============================================

local function format_sys_coord(coord)
    local s = string.format("%9d", coord)
    s = s:reverse():gsub('(%d%d%d)','%1.'):reverse()
    return s
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

local function make_progress_cb(dlg, title, step)
    step = step or 1
    return function (cur, all)
        if cur % 300 == 0 then collectgarbage("collect") end
        local text = sprintf('%s: %d/%d', title, cur, all)
        if cur % step == 0 and dlg and not dlg:step(cur / all, text) then
            return false
        end
        return true
    end
end

-- =============================================

local function loadMarks(guids)
    local marks = Driver:GetMarks{GUIDS=guids, ListType='all'}
    marks = mark_helper.sort_mark_by_coord(marks)
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
- Check: проверить отметку на дефектность, должна вернуть CHECK
- OnGroup: обработать полученную группу
]]
local function scanGroupDefect(defect_type, dlg)
    local params = defect_type.PARAMETERS or {1}
    local search_group_progress = make_progress_cb(dlg, sprintf('%s: обработка', defect_type.NAME), 23)
    for _, param in ipairs(params) do
        local marks = defect_type:LoadMarks(param, dlg)

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
        defect_type:OnGroup(group, param)
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
        assert(param and param.rail and param.pov_operator)
        local video_joints_juids =
        {
            "{CBD41D28-9308-4FEC-A330-35EAED9FC801}",	-- Стык(Видео)
            "{CBD41D28-9308-4FEC-A330-35EAED9FC802}",	-- Стык(Видео)
            "{CBD41D28-9308-4FEC-A330-35EAED9FC803}",	-- СтыкЗазор(Пользователь)
            "{CBD41D28-9308-4FEC-A330-35EAED9FC804}",	-- АТСтык(Видео)
            "{3601038C-A561-46BB-8B0F-F896C2130003}",	-- Рельсовые стыки(Пользователь)
            "{64B5F99E-75C8-4386-B191-98AD2D1EEB1A}",   -- ИзоСтык(Видео)
        }
        local marks = loadMarks(video_joints_juids)
        marks = filter_rail(marks, param.rail)
        marks = filter_pov_operator(marks, param.pov_operator)
        return marks
    end,

    Check = function (self, get_near_mark)
        local mark = get_near_mark(0)
        if mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130003}" then
            if  mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP[1] or
                mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_TWO[1] or
                mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT[1] or
                mark.ext.CODE_EKASUI == DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_RIGTH[1]
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

            local mark = makeMark(
                self.GUID,
                group[1].prop.SysCoord,
                group[#group].prop.SysCoord - group[1].prop.SysCoord,
                param.rail,
                #group
            )

            -- 2020.08.05 Классификатор ред для ATape.xlsx
			--!!! актуальный 2021.02.18 Классфикатор ред  для ATape.xlsx
            if #group == 2 then
                -- local rail_len = group[2].prop.SysCoord - group[1].prop.SysCoord
                mark.ext.CODE_EKASUI = DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_TWO[1] -- Наличие двух подряд слитых зазоров
            else
                if mark_helper.GetMarkRailPos(mark) == -1 then
                    mark.ext.CODE_EKASUI = DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_LEFT[1] -- Три и более слепых (нулевых) зазоров подряд по левой нити
                else
                    mark.ext.CODE_EKASUI = DEFECT_CODES.JOINT_NEIGHBO_BLIND_GAP_MORE_RIGTH[1] -- Три и более слепых (нулевых) зазоров подряд по правой нити
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

--!!! групповые отметки по эпюре и развороту должны иметь разные коды для ДШ и ЖБШ
local SleeperGroups = OOP.class
{
    NAME = 'Шпалы',
    GUID = '{B6BAB49E-4CEC-4401-A106-355BFB2E0011}',

    ctor = function (self, sleeper_count, MEK)
        self.ref_dist = 1000000 / sleeper_count
        self.MEK = MEK
        self.marks = {}
    end,

    LoadMarks = function (self)
        local guigs_sleepers =
        {
            "{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",	-- Шпалы
            "{3601038C-A561-46BB-8B0F-F896C2130002}",	-- Шпалы(Пользователь)
        }
        return loadMarks(guigs_sleepers)
    end,

    Check = function (self, get_near_mark)
        local mark = get_near_mark(0)
        if mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130002}" then
            if mark.ext.CODE_EKASUI == DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE[1] or
			   mark.ext.CODE_EKASUI == DEFECT_CODES.SLEEPER_DISTANCE_WOODEN[1] then
                return CHECK.ACCEPT
            else
                return CHECK.REFUTE
            end
        else
            local material_diffs = {
                [1] = 2*40, -- "бетон",
                [2] = 2*80, -- "дерево",
            }
            local function check_distance_normal(max_diff, cur_dist)
                if cur_dist < 200 then
                    return true
                end
                for i = 1, self.MEK do
                    if math.abs(cur_dist/i - self.ref_dist) <= max_diff then
                        return true
                    end
                end
                return false
            end

            local cur_material = mark_helper.GetSleeperMeterial(mark)
            local max_diff = material_diffs[cur_material] or 80

            local near = get_near_mark(1) or get_near_mark(-1) -- возьмем следующую или предыдущую
            if near then
                local near_dist = math.abs(near.prop.SysCoord - mark.prop.SysCoord)
                if check_distance_normal(max_diff, near_dist)  then
                    return CHECK.REFUTE
                else
                    return CHECK.ACCEPT
                end
            end
        end
    end,

    OnGroup = function (self, group)
        if #group > 1 then
            -- print('Sleepers', #group, table.unpack(map(function (mark) return mark.prop.SysCoord end, group)))
            local mark = makeMark(
                self.GUID,
                group[1].prop.SysCoord,
                group[#group].prop.SysCoord - group[1].prop.SysCoord,
                3,
                #group
            )
            local cur_material = mark_helper.GetSleeperMeterial(mark)

            if cur_material == 1 then -- "бетон",
                mark.ext.CODE_EKASUI = DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE[1]
            else -- "дерево"
                mark.ext.CODE_EKASUI = DEFECT_CODES.SLEEPER_DISTANCE_WOODEN[1]
            end

            table.insert(self.marks, mark)
        end
    end,
}

local FastenerGroups = OOP.class{
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
            if mark.prop.Guid == "{3601038C-A561-46BB-8B0F-F896C2130001}" then
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
            "{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}",	-- Скрепление
            "{3601038C-A561-46BB-8B0F-F896C2130001}",	-- Скрепления(Пользователь)
        }
        local progress = make_progress_cb(dlg, sprintf('загрузка скреплений рельс %d', param.rail), 123)
        local marks = loadMarks(guids_fasteners)
        marks = filter_rail(marks, param.rail)

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
            local code_ekasui = nil

            -- 2020.08.05 Классификатор ред для ATape.xlsx
            if inside_switch then
                if #group == 2 then
                    code_ekasui = '090004017105' -- Отсутствует или дефектное скрепление скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити  на 2-х брусьях подряд по одной нити
                elseif #group == 3 then
                    code_ekasui = '090004017106' -- Отсутствует или дефектное скрепление скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити  на 3-х брусьях подряд по одной нити
                elseif #group == 4 then
                    code_ekasui = '090004017107' -- Отсутствует или дефектное скрепление скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити  на 4-х брусьях подряд по одной нити
                elseif #group >= 4 then
                    code_ekasui = '090004017108' -- Отсутствует или дефектное скрепление скрепление на рамном рельсе, в крестовине или контррельсовом рельсе стрелочного перевода по одной нити  на 5 и более брусьях подряд 
                end
            else
                if #group == 4 then
                    code_ekasui = '090004017099' -- Отсутствует или дефектное скрепление скрепление в прямых и кривых радиусом более 650 м на 4-х шпалах подряд  по одной нити
                elseif #group == 5 then
                    code_ekasui = '090004017100'  -- Отсутствует или дефектное скрепление скрепление в прямых и кривых радиусом более 650 м на 5 шпалах подряд по одной нити
                elseif #group == 6 then
                    code_ekasui = '090004017101' -- Отсутствует или дефектное скрепление скрепление в прямых и кривых радиусом более 650 м на 6 шпалах подряд по одной нити
                elseif #group > 6 then
                    code_ekasui = '090004017098' --  Отсутствует или дефектное скрепление скрепление в прямых и кривых радиусом более 650 м более чем на 6 шпалах подряд по одной нити
                end
            end

            if code_ekasui then
                local mark = makeMark(
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
        local dlg = luaiup_helper.ProgressDlg('Поиск групповых дефектов')
        defer(dlg.Destroy, dlg)

        local defect_types =
        {
            GapGroups(5),
            SleeperGroups(1840, 4),
            FastenerGroups()
        }
        local message = 'Найдено:\n'
        local marks = {}
        local guids_to_delete = {}
        for _, defect_type in ipairs(defect_types) do
            if not guids or mark_helper.table_find(guids, defect_type.GUID) then
                scanGroupDefect(defect_type, dlg)
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
            remove_old_marks(guids_to_delete, dlg)
        end
        save_marks(marks, dlg)
        return #marks
    end)
end

-- =========================================

if not ATAPE then
    local test_report  = require('test_report')
    local data = 'D:\\d-drive\\ATapeXP\\Main\\494\\video_recog\\2019_05_17\\Avikon-03M\\30346\\[494]_2019_03_15_01.xml'
    --local data = 'D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml'
    test_report(data)

    local t = os.clock()
    local save_count = SearchGroupAutoDefects({
        --'{B6BAB49E-4CEC-4401-A106-355BFB2E0001}',
        --'{B6BAB49E-4CEC-4401-A106-355BFB2E0011}',
        '{B6BAB49E-4CEC-4401-A106-355BFB2E0021}',
    })
    printf("work %f sec, found %d mark", os.clock() - t, save_count or 0)
end

-- =========================================

return {
    SearchGroupAutoDefects = SearchGroupAutoDefects,
}
