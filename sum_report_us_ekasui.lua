if not ATAPE then
	require "iuplua"
end

if iup then
	iup.SetGlobal('UTF8MODE', 1)
end


local OOP = require "OOP"
local mark_helper = require "sum_mark_helper"
local luaiup_helper = require 'luaiup_helper'
local GUIDS = require "sum_types"
local functional = require "functional"
require "ExitScope"
require "luacom"
local ext_obj_utils = require 'list_ext_obj_utils'
local sqlite3 = require "lsqlite3"

local sformat = string.format

-- ==================================================== --

local function get_carid()
    return Passport.CARID or ""
end

local function get_reg_date_id()
    return string.gsub(Passport.DATE, ":", "") .. "00"
end

local function loadDefectCodes()
    local res = {}
    local path_ntb = os.getenv("ProgramFiles") .. "\\ATapeXP\\Defect_GR1.xml"
    local xmlDom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(xmlDom, 'can not create MSXML object')
	assert(xmlDom:load(path_ntb), "can not open xml file: " .. path_ntb)
    local nodes_record = xmlDom:SelectNodes('DATAPACKET/ROWDATA/ROW[@Code_EKASU and @cod]')
    while true do
		local node = nodes_record:nextNode()
		if not node then break end
        local code = node.attributes:getNamedItem('cod').nodeValue
        local ekasui = node.attributes:getNamedItem('Code_EKASU').nodeValue
        if #ekasui < 12 then
            ekasui = '0' .. ekasui
        end
		res[code] = ekasui
	end
    return res
end

local _ekasui_defect_codes = nil

local function get_ekasui_code_by_defect_code(code)
	if not _ekasui_defect_codes then
		_ekasui_defect_codes = loadDefectCodes()
	end
	return _ekasui_defect_codes[code] or ""
end

local function format_defect_speed_limit(speed_limit)
    if not speed_limit or speed_limit == 0 then
        return "установленная"
    end
    if speed_limit < 0 then
        return "0"
    end
    local tbl = {15, 25, 40, 50, 60, 70, 100, 120, 140, 160, 200, 250} -- Таблица 2-06
    for i = #tbl, 1, -1 do
        if tbl[i] <= speed_limit then
            return tbl[i]
        end
    end
    return speed_limit
end

local function get_us_image(defect)
    if ShowVideo ~= 1 then
        return ''
    end

    local params = {
        width=800,
        height=600,
        color=1,
        base64=true,
    }

    if defect.is_ntb then
        params.note_rec = defect.item:GetNoteID()
        params.coord = defect.item:GetMarkCoord()
    else
        local s1, s2 = defect:get_sys_coord(0), defect:get_sys_coord(1)
        params.coord = (s1 + s2) / 2
        params.length = (s2 - s1 + 1) * 1.1
        params.length = math.min(params.length, 30)
        params.sved = 1 -- ctShift
    end

    local _, img_data = pcall(function ()
        return Driver:GetUltrasoundImage(params)
    end)
    return img_data
end

local function format_critic_date(action)
    if type(action) ~= "string" or action:len() == 0 or action:sub(1,3) == "---" then
        return ""
    end
    local days = tonumber(string.match(action, "^%d+")) or 0
    local EKASUI_DICT =
    {
        {code=2, days=1},
        {code=3, days=2},
        {code=4, days=3},
        {code=5, days=5},
        {code=6, days=10},
        {code=7, days=15},
    }
    for i = #EKASUI_DICT, 1, -1 do
        if EKASUI_DICT[i].days <= days then
            return EKASUI_DICT[i].code
        end
    end
    return 1 -- 3 часа
end

local function format_gps(val)
    return val and sformat("%.6f", val) or ""
end

