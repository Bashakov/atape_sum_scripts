dofile('scripts/xml_parse.lua')

local printf  = function(s,...)        return io.write(s:format(...))         end
local sprintf = function(s,...)        return s:format(...)                         end

-- printf("Hello from %s on %s\n", _VERSION, os.date())


-- function for getting rail num (1,2,3) and flag video from mark info
local function getMarkRail(mark)
	local RailMask = mark.RailMask

	local rail = bit32.band(RailMask, 0x03)
	local video = bit32.band(RailMask, 0x8) ~= 0        -- video if 0x08 bit was set in railmask

	if rail == 0 and video then                         -- if rail not found and this video mark then try use channel num
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

local function dump (o)                                                                -- help function for writing variable
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

local function parse_ActionResult(ar)                                        -- function for parse xml from video_ident and getting found gap width
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

local function ChannelMask2videoChannels(ChannelMask)
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

local function format_int(val)
	return tostring(val):reverse():gsub("(%d%d%d)", "%1 "):reverse()
end

function math.round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

local function GetBeaconShift(x, beacon_name) 
	local r = xml2table(x)
	for _, ar in pairs(r.root.ACTION_RESULTS.PARAM) do
		if ar._attr.value == beacon_name then 
			for i, p in pairs(ar.PARAM.PARAM.PARAM) do
				--print(p._attr.name, p._attr.value)
				if p._attr.name == 'Shift_mkm' then
					return tonumber(p._attr.value) / 1000.0
				end
			end
		end
	end
end


local function _get_video_recog_desc(mark, desc)
	local prop = mark:GetProperties()                                -- get mark property
	-- dump(prop)
	if prop.VIDEOIDENTGWT then                desc = desc .. sprintf('\nШирина по пов.  катания(коррек.): %d мм', prop.VIDEOIDENTGWT)        end
	if prop.VIDEOIDENTGWS then                desc = desc .. sprintf('\nШирина по рабочей грани(коррек.): %d мм', prop.VIDEOIDENTGWS)        end

	desc = desc .. sprintf('\n Видео канал [%s]', ChannelMask2videoChannels(mark.ChannelMask))

	local gf = "" --1 and ' стык найден' or ' стык НЕ найден'
	desc = desc .. sprintf('\nдостоверность : %d | %s\n', prop.VIDEOIDENTRLBLT, gf)

	local ar = parse_ActionResult(prop.RAWXMLDATA) -- convert XML to widths
	local kvnrt = {
		['CalcRailGap_User'] =  'пользователь',
		['CalcRailGap_Head_Top'] =  'по пов.  катания',
		["CalcRailGap_Head_Side"] = 'по рабочей грани' }
	for n, cw in pairs(ar) do
		local t = ''
		for _, w in pairs(cw) do 
			t = t .. sprintf('\n     %d [%d] = %g mm', w.fn, w.crd, math.round(w.w/1000, 1)) 
		end
		desc = desc .. sprintf('\nШирина %s:%s', kvnrt[n] or n, t)
	end
	return desc
end -- function _get_video_recog_desc


local function  _get_npu_desc(mark, desc)
	return desc .. sprintf('\n  Протяженность: %s мм', format_int(mark.Len))
end


local function  _get_beacon_mark(mark, desc)
	local prop = mark:GetProperties()                                -- get mark property
	if prop then
		local shift = prop.RAWXMLDATA and GetBeaconShift(prop.RAWXMLDATA, "Beacon_Web")
		local suf = ""
		if prop.BEACONUSEROFFSET then
			desc = desc .. sprintf('\n  Смещение (корр.): %s мм', format_int(prop.BEACONUSEROFFSET))
			suf = " (автом.)";
		end
		if shift then
			desc = desc .. sprintf('\n  Смещение%s: %s мм', suf, format_int(shift))
		end
	end
	return desc
end


