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

local function format_defect_speed_limit(defect)
    local num_otv = defect:GetSpeedLimit()
    if not num_otv or num_otv == 0 then
        return "установленная"
    end
    if num_otv < 0 then
        return "0"
    end
    local tbl = {15, 25, 40, 50, 60, 70, 100, 120, 140, 160, 200, 250} -- Таблица 2-06
    for i = #tbl, 1, -1 do
        local limit = tbl[i]
        if limit <= num_otv then
            return limit
        end
    end
    return num_otv
end

local function get_image(center, rail)
    if ShowVideo ~= 1 then -- https://bt.abisoft.spb.ru/view.php?id=809
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

-- ==================================================== --

local EkasuiReportWriter = OOP.class{
    ctor = function (self, path)
        self._file = io.open(path, "w+")
        self._header_added = false
    end,

    close = function (self)
        if self._header_added  then
            self:_end_node(0, "WorkOrder")
        end
        self._file:close()
    end,

    add_header = function (self, Wonum)
        assert(not self._header_added)
        self._file:write('<?xml version="1.0" encoding="utf-8"?>\n')
        self:_start_node(0, "WorkOrder", {Wonum=Wonum})
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

    add_NPUs =function(self, npu_gen)
        assert(self._header_added)
        local add_hdr_node = false
        for npu in npu_gen do
            if not add_hdr_node then
                add_hdr_node = true
                self:_start_node(1, "Workorderset")
            end
            self:_add_npu(npu)
        end
        if add_hdr_node then
            self:_end_node(1, "Workorderset")
        end
    end,

    _add_npu = function (self, mark)
        local rail_ekasui_table = {
            [-1] = 1, -- левый
            [ 0] = 3, -- оба
            [ 1] = 2, -- правый
        }
        local km1, m1, _ = Driver:GetPathCoord(mark.prop.SysCoord)
        local km2, m2, _ = Driver:GetPathCoord(mark.prop.SysCoord + mark.prop.Len)
        local lat1, lon1 = Driver:GetGPS(mark.prop.SysCoord)
        local lat2, lon2 = Driver:GetGPS(mark.prop.SysCoord + mark.prop.Len)

        self:_start_node(2, "Workorder", {Workorderid=sformat("%s%05d", get_reg_date_id(), mark.prop.ID)})
          self:_add_text_node(3, "Woclass", "!!! 010001000201")
          self:_add_text_node(3, "Notificationnum", "!!! 45157")
            self:_add_text_node(3, "Runtime", os.date('%d.%m.%Y %H:%M:%S', Driver:GetRunTime(mark.prop.SysCoord)))
            self:_add_text_node(3, "Decodetime", os.date('%d.%m.%Y %H:%M:%S'))
            self:_add_text_node(3, "Thread", rail_ekasui_table[mark_helper.GetMarkRailPos(mark)])
            self:_add_text_node(3, "Startkm", km1 or "")
            self:_add_text_node(3, "Startm", m1 or "")
            self:_add_text_node(3, "Endkm", km2 or "")
            self:_add_text_node(3, "Endm", m2 or "")
            self:_add_text_node(3, "Reason", "!!! 22")
            self:_add_text_node(3, "Section", "!!! 5")
            self:_start_node(3, "Boltholes")
                self:_add_text_node(4, "Railpart", "!!! 0")
                self:_add_text_node(4, "Holenum", "!!! 5")
            self:_end_node(3, "Boltholes")
            self:_add_text_node(3, "Defgroup", "!!! 5")
            self:_add_text_node(3, "Criticdate", "!!! 4")
            self:_add_text_node(3, "Binding", "")
            self:_add_text_node(3, "Startlon", lon1 and sformat("%.6f", lon1) or "")
            self:_add_text_node(3, "Beginlat", lat1 and sformat("%.6f", lat1) or "")
            self:_add_text_node(3, "Endlon", lon2 and sformat("%.6f", lon2) or "")
            self:_add_text_node(3, "Endlat", lat2 and sformat("%.6f", lat2) or "")
            self:_add_text_node(3, "Generate", "!!! 1")
            self:_add_text_node(3, "Pic", "") -- get_image(mark.prop.SysCoord + mark.prop.Len/2)
        self:_end_node(2, "Workorder")
    end,

    _add_defect = function (self, defect)
        local rail_mask = defect:GetRailMask()
        local rail_left = rail_mask
        if (rail_left == 1 or rail_left == 2) and tonumber(Passport.FIRST_LEFT) == 0 then
            rail_left = bit32.bxor(rail_left, 0x3)
        end
        local km, m, _ = defect:GetPath()
        local defect_code = defect:GetDefectCode()
        local lat, lon = Driver:GetGPS(defect:GetMarkCoord())

        self:_start_node(2, "Defect", {Defectid=sformat("%s%05d", get_reg_date_id(), defect:GetNoteID())})
            self:_add_text_node(3, "Notificationnum", "!!! 45157")
            self:_add_text_node(3, "Runtime", os.date('%d.%m.%Y %H:%M:%S', Driver:GetRunTime(defect:GetMarkCoord())))
            self:_add_text_node(3, "Decodetime", os.date('%d.%m.%Y %H:%M:%S'))
            self:_add_text_node(3, "Predid", Passport.RCDM or "")
            self:_add_text_node(3, "Thread", rail_left)
            self:_add_text_node(3, "Km", km)
            self:_add_text_node(3, "M", m)
            self:_add_text_node(3, "Defclass", get_ekasui_code_by_defect_code(defect_code))
            self:_add_text_node(3, "Deftype", "!!! 0")
            self:_add_text_node(3, "Fabric", "!!! 122")
            self:_add_text_node(3, "Month", "!!! 1")
            self:_add_text_node(3, "Year", "!!! 2018")
            self:_add_text_node(3, "Typerail", "!!! 101")
            self:_add_text_node(3, "Smeltingnum", "!!! 5454877")
            self:_add_text_node(3, "Sizedepth", "")
            self:_add_text_node(3, "Sizelength", "")
            self:_add_text_node(3, "Sizewidth", "")
            self:_add_text_node(3, "Speedlimitid", format_defect_speed_limit(defect))
            self:_add_text_node(3, "Comment", defect:GetPlacement() .. " " .. defect:GetDescription())
            self:_add_text_node(3, "Lon", lon and sformat("%.6f", lon) or "")
            self:_add_text_node(3, "Lat", lat and sformat("%.6f", lat) or "")
            self:_add_text_node(3, "Generate", "!!! 1")
            self:_add_text_node(3, "Pic", get_image(defect:GetMarkCoord(), rail_mask))
        self:_end_node(2, "Defect")
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

local function make_item_gen(dlg, desc, items)
	return coroutine.wrap(function()
		for i, item in ipairs(items) do
			local msg = sformat("Обработка %s %d/%d", desc, i, #items)
			if i % 12 == 1 and dlg and not dlg:step(1 / #items, msg) then
				break
			end
			coroutine.yield(item)
		end
	end)
end

local function report_EKASUI_US()
	EnterScope(function(defer)
		local dlgProgress = luaiup_helper.ProgressDlg()
		defer(dlgProgress.Destroy, dlgProgress)
        local path_dst = sformat("%s\\%s_US.xml",
            EKASUI_PARAMS.ExportFolder, Passport.SOURCE)
        if TEST_EKASUI_OUT_PREFIX then
            path_dst = TEST_EKASUI_OUT_PREFIX .. "_1.xml"
        end

		local w = EkasuiReportWriter(path_dst)
		w:add_header("!!! 413369986")

		local npu = Driver:GetMarks({GUIDS=NPU_GUIDS})
		npu = mark_helper.sort_mark_by_coord(npu)
		w:add_NPUs(make_item_gen(dlgProgress, "НПУ", npu))

		local ntb = Driver:GetNoteRecords()
		w:add_defects(make_item_gen(dlgProgress, "ЗК", ntb))
		w:close()

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