local PRED_ID_TBL = OOP.class{
    ctor = function (self, TRACK_CODE)
        local sql = [[
            CREATE TEMP TABLE temp.ph as
            SELECT
                a.BEGIN_KM, a.BEGIN_M, a.END_KM, a.END_M, c.TYPE, a.NUM, a.ID_PODR, b.CHIEF_NAME
            FROM
                PODRGR a
            INNER JOIN
                PODR b on a.SITEID=b.SITEID AND a.NUM=b.NUM AND a.TYPE=b.TYPE AND a.TYPE=5
            INNER JOIN
                SPR_PODR c on a.TYPE=c.ID
            INNER JOIN
                WAY d on a.SITEID=d.SITEID AND a.UP_NOM=d.UP_NOM AND a.PUT_NOM=d.NOM
            WHERE
                d.ASSETNUM=:ASSETNUM ]]
        local db = ext_obj_utils.open_db()
        local stmt = db:prepare(sql)
        if not stmt then
            local msg = string.format('%s(%s) on %s', db:errcode(), db:errmsg(), sql)
            error(msg)
        end
        stmt:bind_names({ASSETNUM=Passport.TRACK_CODE})
        assert(stmt:step() == sqlite3.DONE)
        self._db = db
    end,

    get = function (self, km, m)
        local db = self._db
        local sql = [[
            SELECT *
            FROM temp.ph
            WHERE
                (BEGIN_KM<:km or (BEGIN_KM=:km and BEGIN_M<=:m)) AND
                (END_KM>:km or (END_KM=:km and END_M>=:m)) ]]

        local stmt = db:prepare(sql)
        if not stmt then
            local msg = string.format('%s(%s) on %s', db:errcode(), db:errmsg(), sql)
            error(msg)
        end
        stmt:bind_names({km=km, m=m})
        for row in stmt:nrows() do
            return "PRED_" .. row.ID_PODR
        end
        return ""
    end,
}

-- адаптор для работы с записью ЗК или спец. польз. отметкой
local Defect = OOP.class{
    ctor = function (self, item)
        self.item = item
        self.is_ntb = type(item.GetNoteID) == "function"
    end,

    get_thread = function (self)
        local rail_left = self:get_rail_mask()
        if (rail_left == 1 or rail_left == 2) and tonumber(Passport.FIRST_LEFT) == 0 then
            rail_left = bit32.bxor(rail_left, 0x3)
        end
        return rail_left
    end,

    get_rail_mask = function (self)
        local mask = self.is_ntb and self.item:GetRailMask() or self.item.prop.RailMask
        return bit32.band(mask, 0x3)
    end,

    get_sys_coord = function (self, last)
        assert(last == 0 or last == 1)
        if self.is_ntb then
            if last == 0 then
                return self.item:GetMarkCoord()
            else
                return nil
            end
        else
            if Passport.INCREASE == '0' then
                last = 1 - last
            end
            return self.item.prop.SysCoord + self.item.prop.Len * last
        end
    end,

    get_gps = function (self, last)
        return Driver:GetGPS(self:get_sys_coord(last));
    end,

    get_path_coord = function (self, last)
        if self.is_ntb then
            if last == 0 then
                return self.item:GetPath()
            else
                return nil
            end
        else
            return Driver:GetPathCoord(self:get_sys_coord(last))
        end
    end,

    get_description = function (self)
        if self.is_ntb then
            local plcmt, desc = self.item:GetPlacement(), self.item:GetDescription()
            local delm = ""
            if plcmt:len() > 0 and desc:len() > 0 then delm = " " end
            return plcmt .. delm .. desc
        else
            return self.item.prop.Description
        end
    end,

    get_speed_limit = function (self)
        if self.is_ntb then
            return self.item:GetSpeedLimit()
        else
            return 0 -- ???
        end
    end,

    get_action = function (self)
        if self.is_ntb then
            return self.item:GetAction()
        else
            return ""
        end
    end,

    get_defect_code = function (self)
        if self.is_ntb then
            return self.item:GetDefectCode()
        else
            return ""
        end
    end,

    get_id = function (self)
        local prefix, code
        if self.is_ntb then
            prefix, code = 1, self.item:GetNoteID()
        else
            prefix, code = 0, self.item.prop.ID
        end
        return sformat("%s%08d", prefix, code)
    end,

    get_full_id = function (self)
        return sformat("%s%s", get_reg_date_id(), self:get_id())
    end,

    get_woclass = function (self)
        -- https://bt.abisoft.spb.ru/view.php?id=965#c5205
        -- https://bt.abisoft.spb.ru/view.php?id=965#c5258

        if self.is_ntb then
            return "010001000203" -- Для Дефектов (ДР) Woclass = 10001000203 РЗ на вторичный контроль
            -- Преддефект - к вагону это не относится, "создает съемное средство контроля по результатам проведения вторичного контроля".
        else
            return "010001000202" -- Для НПУ Woclass = 10001000202 РЗ на повторный проход
        end
    end
}

