dofile('xml_parse.lua')

local example_xml = [[
<?xml version="1.0" encoding="iso-8859-1" ?>
<library lib='123'>
	Oo! text
  <book id='1'>
    <title>Green Eggs and Ham</title>
    <author>Dr. Seuss</author>
  </book>
  <book id='2'>
    <title>Where the Wild Things Are</title>
    <author>Maurice Sendak</author>
  </book>
</library>
]]

local x2 = [[
<?xml version="1.0" encoding="windows-1251"?>
<ACTION_RESULTS version='1.4'>
	<PARAM name='ACTION_RESULTS' value='CalcRailGap_Head_Top'>
		<PARAM name='FrameNumber' value='0' coord='50771'>
			<PARAM name='Result' value='main'>
				<PARAM name='Coord' type='polygon' value='350,206 349,159 373,159 372,206' />
				<PARAM name='RailGapWidth_mkm' value='12333'/>
			</PARAM>
		</PARAM>
		<PARAM name='FrameNumber' value='1' coord='50864'>
			<PARAM name='Result' value='main'>
				<PARAM name='Coord' type='polygon' value='537,202 552,159 556,159 541,202' />
				<PARAM name='RailGapWidth_mkm' value='2569'/>
			</PARAM>
		</PARAM>
		<PARAM name='FrameNumber' value='-2' coord='50586'>
			<PARAM name='Result' value='main'>
				<PARAM name='Coord' type='polygon' value='4,205 -3,170 -2,170 10,205' />
				<PARAM name='RailGapWidth_mkm' value='2312'/>
			</PARAM>
		</PARAM>
	</PARAM>
	<PARAM name='ACTION_RESULTS' value='CalcRailGap_Head_Side'>
		<PARAM name='FrameNumber' value='0' coord='50771'>
			<PARAM name='Result' value='main'>
				<PARAM name='Coord' type='polygon' value='366,159 366,147 384,147 384,159' />
				<PARAM name='RailGapWidth_mkm' value='9250'/>
			</PARAM>
		</PARAM>
	</PARAM>
	<PARAM name='ACTION_RESULTS' value='Fishplate'>
		<PARAM name='FrameNumber' value='-4' coord='50401'>
			<PARAM name='Result' value='main'>
				<PARAM name='FishplateEdge' value='1'>
					<PARAM name='Coord' type='polygon' value='617,127 617,51'/>
				</PARAM>
			</PARAM>
		</PARAM>
		<PARAM name='FrameNumber' value='4' coord='51139'>
			<PARAM name='Result' value='main'>
				<PARAM name='FishplateEdge' value='2'>
					<PARAM name='Coord' type='polygon' value='108,127 108,51'/>
				</PARAM>
			</PARAM>
		</PARAM>
	</PARAM>
	<PARAM name='ACTION_RESULTS' value='Common'>
		<PARAM name='Reliability' value='100'/>
	</PARAM>
</ACTION_RESULTS>
]]



print(x2)

function parse_ActionResult(ar)
	local r = xml2table(ar)
	
	local startwith = function (String, Start)
		return string.sub(String, 1, string.len(Start)) == Start
	end
	
	local parseFN = function(fnum, coords)
		local w = fnum.PARAM.PARAM[2]._attr
		coords[fnum._attr.value] = w.value
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
 
 local l = parse_ActionResult(x2)
 print (l)
 
local a = {[2]= 2, [0]=0, [-2]=-2} 
print (dump(a))