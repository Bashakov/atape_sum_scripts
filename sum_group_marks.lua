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
local group_sleepers = require 'sum_group_marks_sleepers'
local group_fasteners = require 'sum_group_marks_fasteners'


local printf  = function(fmt, ...)	print(string.format(fmt, ...)) end

local CHECK = group_utils.CHECK

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
            group_sleepers.SleeperGroups(),
            group_fasteners.FastenerGroups(),
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
        --'{B6BAB49E-4CEC-4401-A106-355BFB2E0011}',
        '{B6BAB49E-4CEC-4401-A106-355BFB2E0021}',
    })
    printf("work %f sec, found %d mark", os.clock() - t, save_count or 0)
end

-- =========================================

return {
    SearchGroupAutoDefects = SearchGroupAutoDefects,
}
