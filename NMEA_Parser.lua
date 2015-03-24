local M = {}

do
	local global_names = {'assert', 'io', 'ipairs', 'pairs', 'string', 'setmetatable', 'print', 
		'require', 'type', 'table', 'pcall', 'os', 'math', 'tonumber', 'tostring', 'error'}
	for _,n in pairs(global_names) do 
		M[n] = _G[n] 
	end

	if setfenv then
		setfenv(1, M) -- for 5.1
	else
		_ENV = M -- for 5.2
	end
end

local stuff = require 'stuff'
local printf = stuff.printf
local sprintf = stuff.sprintf
local escape = stuff.escape

-- =============================================================

local function split_fields(str, delim)
	str = string.gsub(str, "%s+", "")
	local outResults = { }
	local theStart = 1
	local theSplitStart, theSplitEnd = str:find(delim, theStart )
	while theSplitStart do
		table.insert( outResults, str:sub( theStart, theSplitStart-1 ) )
		theStart = theSplitEnd + 1
		theSplitStart, theSplitEnd = str:find( delim, theStart )
	end
	table.insert( outResults, str:sub( theStart ) )
	return outResults
end

local function select_fields (fields, positions, can_empty)
	local res = {}
	for _, i in ipairs(positions) do 
		local v = fields[i] or ""
		if #v == 0 and not can_empty then
			return nil
		end
		table.insert(res, v)
	end
	return res
end

-- ================================================================ 

local details = {}

details.UtcOffset = stuff.GetUtcOffset() 

