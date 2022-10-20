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

local function get_video_image(center, rail)
    if ShowVideo ~= 1 then
        return ''
    end
    rail = bit32.band(rail, 0x03)

    local img_prop = {
        width = 900,
        height = 600,
        base64 = true,
        show_marks = 0,
    }

    local _, img_data = pcall(function ()
        return Driver:GetVideoComponentImage("ЕКАСУИ", center, rail, img_prop)
    end)
    return img_data
end

local function get_us_image(center)
    local params = {
        note_rec=nil,
        width=800,
        height=600,
        color=1,
        coord=center,
        length=10, -- 10 m
        sved=1, -- ctShift
        base64=true,
    }

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

-- адаптор для работы с записью ЗК или спец. польз. отметкой
local Defect = OOP.class{
    ctor = function (self, item)
        self._item = item
        self._is_ntb = type(item.GetNoteID) == "function"
    end,

    get_thread = function (self)
        local rail_left = self:get_rail_mask()
        if (rail_left == 1 or rail_left == 2) and tonumber(Passport.FIRST_LEFT) == 0 then
            rail_left = bit32.bxor(rail_left, 0x3)
        end
        return rail_left
    end,

    get_rail_mask = function (self)
        local mask = self._is_ntb and self._item:GetRailMask() or self._item.prop.RailMask
        return bit32.band(mask, 0x3)
    end,

    get_sys_coord = function (self, last)
        assert(last == 0 or last == 1)
        if self._is_ntb then
            return self._item:GetMarkCoord()
        else
            return self._item.prop.SysCoord + self._item.prop.Len * last
        end
    end,

    get_path_coord = function (self, last)
        if self._is_ntb then
            return self._item:GetPath()
        else
            return Driver:GetPathCoord(self:get_sys_coord(last))
        end
    end,

    get_description = function (self)
        if self._is_ntb then
            local plcmt, desc = self._item:GetPlacement(), self._item:GetDescription()
            local delm = ""
            if plcmt:len() > 0 and desc:len() > 0 then delm = " " end
            return plcmt .. delm .. desc
        else
            return self.prop.Description
        end
    end,

    get_speed_limit = function (self)
        if self._is_ntb then
            return self._item:GetSpeedLimit()
        else
            return 0 -- ???
        end
    end,

    get_action = function (self)
        if self._is_ntb then
            return self._item:GetAction()
        else
            return ""
        end
    end,

    get_defect_code = function (self)
        if self._is_ntb then
            return self._item:GetDefectCode()
        else
            return ""
        end
    end,

    get_id = function (self)
        local prefix, code
        if self._is_ntb then
            prefix, code = 1, self._item:GetNoteID()
        else
            prefix, code = 0, self._item.prop.ID
        end
        return sformat("%s%08d", prefix, code)
    end,

    get_full_id = function (self)
        return sformat("%s%s", get_reg_date_id(), self:get_id())
    end
}

-- ==================================================== --

