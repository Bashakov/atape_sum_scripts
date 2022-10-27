require "luacom"
if not ATAPE then
	require "iuplua"
end

local OOP = require 'OOP'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'
require "ExitScope"

local printf = mark_helper.printf
local sprintf = mark_helper.sprintf
local errorf = mark_helper.errorf

-- ========================================

local function format_gps(val)
	if not val or val == '' then
		return ''
	end
	return string.format("%.8f", val)
end

math.randomseed(os.time())

local function uuid()
    local template ='{xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx}'
    local res = string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%X', v)
    end)
	return res
end

local function GetBase64EncodedFrame(row)
	if ShowVideo == 0 then
		return ""
	end

	local rail = bit32.band(row.RAIL_RAW_MASK, 0x03)
	local img_prop = {
		width = 900,
		height = 600,
		base64 = true,
	}
	local _, img_data = pcall(function ()
		return Driver:GetVideoComponentImage("ЕКАСУИ", row.SYS, rail, img_prop)
	end)
	return img_data
end

-- ========================================

local function export_ekasui_xml(PackageNUM, marks, export_id, progres_dlg, pathType )
	local PackageID = uuid() -- Passport.SOURCE +

	local run_year, run_month, run_day = string.match(Passport.DATE, "(%d+):(%d+):(%d+):")
	local runDate = sprintf("%s.%s.%s", run_day, run_month, run_year)

	local rail_ekasui_table = {[-1]=0, [0]=2, [1]=1} -- mark.RAIL_POS {-1 = левый, 0 = оба, 1 = правый}, Нить, статический справочник (0 – левая, 1 – правая, 2 – обе)

	local dom = luacom.CreateObject("Msxml2.DOMDocument.6.0")
	assert(dom)

	local node_OutFile = dom:createElement('OutFile')
	node_OutFile:setAttribute("NSIver", EKASUI_PARAMS.NSIver)

	local node_header = dom:createElement('header')
	node_OutFile:appendChild(node_header)

	node_header:setAttribute("Manufacture", "Радиоавионика")
	node_header:setAttribute("PackageID", PackageID)
	node_header:setAttribute("PackageNUM", PackageNUM)
	node_header:setAttribute("runDate", runDate)
	node_header:setAttribute("decodeDate", runDate)
	node_header:setAttribute("carID", Passport.CARID or "")					-- https://bt.abisoft.spb.ru/view.php?id=935
	node_header:setAttribute("decoder", Passport.CURRENT_OPERATOR or "")	-- https://bt.abisoft.spb.ru/view.php?id=935
	node_header:setAttribute("soft", "ATapeXP")
	node_header:setAttribute("decodePlaceID", Passport.RCDM or "")			-- https://bt.abisoft.spb.ru/view.php?id=935
	node_header:setAttribute("pathType", pathType )
	node_header:setAttribute("SiteID", Passport.SITEID or "")				-- https://bt.abisoft.spb.ru/view.php?id=935
	node_header:setAttribute("pathID", Passport.TRACK_CODE)
	node_header:setAttribute("pathText", Passport.TRACK_NUM)
	node_header:setAttribute("startKM", Passport.FromKm or '0')
	node_header:setAttribute("startM", "0")
	node_header:setAttribute("endKM", Passport.ToKm or '0')
	node_header:setAttribute("endM", "0")
	node_header:setAttribute("NSIver", Passport.NSIVER or "")				-- https://bt.abisoft.spb.ru/view.php?id=935

	for i, mark in ipairs(marks) do
		local runtime = Driver:GetRunTime(mark.SYS)
		local img = GetBase64EncodedFrame(mark)

		local node_incident = dom:createElement('incident')
		node_OutFile:appendChild(node_incident)

		node_incident:setAttribute("recID", sprintf('%s%03d', os.date('%Y%m%d%H%M%S'), i))
		node_incident:setAttribute("time", os.date('%d.%m.%Y %H:%M:%S', runtime))
		node_incident:setAttribute("posKM", mark.KM)
		node_incident:setAttribute("posM", mark.M)
		node_incident:setAttribute("thread", rail_ekasui_table[mark.RAIL_POS])
		node_incident:setAttribute("defectID", mark.DEFECT_CODE)
		node_incident:setAttribute("sizeLength", mark.GAP_WIDTH or mark.BEACON_OFFSET or "")
		node_incident:setAttribute("sizeWidth", "")
		node_incident:setAttribute("sizeDepth", "")
		node_incident:setAttribute("speedLimitID", mark.SPEED_LIMIT)
		node_incident:setAttribute("jpads", "null")
		node_incident:setAttribute("comment", "null")
		node_incident:setAttribute("lon", format_gps(mark.LON_RAW or mark.LON))
		node_incident:setAttribute("lat", format_gps(mark.LAT_ROW or mark.LAT))
		node_incident:setAttribute("Pic", img)
		node_incident:setAttribute("avikon_system_coord", mark.SYS)

		if progres_dlg and not progres_dlg() then
			break
		end
	end

	local path_prefix = TEST_EKASUI_OUT_PREFIX or string.format("%s\\video_%s_%s", EKASUI_PARAMS.ExportFolder, Passport.SOURCE, export_id)
	local path_dst = string.format("%s_%d.xml", path_prefix, PackageNUM)
	local f, msg = io.open(path_dst, 'w+')
	if not f then
		errorf("Can not open file: %s. %s", path_dst, msg)
	end
	f:write('<?xml version="1.0" encoding="utf-8"?>')
	f:write(node_OutFile.xml)
	f:close()
	return path_dst
