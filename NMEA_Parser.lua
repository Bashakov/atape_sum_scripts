local base = _G
module ('NMEA_Parser')

-- =============================================================

helper = {}

helper.printf  = function(s,...)        return base.io.write(s:format(...))         end

helper.sprintf = function(s,...)        return s:format(...)                  		end

helper.GetUtcOffset = function ()
	local ts = 86000 * 5
	local cur, utc = base.os.date("*t", ts), base.os.date("!*t", ts)
	local diff = (cur.day - utc.day) * 24 + (cur.hour - utc.hour)
	return diff
end

helper.dump = function (o) 
	if basetype(o) == "number" then
		base.io.write(o)
	elseif type(o) == "string" then
		base.io.write(base.string.format("%q", o))
	elseif base.type(o) == "boolean" then	
		base.io.write( o and "true" or "false")
	elseif base.type(o) == "table" then
		base.io.write("{\n")
		for k,v in base.pairs(o) do
			base.io.write(" ", k, " = ")
			NMEA_PARSER.details.dump(v)
			base.io.write(",\n")
		end
		base.io.write("}\n")
	else
		base.error("cannot dump a " .. base.type(o))
	end
end
	
helper.split_fields = function(str, delim)
	local outResults = { }
	local theStart = 1
	local theSplitStart, theSplitEnd = str:find(delim, theStart )
	while theSplitStart do
		base.table.insert( outResults, str:sub( theStart, theSplitStart-1 ) )
		theStart = theSplitEnd + 1
		theSplitStart, theSplitEnd = str:find( delim, theStart )
	end
	base.table.insert( outResults, str:sub( theStart ) )
	return outResults
end

helper.select_fields = function(fields, positions)
	res = {}
	for _,i in base.ipairs(positions) do 
		base.table.insert(res, fields[i] or "")
	end
	return res
end

-- ================================================================ 

details = {}

details.UtcOffset = helper.GetUtcOffset() 

details.DecodeCoord = function(value, pos)
	--print (value, pos)
	local sign = {N=1, S=-1, W=1, E=-1} 
	local gg, mm = base.string.match(value, "^0?(%d?%d%d)(%d%d%.%d*)")
	if not (gg and mm) then 
		gg, mm = base.string.match(value, "^0?(%d*.%d*)"), 0
	end 
	--print (gg, mm)
	local degr = sign[pos] * (gg + mm / 60.0)
	return degr
end

details.TimeToMScount = function(value)
	local res = -1
	if value and #value > 5 then
		local h, m, s = base.string.match(value, "(%d%d)(%d%d)(%d%d%.?%d*)")
		--res = string.format("%02d:%02d:%02.3f", h,m,s)
		local seconds = (h * 60 + m) * 60 + s
		res = base.math.floor( seconds * 1000.0 + 0.5)
		--print (value, h, m, s, res)
	end
	return res
end
	
details.DateToOsTime = function(value)
	local dd, mm, yy = base.string.match(value, "(%d%d)(%d%d)(%d%d)")
	--print (value, dd, mm, yy, NMEA_PARSER.UtcOffset )
	local ts = { year=(2000 + yy), month = mm, day = dd, hour=0 }
	local res = base.os.time(ts) + 3600 * details.UtcOffset
	return res
end

details.DecodeAltitude = function(value, units)
	if #value == 0 and #units == 0 then 	return ""	end
	--print (value, units)
	local units_factor = {M=1000.0} 
	local res = units_factor[units] * base.tonumber(value)
	return res
end

details.ParseBlock = function (data, fields_description)
	local fields = helper.split_fields(data, ',')
	--for i,v in ipairs(fields) do print(i,v) end
	
	local res_table = {}
	for name, desc in base.pairs(fields_description) do 
		local flds = helper.select_fields(fields, desc.fields)
		--print (name, table.unpack(flds))
		local r = flds[1]
		if desc.fn then 
			r = desc.fn(base.table.unpack(flds)) or ""
		else
			helper.printf("parse function for name=[%s] not set\n", name)
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
		Quality		= { fields={6}, 	fn = base.tonumber},
		NOS			= { fields={7}, 	fn = base.tonumber},
		HDOP		= { fields={8}, 	fn = base.tonumber},
		Altitude	= { fields={9,10}, 	fn = details.DecodeAltitude},
		GeoidSep	= { fields={11,12},	fn = details.DecodeAltitude},
		AgeDiff		= { fields={13}, 	fn = base.tonumber},
		DiffStID	= {	fields={14}, 	fn = base.tonumber},},
	
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
		SOG			= {	fields={7}, 	fn = base.tonumber},
		TMG			= {	fields={8}, 	fn = base.tonumber},
		Date		= {	fields={9}, 	fn = details.DateToOsTime},
		MagnVar		= {	fields={10,11},	fn = details.DecodeCoord},},
}

function ParseData(data)
	local res = {}
	for block_type, block_data in base.string.gmatch(data, "%$GP(%a%a%a),([^*]+)*%x%x") do
		local desc = data_block_desc[block_type]
		if desc then
			local parsed = details.ParseBlock(block_data, desc)
			parsed.BlockType = block_type
			base.table.insert(res, parsed)
		else
			base.print ('unknown block type:' .. block_type)
		end
	end
	return res
end

-- ================================================================ 
	
tests = {}

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
	local x = base.os.clock()
	for i = 1, test_count do
		res = ParseData(nmea_data)
	end
	base.print( base.string.format("block parse time: %.1f usec", (base.os.clock() - x) * 1000000.0 / test_count) )

	res = {}
	for i,d in base.ipairs(res) do
		for n,v in base.pairs(d) do
			base.print(n,v)
		end
		base.print '========================'
	end
end

tests.parser = function ()
	function tester (block, expected_res)
		local errors = 0
		local res = ParseData(block)[1]
		for n, v in base.pairs(expected_res) do
			local is_equal = false
			if base.type(v) == 'number' then
				is_equal = base.math.abs(res[n] - v) < base.math.abs(res[n] + v) * 1.0e-10
			else
				is_equal = res[n] == v
			end
				
			if not is_equal then
				helper.printf("ERROR for name=[%s]: expected=[%s] found=[%s], for string=%s", n, base.tostring(v), base.tostring(res[n]), block)
				errors = errors + 1
			end
			res[n] = nil
		end
		for n, v in base.pairs(res) do
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
	for _,t in base.ipairs(tests_data) do
		error_count = error_count + tester(t.block, t.res)
	end
	
	if error_count == 0 then
		base.print ("======= All Test done! =========")
	else
		base.print ("========= FOUND " .. error_count .. " ERROR !!! =========")
	end
end

-- ================================================================ 


--tests.parser()
--tests.benchmark()

-- print(os.time{year=1970, month=1, day=2, hour=0} + helper.GetUtcOffset() * 3600)
--NMEA_PARSER.details.dump( os.date("*t", 100))
--NMEA_PARSER.details.dump( os.date("!*t", 100))
-- print(os.date("%x", 1050883200))
