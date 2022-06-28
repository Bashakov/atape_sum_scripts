local TYPES = require 'sum_types'
local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local DEFECT_CODES = require 'report_defect_codes'
local group_utils = require 'sum_group_marks_utils'

local CHECK = group_utils.CHECK


local prev_atape = ATAPE
ATAPE = true -- disable debug code while load scripts
local sum_report_sleepers = require "sum_report_sleepers"
ATAPE = prev_atape


local EPUR = 1000000 / 1840

local function supress_warning_211(...)
    local _ =...
end


local SleeperMarkCache = OOP.class{
    _cmp = function (a, b)
        return a[1] < b[1]
    end,

    ctor = function (self, marks)
        self._sleepers = {}
        for _, mark in ipairs(marks) do
            -- сохраним отметки шпал по координате, чтобы потом к ним обращаться например за материалом
            table.insert(self._sleepers, {mark.prop.SysCoord, mark})
        end
        table.sort(self._sleepers, self._cmp)
    end,

    get_material = function (self, group)
        local i1 = mark_helper.lower_bound(self._sleepers, {group[1] - EPUR, 0}, self._cmp)
        local i2 = mark_helper.lower_bound(self._sleepers, {group[#group] + EPUR, 0}, self._cmp)

        for i = i1,i2 do
            local sleeper_mark = self._sleepers[i][2]
            local cur_material = mark_helper.GetSleeperMeterial(sleeper_mark)
            if cur_material then
                return cur_material
            end
        end
    end,
}

-- загружаем все координаты дефектов и просто отметок в список,
-- потом сортируем его и группируем близкие отметки и потом ищем дефектные подряд
local SleeperScanner = OOP.class
{
    ctor = function (self, serach_dist, epur)
        self.serach_dist = serach_dist or 150
        self.epur = epur or (1000000/1840)
        self.defects = {}
        self.sleepers = nil
    end,

    insert = function (self, coord, defect)
        assert(not self.sleepers)
        while true do
            if type(self.defects[coord]) ~= 'nil' then
                coord = coord+1
            else
                self.defects[coord] = defect or false
                break
            end
        end
    end,

    prepare = function (self)
        assert(not self.sleepers)
        assert(self.defects)
        local sleepers = {}
        for c, d in pairs(self.defects) do
            sleepers[#sleepers+1] = {c, d}
        end
        table.sort(sleepers, function (a, b) return a[1] < b[1] end)
        self.sleepers = sleepers
        self.defects = nil
    end,

    -- объединение близких отметок в отметки шпал
    enum_sleepers = function (self)
        assert(not self.defects)
        assert(self.sleepers)
        return coroutine.wrap(function ()
            local prev_coord = nil
            local cur_defects = {}
            for _, sleeper in ipairs(self.sleepers) do
                local coord, defect = sleeper[1], sleeper[2]
                if prev_coord and coord - prev_coord > self.serach_dist then
                    coroutine.yield(prev_coord, cur_defects)
                    cur_defects = {}
                end
                if defect then
                    table.insert(cur_defects, defect)
                end
                prev_coord = coord
            end
            if prev_coord and #cur_defects > 0 then
                coroutine.yield(prev_coord, cur_defects)
            end
        end)
    end,

    -- сбор шпал с дефектами в группы
    enum_defect_groups = function (self)
        return coroutine.wrap(function ()
            local cur_group = {}
            for coord, defect in self:enum_sleepers() do
                if #cur_group > 0 then
                    if coord - cur_group[#cur_group] > self.epur * 1.5 or #defect == 0 then
                        if #cur_group > 1 then
                            coroutine.yield(cur_group)
                        end
                        cur_group = {}
                    end
                end

                if #defect > 0 then
                    table.insert(cur_group, coord)
                end
            end

            if #cur_group > 1 then
                coroutine.yield(cur_group)
            end
        end)
    end,
}

local function get_group_defect(cnt, joint, wood)
    if joint then
        if cnt>= 2 then
            if wood then
                return DEFECT_CODES.SLEEPER_GROUP_JOINT_WOOD
            else
                return DEFECT_CODES.SLEEPER_GROUP_JOINT_CONCRETE
            end
        end
    end

    if wood then
        if     cnt == 4 then return DEFECT_CODES.SLEEPER_GROUP_STRAIGHT_WOOD_4
        elseif cnt == 5 then return DEFECT_CODES.SLEEPER_GROUP_STRAIGHT_WOOD_5
        elseif cnt >= 6 then return DEFECT_CODES.SLEEPER_GROUP_STRAIGHT_WOOD_6
        end
    else
        if     cnt == 4 then return DEFECT_CODES.SLEEPER_GROUP_STRAIGHT_CONCRETE_4
        elseif cnt == 5 then return DEFECT_CODES.SLEEPER_GROUP_STRAIGHT_CONCRETE_5
        elseif cnt >= 6 then return DEFECT_CODES.SLEEPER_GROUP_STRAIGHT_CONCRETE_6
        end
    end
end

-- ======================================================

local SleeperGroups = OOP.class
{
    NAME = 'Шпалы',
    GUID = '{B6BAB49E-4CEC-4401-A106-355BFB2E0011}',

    ctor = function (self)
        self._joints = nil
        self._material_cache = nil
        self.marks = {} -- result
    end,

    LoadMarks = function (self, _, dlg, pov_filter)
        self._joints = group_utils.Joints(dlg, 1500)

        --[[ сейчас для формирования групповых дефектов нужны только дефектные шпалы (и установленные пользователем),
        а эпюра и перпендикулярность игнорируются https://bt.abisoft.spb.ru/view.php?id=925#c4760
        то меняем логику работы.
        отметки сейчас пишутся таким образом: если на шпале дефект то пишется XML распознавания, иначе только несколько параметров.
        поэтому на сетку из отметок шпал привязываем дефектные, чтобы искать подряд идущие отметки с дефектами
        отметки относящиеся к одной шпале могут гулять +-100 мм.
        ]]

		local guigs_sleepers =
		{
            TYPES.SLEEPER,	        -- Шпалы
			TYPES.SLEEPER_USER,	    -- Шпалы(Пользователь)
			TYPES.SLEEPER_TOP,      -- SleeperTop
			TYPES.SLEEPER_DEFECT,   -- SleeperDefect
		}

        local marks = group_utils.loadMarks(guigs_sleepers, pov_filter, dlg)
        self._material_cache = SleeperMarkCache(marks)

        local group_scanner = SleeperScanner()
        for _, mark in ipairs(marks) do
            group_scanner:insert(mark.prop.SysCoord)
        end

        for _, scanner in ipairs(sum_report_sleepers.group_generators) do
            local cur_rows = scanner[1](marks, dlg, pov_filter)
            if not cur_rows then
                return {}
            end
            for _, row in ipairs(cur_rows) do
                group_scanner:insert(row.SYS, row.DEFECT_CODE)
            end
        end

        group_scanner:prepare()

        for group in group_scanner:enum_defect_groups() do
            self:_check_group(group)
        end
        return {}
    end,

    Check = function (self, get_near_mark)
        supress_warning_211(self, get_near_mark)
        return CHECK.REFUTE
    end,

    OnGroup = function (self, group)
        supress_warning_211(self, group)
    end,

    _check_group = function (self, group)
        assert(#group > 1)
        local joint = self._joints:check_group(group)
        local material = self._material_cache:get_material(group)
        local defect_code = get_group_defect(#group, joint, material==2)
        if defect_code then
            local new_mark = group_utils.makeMark(
                self.GUID,
                group[1],
                group[#group] - group[1],
                3,
                #group
            )
            new_mark.ext.SLEEPERS_METERIAL = material
            new_mark.ext.CODE_EKASUI = defect_code[1]
            table.insert(self.marks, new_mark)
        end
    end,
}

return
{
    SleeperGroups = SleeperGroups,
    SleeperScanner = SleeperScanner,
}
