require "luacom"

local OOP = require 'OOP'
local stuff = require 'stuff'
local mark_helper = require 'sum_mark_helper'
local luaiup_helper = require 'luaiup_helper'

-- ========================================

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
	local rail = bit32.band(row.RAIL_RAW_MASK, 0x03)
	local video_channel = rail==1 and 18 or 17
	local video_img
	local ok, err = pcall(function()
		video_img = Driver:GetFrame(video_channel, row.SYS, {mode=3, panoram_width=700, width=400, height=300, base64=true} )
	end)
	if not ok then 
		video_img = err
	end
	return video_img
end

-- ========================================


local function export_ekasui_xml(PackageNUM, marks, export_id, progres_dlg)
	local PackageID = uuid() -- Passport.SOURCE + 

	local run_year, run_month, run_day = string.match(Passport.DATE, "(%d+):(%d+):(%d+):")
	local runDate = sprintf("%s.%s.%s", run_day, run_month, run_year)
	
	local rail_ekasui_table = {[-1]=0, [0]=2, [1]=1} -- mark.RAIL_POS {-1 = левый, 0 = оба, 1 = правый}, Нить, статический справочник (0 – левая, 1 – правая, 2 – обе)
	
	local dom = luacom.CreateObject("Msxml2.DOMDocument.6.0")	
	assert(dom)
	local pi = dom:createProcessingInstruction("xml", "version='1.0' encoding='utf-8'");
	dom:appendChild(pi);
	
	local node_header = dom:createElement('header')
	dom:appendChild(node_header)
	
	node_header:setAttribute("NSIver", EKASUI_PARAMS.NSIver)
	node_header:setAttribute("Manufacture", "Радиоавионика")
	node_header:setAttribute("PackageID", PackageID)
	node_header:setAttribute("PackageNUM", PackageNUM)
	node_header:setAttribute("runDate", runDate)
	node_header:setAttribute("decodeDate", runDate)
	node_header:setAttribute("carID", EKASUI_PARAMS.carID)
	node_header:setAttribute("decoder", Passport.SIGNED)
	node_header:setAttribute("soft", "ATapeXP")
	node_header:setAttribute("decodePlaceID", "")
	node_header:setAttribute("pathType", "1")
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
		node_header:appendChild(node_incident)
		
		node_incident:setAttribute("recID", sprintf('%s%03d', os.date('%Y%m%d%H%M%S'), i))
		node_incident:setAttribute("time", os.date('%d.%m.%Y %H:%M:%S', runtime))
		node_incident:setAttribute("posKM", mark.KM)
		node_incident:setAttribute("posM", mark.M)
		node_incident:setAttribute("thread", rail_ekasui_table[mark.RAIL_POS]) 
		node_incident:setAttribute("defectID", mark.DEFECT_CODE)
		node_incident:setAttribute("sizeLength", "")
		node_incident:setAttribute("sizeWidth", "")
		node_incident:setAttribute("sizeDepth", "")
		node_incident:setAttribute("speedLimitID", mark.SPEED_LIMIT)
		node_incident:setAttribute("jpads", "null")
		node_incident:setAttribute("comment", "null")
		node_incident:setAttribute("lon", mark.LON)
		node_incident:setAttribute("lat", mark.LAT)
		node_incident:setAttribute("Pic", img)
		
		if progres_dlg and not progres_dlg() then
			break
		end
	end
	
	local path_dst = sprintf("%s\\video_%s_%s_%d.xml", EKASUI_PARAMS.ExportFolder, Passport.SOURCE, export_id, PackageNUM)
	dom:save(path_dst)
	return path_dst
end

local function make_export_prgs_dlg(dlgProgress, all)
	local cur = 0
	return function()
		cur = cur + 1
		return dlgProgress:step(cur / all, sprintf('Выгрузка %d / %d', cur, all)) 
	end
end



local function make_ekasui_generator(getMarks, ...)
	local row_generators = {...}
	local title = 'Выгрузка ЕКАСУИ'
	
	function gen()
		if not EKASUI_PARAMS then 
			iup.Message(title, "Конфигурация ЕКАСУИ не обнаружена")
			return
		end

		local dlgProgress = luaiup_helper.ProgressDlg()
		local marks = getMarks()
		
		local report_rows = {}
		for _, fn_gen in ipairs(row_generators) do
			local cur_rows = fn_gen(marks, dlgProgress)
			for _, row in ipairs(cur_rows) do
				table.insert(report_rows, row)
			end
			--print(#cur_rows, #report_rows)
		end
		
		if #report_rows == 0 then
			iup.Message(title, "Подходящих отметок не найдено")
			return
		end
		
		report_rows = mark_helper.sort_stable(report_rows, function(row)
			local c = row.SYS
			return c
		end)
			
		local export_id = os.date('%Y%m%d%H%M%S')
		local str_msg = 'Сохренено'
		local pghlp = make_export_prgs_dlg(dlgProgress, #report_rows)
		for n, group in mark_helper.split_chunks_iter(100, report_rows) do
			--print(#group)
			local path = export_ekasui_xml(n, group, export_id, pghlp)
			str_msg = str_msg .. sprintf('\n%d отметок в файл: %s', #group, path)
		end
		iup.Message(title, str_msg)
	end
	
	return gen
end

-- =================== ЭКПОРТ ===================


return {
	make_ekasui_generator = make_ekasui_generator,
}