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

local function GetBase64EncodedFrame1(row)
	local rail = bit32.band(row.RAIL_RAW_MASK, 0x03)
	local video_channel = rail==1 and 17 or 18
	local video_img
	local ok, err = pcall(function()
		video_img = Driver:GetFrame(video_channel, row.SYS, {mode=3, panoram_width=700, width=400, height=300, base64=true} )
	end)
	if not ok then
		video_img = err
	end
	return video_img
end

local function merge_images(images)
	if not images or #images == 0 then
		return ''
	end

	local cmd = 'ImageMagick_convert.exe '
	for _, p in ipairs(images) do
		cmd = cmd .. '"' .. p .. '" '
	end
	local out_file_name = string.match(images[1], "(.*[/\\])") .. string.format('%08d.base64.jpg', os.clock() * 1000)
	cmd = cmd .. ' +append INLINE:"'  .. out_file_name .. '"'
	-- print(cmd)
	if not os.execute(cmd) then
		return 'command [' .. cmd .. '] failed'
	end

	local file_data = io.open(out_file_name, 'r')
	local data = file_data:read('*a')
	file_data:close()
	os.remove(out_file_name)

	-- print(#data)
	local hdr = 'data:image/jpeg;base64,'
	if(data:sub(1, #hdr) ~= hdr) then
		return 'bad output file header: [' .. data:sub(1, #hdr) .. ']'
	end

	return data:sub(#hdr+1)
end

local function GetBase64EncodedFrame(row)
	if ShowVideo == 0 then
		return ""
	end
	local p, e = pcall(function()
		local rail = bit32.band(row.RAIL_RAW_MASK, 0x03)
		local video_channels = rail==1 and {17, 19, 21} or {18, 20, 22}
		local channel_images_paths = {}
		for _, ch in ipairs(video_channels) do
			local ok, err = pcall(function()
				local image_params =
				{
					mode=3,
					panoram_width=700,
					width=400,
					height=300,
					base64=false,
					show_marks=0,
					hibit_dev_method='average',
					hibit_dev_param=50,
				}
				local p = Driver:GetFrame(ch, row.SYS, image_params)
				table.insert(channel_images_paths, p)
			end)
			if not ok then
				print(err)
			end
		end
		--iup.Message( 'Info', string.format("%d %d", row.SYS, #channel_images_paths))
		local res_image = merge_images(channel_images_paths)
		return res_image
	end)
	-- iup.Message( 'Info', string.format("%d: %s %s", row.SYS, p, e))
	if p then
		return e
	end
	print(e)
	return ""
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
	node_header:setAttribute("carID", EKASUI_PARAMS.carID)
	node_header:setAttribute("decoder", Passport.SIGNED)
	node_header:setAttribute("soft", "ATapeXP")
	node_header:setAttribute("decodePlaceID", "")
	node_header:setAttribute("pathType", pathType )
	node_header:setAttribute("SiteID", EKASUI_PARAMS.SITEID)
	node_header:setAttribute("pathID", Passport.TRACK_CODE)
	node_header:setAttribute("pathText", Passport.TRACK_NUM)
	node_header:setAttribute("startKM", Passport.FromKm or '0')
	node_header:setAttribute("startM", "0")
	node_header:setAttribute("endKM", Passport.ToKm or '0')
	node_header:setAttribute("endM", "0")

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
		node_incident:setAttribute("lon", format_gps(mark.LON))
		node_incident:setAttribute("lat", format_gps(mark.LAT))
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

		if #report_rows == 0 and 2 == iup.Alarm(title, "Подходящих отметок не найдено", "Построить пустой отчет", "Выход") then
			return
		end

		report_rows = mark_helper.sort_stable(report_rows, function(row)
			local c = row.SYS
			return c
		end)

		local export_id = os.date('%Y%m%d%H%M%S')
		local pghlp = make_export_prgs_dlg(dlgProgress, #report_rows)

        -- РЕДАКТИРОВАНИЕ  атрибутов проезда
            -- Получаем атрибуты проезда
        local SiteID   = EKASUI_PARAMS.SITEID
        local carID    = EKASUI_PARAMS.carID
        local pathType = 1 						-- https://bt.abisoft.spb.ru/view.php?id=722#c3397
        local pathID   = Passport.TRACK_CODE
        local pathText = Passport.TRACK_NUM
            -- Диалог редактирования  атрибутов проезда
        local res, _SiteID, _carID, _pathType, _pathID, _pathText = iup.GetParam("ЕКАСУИ: Проверка заполнения атрибутов", nil,
        "SiteID = %i\n\z carID = %s\n\z pathType = %i\n\z  pathID = %s\n\z pathText = %s\n\z",
        SiteID, carID, pathType, pathID, pathText )
        if res then
            EKASUI_PARAMS.SITEID = _SiteID
            EKASUI_PARAMS.carID  = _carID
            pathType             = _pathType
            Passport.TRACK_CODE  = _pathID
            Passport.TRACK_NUM   = _pathText
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
				EKASUI_PARAMS.SITEID, EKASUI_PARAMS.carID, psp_date, 0, Passport.TRACK_CODE
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