local EkasuiReportWriter = OOP.class{
    ctor = function (self, path, params)
        self._file = io.open(path, "w+")
        self._header_added = false
        self._params = params
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
            self:_add_text_node(2, "Softint", "EKASUI_sync_3.40")
            self:_add_text_node(2, "Softdecode", "ATape 2.0")
            self:_add_text_node(2, "Nsiver", Passport.NSIVER or "")
            self:_add_text_node(2, "Extwonum", extwonum)
            self:_add_text_node(2, "Sessionid", "s1" .. extwonum)
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

        --local rail_mask = defect:get_rail_mask()
        local thread = defect:get_thread()

        local km, m, _ = defect:get_path_coord(defect, 0)
        local sys_coord = defect:get_sys_coord(0)
        local defect_code = defect:get_defect_code()
        local lat, lon = Driver:GetGPS(sys_coord)

        self:_start_node(2, "Defect", {Defectid=defect:get_full_id()})
            self:_add_text_node(3, "Notificationnum", "")
            self:_add_text_node(3, "Runtime", os.date('%d.%m.%Y %H:%M:%S', Driver:GetRunTime(sys_coord)))
            self:_add_text_node(3, "Decodetime", os.date('%d.%m.%Y %H:%M:%S'))
            self:_add_text_node(3, "Predid", Passport.RCDM or "")
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
            self:_add_text_node(3, "Lon", lon and sformat("%.6f", lon) or "")
            self:_add_text_node(3, "Lat", lat and sformat("%.6f", lat) or "")
            self:_add_text_node(3, "Generate", "0") -- 0 – всегда, 1 – во время регистрации
            self:_add_text_node(3, "Pic", get_us_image(sys_coord))
        self:_end_node(2, "Defect")
    end,

    add_workorders =function(self, npu_gen)
        assert(self._header_added)
        local add_hdr_node = false
        for npu in npu_gen do
            if not add_hdr_node then
                add_hdr_node = true
                self:_start_node(1, "Workorderset")
            end
            self:_add_workorder(npu)
        end
        if add_hdr_node then
            self:_end_node(1, "Workorderset")
        end
    end,

    _add_workorder = function (self, defect)
        --local rail_mask = defect:get_rail_mask()
        local thread = defect:get_thread()

        local km1, m1, _ = defect:get_path_coord(0)
        local km2, m2, _ = defect:get_path_coord(1)
        local s1, s2 = defect:get_sys_coord(0), defect:get_sys_coord(1)
        local defect_code = defect:get_defect_code()
        local lat1, lon1 = Driver:GetGPS(s1)
        local lat2, lon2 = Driver:GetGPS(s2)

        self:_start_node(2, "Workorder", {Workorderid=defect:get_full_id()})
          self:_add_text_node(3, "Woclass", self._params.Woclass)
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
            self:_add_text_node(3, "Defgroup", defect_code and defect_code:sub(1,1) or "")
            self:_add_text_node(3, "Criticdate", format_critic_date(defect:get_action()))
            self:_add_text_node(3, "Binding", defect:get_description())
            self:_add_text_node(3, "Startlon", lon1 and sformat("%.6f", lon1) or "")
            self:_add_text_node(3, "Beginlat", lat1 and sformat("%.6f", lat1) or "")
            self:_add_text_node(3, "Endlon", lon2 and sformat("%.6f", lon2) or "")
            self:_add_text_node(3, "Endlat", lat2 and sformat("%.6f", lat2) or "")
            self:_add_text_node(3, "Generate", "0") -- 0 – всегда, 1 – во время регистрации
            self:_add_text_node(3, "Pic", get_us_image((s1+s2) / 2.0))
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
        for _, items in ipairs(items_list) do
            for i, item in ipairs(items) do
                local msg = sformat("Обработка %s %d/%d", desc, i, #items)
                if dlg and not dlg:step(1 / #items, msg) then
                    break
                end
                coroutine.yield(Defect(item))
            end
        end
	end)
end

local function get_parameters()
    local function val2idx(dict, val)
        if not dict then return val end
        for i, row in ipairs(dict) do
            if row.value == val then
                return i-1
            end
        end
        error(sformat("unknow value %", val))
    end
    local function idx2val (dict, idx)
        if not dict then return idx end
        return assert(dict[idx+1], sformat("unknow idx %s", idx)).value
    end

    local woclass_dict = {
        {value="0",            desc="административное замечание" },
        {value="010001000201", desc="плановое РЗ на сплошной контроль" },
        {value="010001000202", desc="РЗ на повторный проход" },
        {value="010001000203", desc="РЗ на вторичный контроль" },
    }

    local params = {
        {name="Wonum", desc="Wonum", value=Passport.WONUM or "", },
        {name="Woclass", desc="Woclass", value="010001000203", dict=woclass_dict},
    }
    local sfmt = functional.map(function (p)
        local s = p.desc .. ": "
        if p.dict then
            s = s .. "%l|" .. table.concat(functional.map(function (p) return p.desc end, p.dict), "|") .. "|"
        else
            s = s .. "%s"
        end
        return s .. "\n"
    end, params)
    local values = functional.map(function (p) return val2idx(p.dict, p.value) end, params)
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
        for i, p in ipairs(params) do
            out[p.name] = idx2val(p.dict, res[i+1])
        end
        return out
    end
end

local function split_notebook_category(ntb)
    local odr = {}
    local other = {}
    for _, rec in ipairs(ntb) do
        if rec:IsODR() then
            table.insert(odr, rec)
        else
            table.insert(other, rec)
        end
    end
    return odr, other
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

		local w = EkasuiReportWriter(path_dst, params)
		w:add_header()

		local npu = {}
        if false then -- load NPU
            Driver:GetMarks({GUIDS=NPU_GUIDS})
            npu = mark_helper.sort_mark_by_coord(npu)
        end

        w:add_workorders(make_item_gen(dlgProgress, "Workorder", {other_ntb, npu}))
		w:add_defects(make_item_gen(dlgProgress, "ОДР", {odr}))
		w:close()
        Driver:MarkNtbIDsAsReported(functional.map(function (d) return d:GetNoteID() end, ntb))

        local anwser = iup.Alarm("EKASUI", sformat("Сохранен файл: %s", path_dst), "Показать", "Закрыть")
		if 1 == anwser then
			os.execute(path_dst)
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
