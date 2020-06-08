
local MP = require( "MessagePack" )
local Writer = require('ExtGpsWriter')
local Parser = require('NMEA_Parser')

local stuff = require 'stuff'
local printf = stuff.printf
local sprintf = stuff.sprintf

-- ================================================================ 

local Driver = {}

function Driver:open(passport_path)
	--print('test egpsdriver', tostring(0.1), tonumber('0.3'))
	assert(tonumber('0.3'), 'check locale settings, "." or "," used for fraction separator')
	self.writer = Writer.OpenEGps(passport_path)
	self.parse = Parser.ParseData
end

function Driver:on_data(data)
	assert(self.parse)
	
	local x = os.clock()
	local res, failed = {}, {}
	for _, d in MP.unpacker(data) do
		local gps, pps, sc = table.unpack(d)
		--print (pps, sc, stuff.escape(gps))
		local ok, parsed = pcall(self.parse, gps)
		
		if ok and parsed then 
			--stuff.save('parsed', parsed)
			if #parsed > 0 then
				local merged = self:_merge_parsed_data(parsed, gps)
				table.insert(res, {pps=pps, sc=sc, parsed=merged, gps=gps} )
			end
		else
			local msg = sprintf('parsing ERROR block pps=%d sc=%d data=[%s]: \n%s', 
				pps, sc, stuff.escape(gps), parsed or "" )
			print(msg)
			table.insert(failed, msg)
		end
	end
	print(string.format("Driver:on_data: parse time: %.3f", os.clock() - x))
		
	printf("Driver:on_data data_len = %d; block (parsed = %d, failed = %d)\n", #data, #res, #failed)
	x = os.clock()
	self:_on_parsed_data(res)
	print(string.format("Driver:on_data: rite time: %.3f", os.clock() - x))
	return {processed=#res, errors=failed}
end

function Driver:_merge_parsed_data(parsed, data)
	local res, types = {}, {}
	for _, block in ipairs(parsed) do
		if not types[block.Type] then
			types[block.BlockType] = 1
			block.BlockType = nil
			for n, v in pairs(block) do
				if res[n] then
					printf('found same data [%s] in block with values [%s] (will used) and [%s]\n', n, res[n], v)
				else
					res[n] = v
				end
			end
		else
			printf('found same block types [%s] in data [%s], skip it...', block.Type, data)
		end
	end
	
	if not res.Quality 	then	res.Quality = res.Status or 1	end
	if not res.Altitude then	res.Altitude = 0				end
	
	return res
end


function Driver:_on_parsed_data(data)
	assert(self.writer)
	local insert_data = function()
		for _,d in ipairs(data) do
			self.writer:on_data(d.sc, d.pps, d.parsed, d.gps)
		end
	end
	
	self.writer.db:transaction{body_fn = insert_data}
	--insert_data()
end

function Driver:close_data()
	assert(self.writer)
	self.writer:close_data()
	self.writer = nil
	self.parse = nil
end

-- ================================================================ 

function OpenDriver(passport_path)
	local r = {}
	setmetatable(r, {__index=Driver})
	r:open(passport_path)
	return r
end

function OnData(driver, data)
	return driver:on_data(data)
end

function CloseDriver(driver)
	-- print '============================================'
	-- print (driver)
	driver:close_data()
	-- print '============================================'
end

-- ================================================================ 

local tests = {}

function tests.parse()
	local driver = OpenDriver('tttt')
	local data_tbl = {
		{"$GPGGA,0945 20.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c\r\n$GPGLL,3751.65,S,14507.36,E,225444,A*77", 1, 10 },
		{"$GPGGA,094520.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c\r\n$GPGLL,3751.65,S,14507.36,E,225444,A*77", 2, 20 },
	}
	local merged = {}
	for _,d in ipairs(data_tbl) do
		local data = MP.pack(d)
		table.insert(merged, data)
	end
	
	merged = table.concat(merged)
	
	local res = driver:on_data(merged)
	printf('processed %d records\n', res.processed)
	for _, err in ipairs(res.errors) do
		print (err)
	end
end

function tests.parse_empty()
	local driver = OpenDriver('tttt')
	
	local merged = ""
	local res = driver:on_data(merged)
	printf('processed %d records\n', res.processed)
	for _, err in ipairs(res.errors) do
		print (err)
	end
end

function tests.file()
	local f = io.open('1.dat', 'rb')
	local buff = f:read(2^13)
	print (#buff)
	
	for i,d in MP.unpacker(buff) do
		local gps, pps, sc = table.unpack(d)
		print (gps, pps, sc)
	end
end


-- tests.parse_empty()
-- tests.parse()
-- tests.file()
