local M = {}

do
	local global_names = {'assert', 'io', 'ipairs', 'pairs', 'string', 'setmetatable', 'print', 
		'require', 'type', 'table', 'pcall', 'os', 'math', 'tonumber', 'tostring'}
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

-- =============================================================

local function split_fields(str, delim)
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

local function select_fields (fields, positions)
	res = {}
	for _,i in ipairs(positions) do 
		table.insert(res, fields[i] or "")
	end
	return res
end

-- ================================================================ 

local details = {}

details.UtcOffset = stuff.GetUtcOffset() 

details.DecodeCoord = function(value, pos)
	-- print (value, pos)
	local sign = {N=1, S=-1, W=1, E=-1} 
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
	if #value == 0 and #units == 0 then 	return ""	end
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
		local flds = select_fields(fields, desc.fields)
		--print (name, table.unpack(flds))
		local r = flds[1]
		if desc.fn then 
			r = desc.fn(table.unpack(flds)) or ""
		else
			printf("parse function for name=[%s] not set\n", name)
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
		UTC 		= {	fields={1}, 	fn = details.TimeToMScount},
		Latitude 	= { fields={2,3}, 	fn = details.DecodeCoord},
		Longitude	= { fields={4,5}, 	fn = details.DecodeCoord},
		Quality		= { fields={6}, 	fn = tonumber},
		NOS			= { fields={7}, 	fn = tonumber},
		HDOP		= { fields={8}, 	fn = tonumber},
		Altitude	= { fields={9,10}, 	fn = details.DecodeAltitude},
		GeoidSep	= { fields={11,12},	fn = details.DecodeAltitude},
		AgeDiff		= { fields={13}, 	fn = tonumber},
		DiffStID	= {	fields={14}, 	fn = tonumber},},
	
	GLL = {
		Latitude	= { fields={1,2}, 	fn = details.DecodeCoord},
		Longitude	= { fields={3,4}, 	fn = details.DecodeCoord},
		UTC			= { fields={5}, 	fn = details.TimeToMScount},
		Status		= { fields={6}, 	fn = details.ParseStatus},},
	
	RMC = {
		UTC			= {	fields={1}, 	fn = details.TimeToMScount},
		Status		= {	fields={2}, 	fn = details.ParseStatus},
		Latitude	= {	fields={3,4}, 	fn = details.DecodeCoord},
		Longitude	= {	fields={5,6}, 	fn = details.DecodeCoord},
		SOG			= {	fields={7}, 	fn = tonumber},
		TMG			= {	fields={8}, 	fn = tonumber},
		Date		= {	fields={9}, 	fn = details.DateToOsTime},
		MagnVar		= {	fields={10,11},	fn = details.DecodeCoord},},
}

function ParseData(data)
	assert(tonumber('0.3'), 'check locale settings, "." or "," used for fraction separator')
	local res = {}
	for block_type, block_data in string.gmatch(data, "%$GP(%a%a%a),([^*]+)*%x%x") do
		local desc = data_block_desc[block_type]
		if desc then
			local parsed = details.ParseBlock(block_data, desc)
			parsed.BlockType = block_type
			table.insert(res, parsed)
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
				is_equal = math.abs(res[n] - v) < math.abs(res[n] + v) * 1.0e-10
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
		{	block = "$GPGGA,094520.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c",
			res = {
				BlockType = "GGA",
				UTC = 35120590,
				Latitude = 37.391097950667,
				Longitude = 122.03782631066667,
				Quality = 2,
				NOS	= 6,
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
				SOG = 0.01,
				TMG	= 5.6,
				Date = 1050883200,
				MagnVar = -8.7,}
		},
	}
	local error_count = 0
	for _,t in ipairs(tests_data) do
		error_count = error_count + tester(t.block, t.res)
	end
	
	if error_count == 0 then
		print ("======= All Test done! =========")
	else
		print ("========= FOUND " .. error_count .. " ERROR !!! =========")
	end
end

-- ================================================================ 


--tests.parser()
--tests.benchmark()

-- print(os.time{year=1970, month=1, day=2, hour=0} + stuff.GetUtcOffset() * 3600)
--NMEA_PARSER.details.dump( os.date("*t", 100))
--NMEA_PARSER.details.dump( os.date("!*t", 100))
-- print(os.date("%x", 1050883200))

return M