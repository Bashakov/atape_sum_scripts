-- dofile('xml_parse.lua')

printf  = function(s,...)        return io.write(s:format(...))         end
sprintf = function(s,...)        return s:format(...)                         end

-- printf("Hello from %s on %s\n", _VERSION, os.date())


-- function for getting rail num (1,2,3) and flag video from mark info
function getMarkRail(mark)
	local RailMask = mark.RailMask

	local rail = bit32.band(RailMask, 0x03)
	local video = bit32.band(RailMask, 0x8) ~= 0        -- video if 0x08 bit was set in railmask

	if rail == 0 and video then                                        -- if rail not found and this video mark then try use channel num
		local chMask = mark.ChannelMask

		if bit32.band(chMask, 0x5555) ~= 0 then        -- if odd ch num (1,3,5) then set rail to 1
			rail = bit32.bor(rail, 1)
		end
		if bit32.band(chMask, 0xAAAA) ~= 0 then         -- if even ch num (2,4,6) then set rail to 2
			rail = bit32.bor(rail, 2)
		end
	end
	return rail, video                                                         --return rail and video_flag
end

function dump (o)                                                                -- help function for writing variable
	if type(o) == "number" then
		io.write(o)
	elseif type(o) == "string" then
		io.write(string.format("%q", o))
	elseif type(o) == "table" then
		io.write("{\n")
		for k,v in pairs(o) do
			io.write(" ", k, " = ")
			dump(v)
			io.write(",\n")
		end
		io.write("}\n")
	else
		error("cannot dump a " .. type(o))
	end
end

function parse_ActionResult(ar)                                        -- function for parse xml from video_ident and getting found gap width
	if not xml2table then
		dofile('scripts/xml_parse.lua')
	end

	local r = xml2table(ar)

	local startwith = function (String, Start)
		return string.sub(String, 1, string.len(Start)) == Start
	end

	local parseFN = function(fnum, coords)
		local w = fnum.PARAM.PARAM[2]._attr
		table.insert(coords, {fn=fnum._attr.value, crd=fnum._attr.coord, w=w.value} )
	end

	local parseRG = function(prm)
		coords = {}
		if (prm.PARAM) then
			parseFN(prm, coords)
		else
			for _, fnum in pairs(prm) do
				parseFN(fnum, coords)
			end
		end
		return coords
	end

	local res = {}
	for _, ar in pairs(r.root.ACTION_RESULTS.PARAM) do
		if startwith(ar._attr.value, 'CalcRailGap') then
			res[ar._attr.value] = parseRG(ar.PARAM)
		end
	end
	return res
end

function ChannelMask2videoChannels(ChannelMask)
	local res = {}
	-- print(ChannelMask)
	for i = 1, 32 do
		local t = bit32.lshift(1, i)
		-- print (i, t, bit32.btest(ChannelMask, t))
		if bit32.btest(ChannelMask, t) then
			table.insert(res, i)
		end
	end
	return table.concat(res, ",")
end

function format_int(val)
	return tostring(val):reverse():gsub("(%d%d%d)", "%1 "):reverse()
end

function math.round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end


-- ================================ EXPORT FUNCTIONS ================================= --

