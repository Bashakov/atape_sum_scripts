local base = _G

module('ExtGpsDriver')

local global_names = {'assert', 'io', 'ipairs', 'pairs', 'string', 'setmetatable', 'print', 'require', 'type', 'table'}
for _,n in base.pairs(global_names) do 
	_M[n] = base[n] 
end

local MP = require( "MessagePack" )
local Writer = require('ExtGpsWriter')
local Parser = require('NMEA_Parser')

printf  = function(s,...)        return base.io.write(s:format(...))		end
sprintf = function(s,...)        return s:format(...)                  		end

function dump(o) 
	if type(o) == "number" then
		io.write(o)
	elseif type(o) == "string" then
		io.write(string.format("%q", o))
	elseif type(o) == "table" then
		io.write("{\n")
		for k,v in base.pairs(o) do
			io.write(" ", k, " = ")
			dump(v)
			io.write(",\n")
		end
		io.write("}\n")
	elseif type(o) == "function" then
		io.write("function")
	else
		error("cannot dump a " .. base.type(o))
	end
end



--dump(Writer)

-- ================================================================ 

local Driver = {}

Driver.BlockWriter = {}

function Driver:open(passport_path)
	self.writer = Writer.OpenEGps(passport_path)
	self.parse = Parser.ParseData
end

function Driver:on_data(data)
	assert(self.parse)

	local data_table, res = MP.unpack(data), {}
	for i,d in ipairs(data_table) do
		local pps, sc, gps = table.unpack(d)
		print (pps, sc, gps)
		local parsed = self.parse(gps)
		if parsed then  
			--dump(parsed)
			local merged = self:_merge_parsed_data(parsed, gps)
			table.insert(res, {pps=pps, sc=sc, parsed=merged, gps=gps} )
		end
	end
	
	self:_on_parsed_data(res)
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
	self.writer.db:transaction{body_fn = function()
		for _,d in ipairs(data) do
			self.writer:on_data(d.sc, d.pps, d.parsed, d.gps)
		end
	end}
end


function OpenDriver(passport_path)
	local r = {}
	setmetatable(r, {__index=Driver})
	r:open(passport_path)
	return r
end

function OnData(driver, data)
	driver:on_data(data)
end

-- ================================================================ 

tests = {}

function tests.modules()
	function table_equals(t1, t2)
		base.assert(base.type(t1) == 'table')
		base.assert(base.type(t2) == 'table')
		
		for i, v in base.pairs(t1) do
			if base.type(v) == 'table' then 
				if not table_equals(v, t2[i]) then
					return false
				end
			elseif t2[i] ~= v then
				return false
			end
			t2[i] = nil
		end
		return base.next(t2) == nil
	end
	
	local tbl = { a=123, b="any", c={"ta","bl","e",1,2,3} }
	local packed = MP.pack(tbl)
	local unpacked_table = MP.unpack(packed)
	base.assert(table_equals(tbl, unpacked_table))

	Writer.test()
	Parser.tests.parser()
end 

function tests.parse()
	local driver = OpenDriver('tttt')
	local data_tbl = {
		{1, 10, "$GPGGA,094520.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c\r\n$GPGLL,3751.65,S,14507.36,E,225444,A*77" },
		{2, 20, "$GPGGA,094520.590,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4c\r\n$GPGLL,3751.65,S,14507.36,E,225444,A*77" },
	}
	local data = MP.pack(data_tbl)
	driver:on_data(data)
end


--tests.modules()
tests.parse()