-- ==================================================== --

local EkasuiReportWriter = OOP.class{
    ctor = function (self, path, params)
        self._file = io.open(path, "w+")
        if not self._file then
            error("can not open output file: " .. path)
        end
        self._header_added = false
        self._params = params
        self._pred_ids = PRED_ID_TBL()
    end,

    close = function (self)
        if self._header_added  then
            self:_end_node(0, "WorkOrder")
        end
        self._file:close()
    end,

    add_header = function (self)
        assert(not self._header_added)
        self._file:write('<?xml version="1.0" encoding="utf-8"?>\n')
        self:_start_node(0, "WorkOrder", {Wonum=self._params.Wonum})
        self._header_added = true

        local extwonum = os.date("%Y%m%d%H%M%S") .. get_carid()

        self:_start_node(1, "Common_inf")
            self:_add_text_node(2, "Manufacture", "5")
            self:_add_text_node(2, "Softint", EKASUI_PARAMS.Softint or "")
            self:_add_text_node(2, "Softdecode", "ATape 2.24")
            self:_add_text_node(2, "Nsiver", Passport.NSIVER or "")
            self:_add_text_node(2, "Extwonum", extwonum)
            self:_add_text_node(2, "Sessionid", "1S" .. extwonum)
            self:_add_text_node(2, "Session_date", os.date("%d.%m.%Y %H:%M:%S"))
            self:_add_text_node(2, "Vag", get_carid())
            self:_add_text_node(2, "Decoder", Passport.CURRENT_OPERATOR or "")
            self:_add_text_node(2, "Siteid", Passport.SITEID or "")
            self:_add_text_node(2, "Assetnum", Passport.TRACK_CODE)
        self:_end_node(1, "Common_inf")
    end,

    add_defects =function(self, defect_gen)
        assert(self._header_added)
        local add_hdr_node = false
        for defect in defect_gen do
            if not add_hdr_node then
                add_hdr_node = true
                self:_start_node(1, "Defectset")
            end
            self:_add_defect(defect)
        end
        if add_hdr_node then
            self:_end_node(1, "Defectset")
        end
    end,

    _add_defect = function (self, defect)
        local thread = defect:get_thread()

        local km, m, _ = defect:get_path_coord(0)
        local sys_coord = defect:get_sys_coord(0)
        local defect_code = defect:get_defect_code()
        local lat, lon = defect:get_gps(0)

        self:_start_node(2, "Defect", {Defectid=defect:get_full_id()})
            self:_add_text_node(3, "Notificationnum", "")
            self:_add_text_node(3, "Runtime", os.date('%d.%m.%Y %H:%M:%S', Driver:GetRunTime(sys_coord)))
            self:_add_text_node(3, "Decodetime", os.date('%d.%m.%Y %H:%M:%S'))
            self:_add_text_node(3, "Predid", self._pred_ids:get(km, m))
            self:_add_text_node(3, "Thread", thread)
            self:_add_text_node(3, "Km", km)
            self:_add_text_node(3, "M", m)
            self:_add_text_node(3, "Defclass", get_ekasui_code_by_defect_code(defect_code))
            self:_add_text_node(3, "Deftype", "2") -- ВСЕГДА 2 (ОДР)
            self:_add_text_node(3, "Fabric", "")
            self:_add_text_node(3, "Month", "")
            self:_add_text_node(3, "Year", "")
            self:_add_text_node(3, "Typerail", "")
            self:_add_text_node(3, "Smeltingnum", "")
            self:_add_text_node(3, "Sizedepth", "")
            self:_add_text_node(3, "Sizelength", "")
            self:_add_text_node(3, "Sizewidth", "")
            self:_add_text_node(3, "Speedlimitid", format_defect_speed_limit(defect:get_speed_limit()))
            self:_add_text_node(3, "Comment", defect:get_description())
            self:_add_text_node(3, "Lon", format_gps(lon))
            self:_add_text_node(3, "Lat", format_gps(lat))
            self:_add_text_node(3, "Generate", "0") -- 0 – всегда, 1 – во время регистрации
            self:_add_text_node(3, "Pic", get_us_image(defect))
        self:_end_node(2, "Defect")
    end,

    add_workorders =function(self, defect_gen)
        assert(self._header_added)
        local add_hdr_node = false
        for defect in defect_gen do
            if not add_hdr_node then
                add_hdr_node = true
                self:_start_node(1, "Workorderset")
            end
            self:_add_workorder(defect)
        end
        if add_hdr_node then
            self:_end_node(1, "Workorderset")
        end
    end,

    _add_workorder = function (self, defect)
        local thread = defect:get_thread()

        local km1, m1, _ = defect:get_path_coord(0)
        local km2, m2, _ = defect:get_path_coord(1)
        local lat1, lon1 = defect:get_gps(0)
        local lat2, lon2 = defect:get_gps(1)

        local s1 = defect:get_sys_coord(0)
        local defect_code = defect:get_defect_code()

        self:_start_node(2, "Workorder", {Workorderid=defect:get_full_id()})
          self:_add_text_node(3, "Woclass", defect:get_woclass())
          self:_add_text_node(3, "Notificationnum", "") -- всегда пусто!
            self:_add_text_node(3, "Runtime", os.date('%d.%m.%Y %H:%M:%S', Driver:GetRunTime(s1)))
            self:_add_text_node(3, "Decodetime", os.date('%d.%m.%Y %H:%M:%S'))
            self:_add_text_node(3, "Thread", thread)
            self:_add_text_node(3, "Startkm", km1 or "")
            self:_add_text_node(3, "Startm", m1 or "")
            self:_add_text_node(3, "Endkm", km2 or "")
            self:_add_text_node(3, "Endm", m2 or "")
            self:_add_text_node(3, "Reason", "") -- на вагоне всегда пусто! для Офиса справочник
            self:_add_text_node(3, "Section", "") -- пока пусто всегда, потом - справочник в ЗК
            self:_start_node(3, "Boltholes")
                self:_add_text_node(4, "Railpart", "") -- пока пусто всегда, потом - справочник в ЗК
                self:_add_text_node(4, "Holenum", "") -- пока пусто всегда,номер отверстия.......
            self:_end_node(3, "Boltholes")
            self:_add_text_node(3, "Defgroup", defect_code and string.match(defect_code, "%d") or "")
            self:_add_text_node(3, "Criticdate", format_critic_date(defect:get_action()))
            self:_add_text_node(3, "Binding", defect:get_description())
            self:_add_text_node(3, "Startlon", format_gps(lon1))
            self:_add_text_node(3, "Beginlat", format_gps(lat1))
            self:_add_text_node(3, "Endlon", format_gps(lon2))
            self:_add_text_node(3, "Endlat", format_gps(lat2))
            self:_add_text_node(3, "Generate", "0") -- 0 – всегда, 1 – во время регистрации
            self:_add_text_node(3, "Pic", get_us_image(defect))
        self:_end_node(2, "Workorder")
    end,

    _start_node = function (self, indent, name, attr)
        local a = ""
        for n, v in pairs(attr or {}) do a = a .. string.format(' %s="%s"', n, v) end
        local s = string.rep("\t", indent) .. "<" .. name .. a .. ">\n"
        self._file:write(s)
    end,

    _end_node = function (self, indent, name)
        local s = string.rep("\t", indent) .. "</" .. name ..">\n"
        self._file:write(s)
    end,

    _add_text_node = function (self, indent, name, text)
        local s = string.rep("\t", indent) .. "<" .. name ..">" .. tostring(text) .. "</" .. name ..">\n"
        self._file:write(s)
    end
}