-- ================================ EXPORT FUNCTIONS ================================= --
local Img_DA_guids = {

		["{A77EC705-1E6D-4035-BCA5-84B6D338EB8D}"]=2, -- USER_SET="1" INTERNAL_NAME="VID_BEACON_INDT" VALUE="расп. МАЯЧ (R=50-70)"/>
		["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"]=1, -- USER_SET="1" INTERNAL_NAME="VID_BEACON_INDT" VALUE="Маячная(Видео распознование)""/>		
		["{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}"]=0, --USER_SET="1" INTERNAL_NAME="M_SPALA" VALUE="Маячная(Пользователь)" />	
		["{0860481C-8363-42DD-BBDE-8A2366EFAC90}"]=5, --USER_SET="1" INTERNAL_NAME="UNSPC_OBJ" VALUE="Ненормативный объект"  />		
	
		["{28C82406-2773-48CB-8E7D-61089EEB86ED}"]=17, --USER_SET="1" INTERNAL_NAME="VID_CREWJOINT_INDT" VALUE="Болты(Видео распознование)"  />	
		
		["{E3B72025-A1AD-4BB5-BDB8-7A7B977AFFE0}"]=9, --INTERNAL_NAME="FASTENER" VALUE="Скрепление"
		
		["{CC8B0BF6-719A-4252-8CA7-2991D226C4EF}"]=16, --"Нерасп. Стык" 
		["{FC2F2752-9383-45A4-8D0B-29851F3DD805}"]=15, --"Нерасп. АТСтык"
		["{1F3BDFD2-112F-499A-9CD3-30DF28DDF6D3}"]=14, --"Нерасп. П.Деф."
		
		["{4FB794A3-0CD7-4E55-B0FB-41B023AA5C6E}"]=18, --"П.Деф."
		
}

local Img_guid2idx = {
    ["{19253263-2C0B-41EE-8EAA-000000000010}"] = 4, -- iso
    ["{19253263-2C0B-41EE-8EAA-000000000040}"] = 3, -- pseudo
    ["{19253263-2C0B-41EE-8EAA-000000000080}"] = 5, -- NAKLADKA
	["{19253263-2C0B-41EE-8EAA-000000000100}"] = 9, -- SVARKA
	["{19253263-2C0B-41EE-8EAA-000000000400}"] = 9, -- SVARKA_REG
	["{19253263-2C0B-41EE-8EAA-000000000800}"] = 9, -- SVARKA_REG_NST
    ["{19FF08BB-C344-495B-82ED-10B6CBAD508F}"] = 8, -- pre NPU
	["{19FF08BB-C344-495B-82ED-10B6CBAD5090}"] = 12, -- NPU

    ["{CBD41D28-9308-4FEC-A330-35EAED9FC800}"] = 2, -- video_ident 0-50
    ["{CBD41D28-9308-4FEC-A330-35EAED9FC810}"] = 2, -- video_ident 0-50
    ["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = 2, -- video_ident 50-70
    ["{CBD41D28-9308-4FEC-A330-35EAED9FC811}"] = 2, -- video_ident 50-70
    ["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = 2, -- video_ident 70-100
    ["{CBD41D28-9308-4FEC-A330-35EAED9FC812}"] = 2, -- video_ident 70-100
	["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = 7, -- video_ident user
	["{CBD41D28-9308-4FEC-A330-35EAED9FC804}"] = 6, -- ats

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
	["{CBD41D28-9308-4FEC-A330-35EAED9FC800}"] = _get_video_recog_desc, 	-- video_ident 0-50
	["{CBD41D28-9308-4FEC-A330-35EAED9FC810}"] = false, 					-- video_ident 0-50
	["{CBD41D28-9308-4FEC-A330-35EAED9FC801}"] = _get_video_recog_desc, 	-- video_ident 50-70
	["{CBD41D28-9308-4FEC-A330-35EAED9FC811}"] = false, 					-- video_ident 50-70
	["{CBD41D28-9308-4FEC-A330-35EAED9FC802}"] = _get_video_recog_desc, 	-- video_ident 70-100
	["{CBD41D28-9308-4FEC-A330-35EAED9FC812}"] = false, 					-- video_ident 70-100
	["{CBD41D28-9308-4FEC-A330-35EAED9FC803}"] = _get_video_recog_desc, 	-- video_ident (user)
	["{CBD41D28-9308-4FEC-A330-35EAED9FC804}"] = _get_video_recog_desc, 	-- video_ident (ats)
	
	["{19FF08BB-C344-495B-82ED-10B6CBAD508F}"] = _get_npu_desc,				-- NPU
	["{19FF08BB-C344-495B-82ED-10B6CBAD5090}"] = _get_npu_desc,				-- NPU
	
	["{DC2B75B8-EEEA-403C-8C7C-212DBBCF23C6}"] = _get_beacon_mark,			-- beacon  (user)
	["{2427A1A4-9AC5-4FE6-A88E-A50618E792E7}"] = _get_beacon_mark,			-- beacon
	
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
	
	local fn = desc_vguids[typeGuid]                                        -- if this video_ident mark, try parse it XML and add to description
	if fn then
		desc = fn(mark, desc)
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