details.DecodeCoord = function(value, pos)
	-- print (value, pos)
	if(#value + #pos < 3) then 
		error("empty coord string")
	end
	
	local sign = {N=1, S=-1, W=-1, E=1} 
	local gg, mm = string.match(value, "^0?(%d?%d%d)(%d%d%.%d*)")
	if not (gg and mm) then 
		gg, mm = string.match(value, "^0?(%d*.%d*)"), 0
	end 
	-- print (sign[pos], gg, mm, tonumber(mm))
	local degr = sign[pos] * (gg + mm / 60.0)
	return degr
end

details.TimeToMScount = function(value)
	local res = -1
	if value and #value > 5 then
		local h, m, s = string.match(value, "(%d%d)(%d%d)(%d%d%.?%d*)")
		--res = string.format("%02d:%02d:%02.3f", h,m,s)
		-- print (h, m, s, tonumber(s))
		local seconds = (h * 60 + m) * 60 + s
		res = math.floor( seconds * 1000.0 + 0.5)
		--print (value, h, m, s, res)
	end
	return res
end
	
details.DateToOsTime = function(value)
	local dd, mm, yy = string.match(value, "(%d%d)(%d%d)(%d%d)")
	--print (value, dd, mm, yy, NMEA_PARSER.UtcOffset )
	local ts = { year=(2000 + yy), month = mm, day = dd, hour=0 }
	local res = os.time(ts) + 3600 * details.UtcOffset
	return res
end

details.DecodeAltitude = function(value, units)
	if #value == 0 or #units == 0 then 	return ""	end
	--print (value, units)
	local units_factor = {M=1000.0} 
	local res = units_factor[units] * tonumber(value)
	return res
end

details.ParseBlock = function (data, fields_description)
	local fields = split_fields(data, ',')
	--for i,v in ipairs(fields) do print(i,v) end
	
	local res_table = {}
	for name, desc in pairs(fields_description) do 
		local flds = select_fields(fields, desc.fields, desc.can_empty)
		if not flds then 
			return nil
		end
		
		--print (name, table.unpack(flds))
		local r = flds[1]
		
		if desc.fn then 
			local ok, rr = pcall(desc.fn, table.unpack(flds))
			if not ok then
				--stuff.save('er', rr)
				local esc_fld = escape(table.concat(flds, '\';\''))
				error(sprintf('failed parse field %s:[\'%s\'] \n on data: [%s]\n with error: %s ', 
					name, esc_fld, escape(data) , rr))
			end
			r = rr or ""
		else
			error("parse function for name=[%s] not set\n", name)
		end
		--print (desc.name, r)
		res_table[name] = r
	end
	return res_table
end
	
details.ParseStatus = function(value)
	local res = ( {A=1, E=0} )[value]
	return res or 0
end

-- ======================================================== 

local data_block_desc = {
	GGA = {
		UTC 		= {	fields={1}, 	fn = details.TimeToMScount, can_empty = false},
		Latitude 	= { fields={2,3}, 	fn = details.DecodeCoord, 	can_empty = false},
		Longitude	= { fields={4,5}, 	fn = details.DecodeCoord, 	can_empty = false},
		Quality		= { fields={6}, 	fn = tonumber,				can_empty = true},
		NoS			= { fields={7}, 	fn = tonumber,				can_empty = true},
		HDOP		= { fields={8}, 	fn = tonumber,				can_empty = true},
		Altitude	= { fields={9,10}, 	fn = details.DecodeAltitude,can_empty = true},
		GeoidSep	= { fields={11,12},	fn = details.DecodeAltitude,can_empty = true},
		AgeDiff		= { fields={13}, 	fn = tonumber,				can_empty = true},
		DiffStID	= {	fields={14}, 	fn = tonumber,				can_empty = true},
	},
	
	GLL = {
		Latitude	= { fields={1,2}, 	fn = details.DecodeCoord, 	can_empty = false},
		Longitude	= { fields={3,4}, 	fn = details.DecodeCoord, 	can_empty = false},
		UTC			= { fields={5}, 	fn = details.TimeToMScount, can_empty = false},
		Status		= { fields={6}, 	fn = details.ParseStatus,	can_empty = true},
		},
	
	RMC = {
		UTC			= {	fields={1}, 	fn = details.TimeToMScount, can_empty = false},
		Status		= {	fields={2}, 	fn = details.ParseStatus,	can_empty = true},
		Latitude	= {	fields={3,4}, 	fn = details.DecodeCoord, 	can_empty = false},
		Longitude	= {	fields={5,6}, 	fn = details.DecodeCoord, 	can_empty = false},
		Speed		= {	fields={7}, 	fn = tonumber,				can_empty = true},
		TMG			= {	fields={8}, 	fn = tonumber,				can_empty = true},
		Date		= {	fields={9}, 	fn = details.DateToOsTime,	can_empty = true},
		MagnVar		= {	fields={10,11},	fn = details.DecodeCoord,	can_empty = true},
		},
}

--print('test nmea', tostring(0.1), tonumber('0.3'))
assert(tonumber('0.3'), 'check locale settings, "." or "," used for fraction separator')

function ParseData(data)
	local res = {}
	for block_type, block_data in string.gmatch(data, "%$G[PNL](%a%a%a),([^*]+)*%x%x") do
		local desc = data_block_desc[block_type]
		if desc then
			local parsed = details.ParseBlock(block_data, desc)
			if parsed then
				parsed.BlockType = block_type
				table.insert(res, parsed)
			else
				print ('empty block:' .. escape(block_data))
			end
		else
			print ('unknown block type:' .. block_type)
		end
	end
	return res
end

-- ================================================================ 
	
local tests = {}

tests.benchmark = function ()
	local nmea_data = 
		"$GPGGA,094520.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c\r\n"
		.. "$GPGGA,004241.47,5532.8492,N,03729.0987,E,1,04,2.0,-0015,M,,,,*AA\r\n" 
		.. "$GPGGA,094446,3851.3970,N,09447.9880,W,8,12,0.9,186.6,M,-28.6,M,,*75\r\n" 
		.. "$GPGGA,153450,3851.3970,N,09447.9880,W,0,00,	 ,		 ,M,		 ,M,,  *4c\r\n"
		.. "$GPGLL,3751.65,S,14507.36,E*77\r\n" 
		.. "$GPGLL,3751.65,S,14507.36,E,225444,A*77\r\n" 
		.. "$GPGLL,5532.8492,N,03729.0987,E,004241.469,A*33\r\n" 
		.. "$GPRMC,113650.0,A,5548.607,N,03739.387,E,000.01,5.6,210403,08.7,E*69"
		
	--nmea_data = "$GPRMC,113650.0,A,5548.607,N,03739.387,E,000.01,5.6,210403,08.7,E*69"
		
	local res, test_count = {}, 3000
	local x = os.clock()
	for i = 1, test_count do
		res = ParseData(nmea_data)
	end
	print( string.format("block parse time: %.1f usec", (os.clock() - x) * 1000000.0 / test_count) )

	res = {}
	for i,d in ipairs(res) do
		for n,v in pairs(d) do
			print(n,v)
		end
		print '========================'
	end
end

tests.parser = function ()
	function tester (block, expected_res)
		local errors = 0
		local res = ParseData(block)[1]
		for n, v in pairs(expected_res) do
			local is_equal = false
			if type(v) == 'number' then
				--print (res[n], v)
				is_equal = math.abs(res[n] - v) < math.abs(res[n] + v + 0.001) * 1.0e-10
			else
				is_equal = res[n] == v
			end
				
			if not is_equal then
				printf("ERROR for name=[%s]: expected=[%s] found=[%s], for string=%s", n, tostring(v), tostring(res[n]), block)
				errors = errors + 1
			end
			res[n] = nil
		end
		for n, v in pairs(res) do
			print (string.format("ERROR: found unexpected value [%s]=[%s] for string = %s", n, tostring(v), block) )
			errors = errors + 1
		end
		return errors
	end

	local tests_data = {
		{
			block = "$GPGGA,,,,,,0,07,,,M,,M,,*61",
			BlockType = "GGA",
		},
		{	block = "$GPGGA,153450,3851.3970,N,09447.9880,W,0,00,	 ,		 ,M,		 ,M,,  *4c",
			res = {
				BlockType = "GGA",
				UTC = 56090000,
				Latitude = 38.8566166666666,
				Longitude = 94.7998,
				Quality = 0,
				NoS	= 0,
				HDOP = "",
				Altitude = "",
				GeoidSep = "",
				AgeDiff	= "",
				DiffStID = "" }
		},
		{	block = "$GPGGA,094520.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c",
			res = {
				BlockType = "GGA",
				UTC = 35120590,
				Latitude = 37.391097950667,
				Longitude = 122.03782631066667,
				Quality = 2,
				NoS	= 6,
				HDOP = 1.2,
				Altitude = 18893.0,
				GeoidSep = -25669,
				AgeDiff	= 2.0,
				DiffStID = 31 }
		},
		{	block = "$GPGLL,3751.65,S,14507.36,E,225444,A*77",
			res = {
				BlockType = "GLL",
				Latitude = -37.86083333333333,
				Longitude = -145.12266666666667,
				UTC = 82484000,
				Status = 1}
		},
		{	block = "$GPRMC,113650.0,A,5548.607,N,03739.387,E,000.01,5.6,210403,08.7,E*69",
			res = {
				BlockType = "RMC",
				UTC = 41810000,
				Status = 1,
				Latitude = 55.810116666666666,
				Longitude = -37.65645,
				Speed = 0.01,
				TMG	= 5.6,
				Date = 1050883200,
				MagnVar = -8.7,}
		},
		{
			block = "$GPGGA,094433,3851.3970,N,09447.9880,W,8,12,0.9,186.6,M,-28.6,M,,*77",
			res = {
				BlockType = "GGA",
				UTC = 35073000,
				Latitude = 38.85661666666667,
				Longitude = 94.7998,
				Quality = 8,
				NoS	= 12,
				HDOP = 0.9,
				Altitude = 186600.0,
				GeoidSep = -28600,
				AgeDiff	= "",
				DiffStID = "", }
		}, 
	}
	local error_count = 0
	for _,t in ipairs(tests_data) do
		error_count = error_count + tester(t.block, t.res)
	end
	
	if error_count == 0 then
		print ("======= All Test done! =========")
	else
		print ("\n========= FOUND " .. error_count .. " ERROR !!! =========")
	end
end

tests.empty_data = function ()
	local nmea_data = "$GNGGA,,,,,,0,,,,,,,,*78\r\n"
		
	local res = ParseData(nmea_data)
	if #res ~= 0 then
		print('ERROR: must be upparsed')
	end
end
-- ================================================================ 


--tests.parser()
--tests.benchmark()
--tests.empty_data()

-- print(os.time{year=1970, month=1, day=2, hour=0} + stuff.GetUtcOffset() * 3600)
--NMEA_PARSER.details.dump( os.date("*t", 100))
--NMEA_PARSER.details.dump( os.date("!*t", 100))
-- print(os.date("%x", 1050883200))

return M