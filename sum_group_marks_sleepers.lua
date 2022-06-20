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

-- список координат стыков для определения кода дефекта шпал
local Joints =  OOP.class{
    ctor = function (self, dlg)
        local video_joints_juids =
        {
            TYPES.VID_INDT_1,	-- Стык(Видео)
            TYPES.VID_INDT_2,	-- Стык(Видео)
            TYPES.VID_INDT_3,	-- СтыкЗазор(Пользователь)
            TYPES.VID_INDT_ATS,	-- АТСтык(Видео)
            TYPES.RAIL_JOINT_USER,	-- Рельсовые стыки(Пользователь)
            TYPES.VID_ISO,   -- ИзоСтык(Видео)
        }
        local joints = group_utils.loadMarks(video_joints_juids, nil, dlg)
        local coords = {}
        for _, mark in ipairs(joints) do
            table.insert(coords, mark.prop.SysCoord)
        end
        table.sort(coords)
        self._coords = coords
    end,

    check_group = function (self, group)
        local c1 = group[1][1] - EPUR
        local c2 = group[#group][1] + EPUR
        local i1 = mark_helper.lower_bound(self._coords, c1)
        local i2 = mark_helper.lower_bound(self._coords, c2)
        return i1 < i2
    end,
}

local SleeperMarkCache = OOP.class{
    ctor = function (self, marks)
        self._sleepers = {}
        for _, mark in ipairs(marks) do
            -- сохраним отметки шпал по координате, чтобы потом к ним обращаться например за материалом
            self._sleepers[mark.prop.SysCoord] = mark
        end
    end,

    get_material = function (self, group)
        for _, mark in ipairs(group) do
            local sleeper_mark = self._sleepers[mark[1]]
            if sleeper_mark then
                local cur_material = mark_helper.GetSleeperMeterial(sleeper_mark)
                return cur_material
            end
        end
    end,
}

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
        self._joints = Joints(dlg)

		local guigs_sleepers =
		{
			"{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE1}",	-- Шпалы
			"{3601038C-A561-46BB-8B0F-F896C2130002}",	-- Шпалы(Пользователь)
			"{53987511-8176-470D-BE43-A39C1B6D12A3}",   -- SleeperTop
			"{1DEFC4BD-FDBB-4AC7-9008-BEEB56048131}",   -- SleeperDefect
		}

        local marks = group_utils.loadMarks(guigs_sleepers, pov_filter, dlg)
        self._material_cache = SleeperMarkCache(marks)

        local coord2defects = {}
        for _, scanner in ipairs(sum_report_sleepers.all_generators) do
            local cur_rows = scanner[1](marks, dlg, pov_filter)
            if not cur_rows then
                return {}
            end
            for _, row in ipairs(cur_rows) do
                local d = coord2defects[row.SYS] or {}
                table.insert(d, row.DEFECT_CODE)
                coord2defects[row.SYS] = d
            end
        end

        local order_by_coord = {}
        for c, d in pairs(coord2defects) do table.insert(order_by_coord, {c, d}) end
        table.sort(order_by_coord, function (lh, rh) return lh[1] < rh[1] end)
        return order_by_coord
    end,

    Check = function (self, get_near_mark)
        local prev = get_near_mark(-1)
        local cur = get_near_mark(0)

        if prev then
            local dist = cur[1] - prev[1]
            if dist > EPUR * 1.5 then
                -- если есть предыдущая и расстояние до нее больше чем должно быть между шпалами,
                -- полагаем что какую то шпалу не записали а значит неизвестно что было до
                return CHECK.CLOSE_ACCEPT
            end
        end

        return CHECK.ACCEPT
    end,

    OnGroup = function (self, group)
        if
            (#group >= 4) or
            (#group >= 2 and self._joints:check_group(group))
        then
            local new_mark = group_utils.makeMark(
                self.GUID,
                group[1][1],
                group[#group][1] - group[1][1],
                3,
                #group
            )
            local cur_material = self._material_cache:get_material(group)
            if cur_material then
                new_mark.ext.SLEEPERS_METERIAL = cur_material

                if cur_material == 1 then 
                    -- "бетон",
                    new_mark.ext.CODE_EKASUI = DEFECT_CODES.SLEEPER_DISTANCE_CONCRETE[1]
                else
                    -- "дерево"
                    new_mark.ext.CODE_EKASUI = DEFECT_CODES.SLEEPER_DISTANCE_WOODEN[1]
                end

                table.insert(self.marks, new_mark)
            end
        end
    end,
}

return
{
    SleeperGroups = SleeperGroups
}