local Img_DA_guids = {

	["{8BCDBD8F-0588-407D-83AA-92E2C4A762E2}"] = 0, -- Hi
	["{9FE614FC-275A-400E-869D-85C9BDFD22B5}"] = 1,        -- Mi
	["{E7F5AB7E-6C7E-47BF-8F17-A826942DDC2B}"] = 2, -- Lo
	["{5C3A5288-344E-4655-AD2D-FBE6C37C3F56}"] = 3, -- No
	["{19253263-2C0B-41EE-8EAA-FFFFFFFFFFFF}"] = 4, -- FAIL_GAP_BY_MAGN


	["{EADB9B20-6772-4FA7-A1ED-811ED6DB0E2B}"] = 5,  -- FAIL
	["{E5FB236D-FE40-411E-9F7C-51D94EB1856B}"] = 6,  -- FAIL_ONLY_SINGLE
	["{62DEC5BD-654E-4C7C-8682-5E9834B3A084}"] = 7,  -- FAIL_ONLY_LO
	["{7FA7E3A6-1B5F-4728-8312-FD82432A0E05}"] = 8,  -- FAIL_SHIFT_VERTICAL
	["{083B6FED-4AAE-412A-B92E-43C23BF47393}"] = 9,  -- FAIL_NORMAL

	["{FC29AF42-5605-44B9-9599-7CCFB2D0D213}"] = 10,  -- TO_BE_IMPROVED

	["{19253263-2C0B-41EE-8EAA-FFFFFFFFFFF0}"] = 11, --FAIL_JOINT_BY_MAGN_AS_WELD
	["{19253263-2C0B-41EE-8EAA-FFFFFFFFFFF1}"] = 12, --FAIL_JOINT_BY_MAGN_AS_WELD_FP
	["{19253263-2C0B-41EE-8EAA-FFFFFFFFFFF2}"] = 13, --FAIL_JOINT_BY_MAGN_AS_ISO

	["{30F00EEB-FE4D-411C-82AE-66003115A864}"] = 14, -- FAIL_VR_17
	["{31E56427-E997-4CB9-B49C-0599FF9DDDB5}"] = 15, -- FAIL_VR_17_WEAK
}


local Img_guid2idx = {
	["{19253263-2C0B-41EE-8EAA-000000000010}"] = 4, -- iso
	["{19253263-2C0B-41EE-8EAA-000000000040}"] = 3, -- pseudo
	["{19253263-2C0B-41EE-8EAA-000000000080}"] = 5, -- NAKLADKA
	["{19253263-2C0B-41EE-8EAA-000000000100}"] = 9, -- SVARKA
	["{19253263-2C0B-41EE-8EAA-000000000400}"] = 9, -- SVARKA_REG
	["{19253263-2C0B-41EE-8EAA-000000000800}"] = 9, -- SVARKA_REG_NST
	["{19FF08BB-C344-495B-82ED-10B6CBAD508F}"] = 8, -- NPU

	["{CBD41D28-9308-4FEC-A330-35EAED9FC800}"] = 7, -- video_ident 0-50
	["{CBD41D28-9308-4FEC-A330-35EAED9FC810}"] = 7, -- video_ident 0-50
	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = 6, -- video_ident 50-70
	["{CBD41D28-9308-4FEC-A330-35EAED9FC811}"] = 6, -- video_ident 50-70
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = 2, -- video_ident 70-100
	["{CBD41D28-9308-4FEC-A330-35EAED9FC812}"] = 2, -- video_ident 70-100
	
	["{D4607B05-17C2-4C30-A303-69005A08C000}"] = 10, -- move backward
	["{D4607B05-17C2-4C30-A303-69005A08C001}"] = 11, -- move backward
}

function GetMarkImage(mark) -- exported (return ico desc from mark)
	local RailMask = mark.RailMask
	local chMask = mark.ChannelMask
	local coord = mark.SysCoord
	local typeGuid = mark.Guid

	local rail, video = getMarkRail(mark)                -- get rail and fideo_glag


	local da_index = Img_DA_guids[typeGuid]                -- first check at Dmitry Alexeev mark
	if da_index  then                                                        -- if guid found
		local offset = (rail == 1) and 0 or 1        -- convert rail to subindex
		local im_size = 16
		local res = {
			filename = 'Images/SUM_DA.bmp',                -- filename
			src_rect = { (da_index * 2 + offset) * im_size, 0, im_size, im_size}, -- {left, top, width, height}
		}
		return res                                                                -- return desc
	end


	local img_x = Img_guid2idx[typeGuid]                -- chack atape guids
	local img_y = rail - 1                                        -- rail to y offset (1,2,3 -> 0,1,2)

	if not img_x then                                                -- if guid not found, use default for video or regular
		img_x = video and 2 or 1
	end

	img_x = img_x or 0 -- or default
	img_y = img_y or 0 -- or default

	if rail < 1 or rail > 3 then                        -- if rail chaching failde then use default too
		img_x = 0
		img_y = 0
	end

	-- print (RailMask, rail, coord, typeGuid, img_x, img_y)

	local img_size = { x=16, y=16 }                        -- set img size
	local res = {
		filename = 'Images/sum.bmp',                -- filename
		src_rect = {img_x * img_size.x, img_y *img_size.y, img_size.x, img_size.y}, -- {left, top, width, height}
	}

	--printf("coord=%d, rm=%d, cm=%d, x=%d, y=%d\n", coord, RailMask, chMask, img_x, img_y)
	return res                                                                -- return ico description