end

local function make_export_prgs_dlg(dlgProgress, all)
	local cur = 0
	return function()
		cur = cur + 1
		return dlgProgress:step(cur / all+1, sprintf('Выгрузка %d / %d', cur, all))
	end
end



local function make_ekasui_generator(getMarks, ...)
	local row_generators = {...}
	local title = 'Выгрузка ЕКАСУИ'

	local function gen()
		EnterScope(function(defer)
		if not EKASUI_PARAMS then
			iup.Message(title, "Конфигурация ЕКАСУИ не обнаружена")
			return
		end

		local dlgProgress = luaiup_helper.ProgressDlg()
		defer(dlgProgress.Destroy, dlgProgress)

		local marks = getMarks(dlgProgress)

		local code2marks = {} -- убрать дублирование отметок полученных через стандартную функцию отчетов (включающую пользовательские отметки с опр. гуидом) и пользовательскую функцию отчетов
		local report_rows = {}
		for _, fn_gen in ipairs(row_generators) do
			local cur_rows = fn_gen(marks, dlgProgress)
			if not cur_rows then
				break
			end
			for _, row in ipairs(cur_rows) do
				local code = row.DEFECT_CODE or ''
				local id = row.mark_id or -1
				if not code2marks[code] then code2marks[code] = {} end
				if id < 0 or not code2marks[code][id] then
					code2marks[code][id] = true
					table.insert(report_rows, row)
				end
			end
			--print(#cur_rows, #report_rows)
		end

		report_rows = mark_helper.sort_stable(report_rows, function(row)
			local c = row.SYS
			return c
		end)

		local export_id = os.date('%Y%m%d%H%M%S')
		local pghlp = make_export_prgs_dlg(dlgProgress, #report_rows)

		-- https://bt.abisoft.spb.ru/view.php?id=949
		Passport.SITEID = Passport.SITEID or ''
		Passport.CARID = Passport.CARID or ''

        -- Диалог редактирования  атрибутов проезда
        local res = {iup.GetParam(
			"ЕКАСУИ: Проверка заполнения атрибутов", nil,
			"SiteID = %s\n\z
			carID = %s\n\z
			pathType = %i\n\z
			pathID = %s\n\z
			pathText = %s\n\z",
			Passport.SITEID,		-- https://bt.abisoft.spb.ru/view.php?id=935
			Passport.CARID,			-- https://bt.abisoft.spb.ru/view.php?id=935
			1, 						-- https://bt.abisoft.spb.ru/view.php?id=722#c3397
			Passport.TRACK_CODE,
			Passport.TRACK_NUM
		)}
        if res[1] then
            Passport.SITEID 	= res[2]
            Passport.CARID  	= res[3]
            pathType            = res[4]
            Passport.TRACK_CODE = res[5]
            Passport.TRACK_NUM  = res[6]
        end

		local first_file
		local str_msg = 'Сохренено'
        for n, group in mark_helper.split_chunks_iter(100, report_rows) do
			--print(#group)
			local path = export_ekasui_xml(n, group, export_id, pghlp, pathType)
			str_msg = str_msg .. sprintf('\n%d отметок в файл: %s', #group, path)
			if not first_file then
				first_file = path
			end
		end
		if #report_rows == 0 then
			first_file = export_ekasui_xml(1, {}, export_id, pghlp, pathType)
			str_msg = sprintf('\n0 отметок в файл: %s', first_file)
		end
		local anwser = iup.Alarm("Построение отчета закончено", str_msg, "Показать первый", "Закрыть")
		if 1 == anwser and first_file then
			local cmd = sprintf('%%SystemRoot%%\\explorer.exe /select,"%s"', first_file)
			os.execute(cmd)
		end
		end)
	end

	return gen
end

local function AskEkasuiParam()
	if not EKASUI_PARAMS then
		iup.Message("Генерация отчета", "Конфигурация ЕКАСУИ не обнаружена")
	else
		local psp_date = Passport.DATE --2017:06:08:12:44
		psp_date = string.gsub(psp_date, ":", "")
		psp_date = string.sub(psp_date, 1, 8) .. "_" .. string.sub(psp_date, 9) .. "00"

		local ok, road, vagon, proezd, proverka, assetnum = iup.GetParam("Параметры проезда", nil,
				"идентификатор дороги (ID БД ЕК АСУИ): %s\n\z
				идентификатор средства диагностики (ID БД ЕК АСУИ): %s\n\z
				дата (ГГГГММДД_ЧЧММСС): %s\n\z
				вид проверки: %o|рабочая|контрольная|дополнительная|\n\z
				ID пути БД ЕК АСУИ: %s\n\z",
				Passport.SITEID or '', Passport.CARID or '', psp_date, 0, Passport.TRACK_CODE
			)
		if ok then
			return {road=road, vagon=vagon, proezd=proezd, proverka=proverka, assetnum=assetnum}
		end
	end
	return nil
end

-- =================== ЭКСПОРТ ===================


return {
	make_ekasui_generator = make_ekasui_generator,
	AskEkasuiParam = AskEkasuiParam,
}