-- ============================================== --

local NPU_GUIDS =
{
	GUIDS.NPU,
	GUIDS.NPU2,
}

local function make_item_gen(dlg, desc, items_list)
	return coroutine.wrap(function()
        for ni, items in ipairs(items_list) do
            for ii, item in ipairs(items) do
                local msg = sformat("Обработка %s (%d/%d) %d/%d", desc, ni, #items_list, ii, #items)
                if dlg and not dlg:step(ii / #items, msg) then
                    break
                end
                coroutine.yield(Defect(item))
            end
        end
	end)
end

local function get_parameters()
    local function prep_val(row)
        if row.dict then
            for i, d in ipairs(row.dict) do
                if d.value == row.value then
                    return i-1
                end
            end
            error(sformat("unknow value %", val))
        elseif row.bool then
            return row.value and 1 or 0
        else
            return row.value
        end
    end
    local function get_val(row, val)
        if row.dict then
            return assert(row.dict[val+1], sformat("unknow idx %s", val)).value
        elseif row.bool then
            return val == 1
        else
            return val
        end
    end
    local function get_fmt(row)
        local s = row.desc .. ": "
        if row.dict then
            s = s .. "%l|" .. table.concat(functional.map(function (d) return d.desc end, row.dict), "|") .. "|"
        elseif row.bool then
            s = s .. "%b[No,Yes]"
        else
            s = s .. "%s"
        end
        return s .. "\n"
    end

    local rows = {
        {name="Wonum", desc="Код раб.задания в ЕКАСУИ ДМ НК (Wonum)", value=Passport.WONUM or "", },
        {name="show_npu", desc="Выводить НПУ", value=false, bool=true},
    }
    local sfmt = functional.map( get_fmt, rows)
    local values = functional.map(prep_val, rows)
    local res
    if true then -- !!!!!
        res = {iup.GetParam("Параметры генерации отчета", nil,
            table.concat(sfmt, ""),
            table.unpack(values)
        )};
    else
        res = {true, table.unpack(values)}
    end
    if res[1] then
        local out = {}
        for i, row in ipairs(rows) do
            out[row.name] = get_val(row, res[i+1])
        end
        return out
    end
end

local function split_notebook_category(ntb)
    local odr = {}
    local dr = {}
    for _, rec in ipairs(ntb) do
        if rec:IsODR() then
            table.insert(odr, rec)
        elseif rec:IsDR() then
            table.insert(dr, rec)
        end
    end
    return odr, dr
end

local function report_EKASUI_US()
	EnterScope(function(defer)
        local params = get_parameters()
        if not params then return end
		local dlgProgress = luaiup_helper.ProgressDlg()
		defer(dlgProgress.Destroy, dlgProgress)
        local path_dst = sformat("%s\\%s_US.xml",
            EKASUI_PARAMS.ExportFolder, Passport.SOURCE)
        if TEST_EKASUI_OUT_PREFIX then
            path_dst = TEST_EKASUI_OUT_PREFIX .. "_1.xml"
        end

        local ntb = Driver:GetNoteRecords()

        local odr, other_ntb = split_notebook_category(ntb)

        local npu = {}
        print("params.show_npu", params.show_npu ~= "0", params.show_npu)
        if params.show_npu then -- load NPU
            npu = Driver:GetMarks({GUIDS=NPU_GUIDS})
            npu = mark_helper.sort_mark_by_coord(npu)
        end

        local w = EkasuiReportWriter(path_dst, params)
		w:add_header()

        w:add_workorders(make_item_gen(dlgProgress, "Workorder", {other_ntb, npu}))
		w:add_defects(make_item_gen(dlgProgress, "ОДР", {odr}))
		w:close()
        Driver:MarkNtbIDsAsReported(functional.map(function (d) return d:GetNoteID() end, ntb))
        dlgProgress:Hide()

        local anwser = iup.Alarm("EKASUI", sformat("Сохранен файл: %s", path_dst), "Показать расположение", "Закрыть")
		if 1 == anwser then
            local cmd = string.format('%%SystemRoot%%\\explorer.exe /select,"%s"', path_dst)
			os.execute(cmd)
		end
	end)
end

-- ============================================== --

local function AppendReports(res)
	local name_pref = ''

	local cur =
	{
		{name = name_pref..'Дефекты УЗК в екасуи',		fn = report_EKASUI_US, },
    }

	for _, report in ipairs(cur) do
		if report.fn then
			report.guids = NPU_GUIDS
			table.insert(res, report)
		end
	end
end

-- тестирование
if not ATAPE then
	_G.ShowVideo = 0
	local test_report  = require('local_data_driver')
	test_report.Driver('D:/ATapeXP/Main/494/video/[494]_2017_06_08_12.xml', nil, {0, 100000000})

	report_EKASUI_US()
end

return {
	AppendReports = AppendReports,
}