end -- function

local desc_vguids = {
	["{CBD41D28-9308-4FEC-A330-35EAED9FC800}"] = 1, -- video_ident 0-50
	["{CBD41D28-9308-4FEC-A330-35EAED9FC810}"] = 0, -- video_ident 0-50
	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = 1, -- video_ident 50-70
	["{CBD41D28-9308-4FEC-A330-35EAED9FC811}"] = 0, -- video_ident 50-70
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = 1, -- video_ident 70-100
	["{CBD41D28-9308-4FEC-A330-35EAED9FC812}"] = 0, -- video_ident 70-100
}

function GetMarkDescription(mark) -- exported (get tooltip text)
	local Description = mark.Description
	local typeGuid = mark.Guid
	local coord = mark.SysCoord

	local typeDesc = APP.GetSpecUserMarkDesc(typeGuid)        -- convert guid to type descroption
	--print (typeDesc)

	local desc = typeDesc
	if #Description ~= 0 then                                                        -- if mark desc not empty then add it
		desc = desc .. '\n' .. Description
	end

	local vt = desc_vguids[typeGuid]                                        -- if this video_ident mark, try parse it XML and add to description
	if vt then
		local prop = mark:GetProperties()                                -- get mark property
		-- dump(prop)
		if prop.VIDEOIDENTGWT then                desc = desc .. sprintf('\nШирина по пов.  катания(коррек.): %d мм', prop.VIDEOIDENTGWT)        end
		if prop.VIDEOIDENTGWS then                desc = desc .. sprintf('\nШирина по рабочей грани(коррек.): %d мм', prop.VIDEOIDENTGWS)        end

		desc = desc .. sprintf('\n Видео канал [%d]', ChannelMask2videoChannels(mark.ChannelMask))

		local gf = vt == 1 and ' стык найден' or ' стык НЕ найден'
		desc = desc .. sprintf('\nдостоверность : %d | %s\n', prop.VIDEOIDENTRLBLT, gf)

		--[[local ar = parse_ActionResult(prop.RAWXMLDATA)        -- convert XML to widths
                for n, cw in pairs(ar) do
                        local t = ''
                        for _, w in pairs(cw) do t = t .. sprintf('\n     %d [%d] = %g mm', w.fn, w.crd, math.round(w.w/1000, 1)) end
                        desc = desc .. sprintf('\nШирина по %s:%s', n, t)
                end]]

		local ar = parse_ActionResult(prop.RAWXMLDATA) -- convert XML to widths
		local kvnrt = {
			['CalcRailGap_Head_Top'] =  'пов.  катания',
			["CalcRailGap_Head_Side"] = 'рабочей грани' }
		for n, cw in pairs(ar) do
			local t = ''
			for _, w in pairs(cw) do 
				t = t .. sprintf('\n     %d [%d] = %g mm', w.fn, w.crd, math.round(w.w/1000, 1)) 
			end
			desc = desc .. sprintf('\nШирина по %s:%s', kvnrt[n] or n, t)
		end
	end

	if(typeGuid == "{19FF08BB-C344-495B-82ED-10B6CBAD508F}") then
		desc = desc .. sprintf('\n  Протяженность: %s мм', format_int(mark.Len))
	end


	return desc
end -- function


function UpdatedSizePosSensArea(mark, pos, size)         -- exported (update mark sens area)
	local rail, video = getMarkRail(mark)                        -- get rail num
	-- local coord = mark.SysCoord
	if rail == 1 then                                                                -- if first rail, set region to upper half area
		size.cy = size.cy / 2
	elseif rail == 2 then                                                        -- if second, set region to bottom half area
		size.cy = size.cy / 2
		pos.y = pos.y + size.cy
	end
	-- print (coord, rail, pos.x, pos.y, size.cx, size.cy)
	return pos, size                                                                -- and return it back to atape
end -- function


