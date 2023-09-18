﻿local lu = require('luaunit')
local utils = require('utils')

package.cpath = package.cpath  .. ';D:\\Distrib\\lua\\ZeroBraneStudioEduPack\\bin\\clibs52\\?.dll'

local mark_helper = require 'sum_mark_helper'
local xml_utils = require "xml_utils"
local algorithm = require 'algorithm'

local function read_file(path)
    local f = assert(io.open(path, 'rb'))
    local res = f:read('*a')
    if res:sub(1,3) == '\xef\xbb\xbf' then
        res = res:sub(4)
    end
    f:close()
    return res
end

local gapUserXml = [[
    <ACTION_RESULTS version="1.4">
        <PARAM name="ACTION_RESULTS" channel="17" value="CalcRailGap_User">
            <PARAM name="FrameNumber" value="0" coord="1976397">
                <PARAM name="Result" value="main">
                    <PARAM name="Coord" type="polygon" value="812,446 812,396 830,396 830,446"/>
                    <PARAM name="RailGapWidth_mkm" value="123000"/>
                </PARAM>
            </PARAM>
        </PARAM>
        <PARAM name="ACTION_RESULTS" channel="19" value="CalcRailGap_Head_Top">
            <PARAM name="FrameNumber" value="0" coord="1976397">
                <PARAM name="Result" value="main">
                    <PARAM name="Coord" type="polygon" value="812,446 812,396 830,396 830,446"/>
                    <PARAM name="RailGapWidth_mkm" value="18000"/>
                </PARAM>
            </PARAM>
        </PARAM>
    </ACTION_RESULTS>]]

local function makeCrewJointXml(states)
    local xml = '<ACTION_RESULTS version="1.4">'
    xml = xml .. '<PARAM name="ACTION_RESULTS" channel="18" value="CrewJoint">' ..
                '<PARAM name="FrameNumber" value="-1" coord="437753">' ..
                '<PARAM name="Result" value="main">'
    for n, val in ipairs(states) do
        xml = xml .. string.format(
            '<PARAM name="JointNumber" value="%d">' ..
            '<PARAM name="Coord" type="ellipse" value="981,457,26,43"/>' ..
            '<PARAM name="CrewJointSafe" value="%d"/>' ..
            '</PARAM>', n, val)
    end
    xml = xml .. '</PARAM></PARAM></PARAM>'
    xml = xml .. '</ACTION_RESULTS>'
    return xml
end

-- ====================== ШИРИНА ЗАЗОРА ===============================

function TestGetAllGapWidth()
    local gap_xml = read_file('test_data/gap1.xml')
    local mark = {ext = {
            VIDEOIDENTGWT = 1,
            VIDEOIDENTGWS = 2,
            RAWXMLDATA = gap_xml,
        }}
    local res = mark_helper.GetAllGapWidth(mark)
    lu.assertEquals(res, {
        CalcRailGap_Head_Side = {[17]=16, [19]=12},
        CalcRailGap_Head_Top = {[17]=18, [19]=12},
        VIDEOIDENTGWS = {[0] = 2},
        VIDEOIDENTGWT = {[0] = 1}
    })
end

function TestGetGapWidth()
    local gap_xml = read_file('test_data/gap1.xml')
    local mark = {prop = {ChannelMask = bit32.lshift(1, 18),}, ext = {}}
    lu.assertEquals({mark_helper.GetGapWidth(mark)}, {})

    mark.ext["RAWXMLDATA"] = gap_xml
    lu.assertEquals({mark_helper.GetGapWidth(mark)}, {12, 19})

    mark.ext["VIDEOIDENTGWT"] = 1
    mark.ext["VIDEOIDENTGWS"] = 2
    lu.assertEquals({mark_helper.GetGapWidth(mark)}, {2, 18})

    mark.ext["RAWXMLDATA"] = gapUserXml
    lu.assertEquals({mark_helper.GetGapWidth(mark)}, {123, 17})
end


function TestGetGapWidthName()
    local gap_xml = read_file('test_data/gap1.xml')
    local mark = {prop = {
        ChannelMask = bit32.lshift(1, 17),
    },
    ext = {
        VIDEOIDENTGWT = 1,
        VIDEOIDENTGWS = 2,
        RAWXMLDATA = gap_xml,
    }}
    lu.assertEquals({mark_helper.GetGapWidthName(mark)}, {2, 17})
    lu.assertEquals({mark_helper.GetGapWidthName(mark, 'inactive')}, {12, 19})
    lu.assertEquals({mark_helper.GetGapWidthName(mark, 'active')}, {16, 17})
    lu.assertEquals({mark_helper.GetGapWidthName(mark, 'thread')}, {12, 19})
    lu.assertEquals({mark_helper.GetGapWidthName(mark, 'user')}, {2, 17})
end

function TestGetRailGapStep()
    local mark = {ext = {RAWXMLDATA = "" }}
    mark.ext.RAWXMLDATA = read_file('test_data/gap1.xml')
    lu.assertIsNil(mark_helper.GetRailGapStep(mark))

    mark.ext.RAWXMLDATA = read_file('test_data/gap2.xml')
    lu.assertEquals(mark_helper.GetRailGapStep(mark), -5)
end

-- ============================ Маячные отметки ============================== --

function TestGetBeaconOffset()
    local mark = {ext = {RAWXMLDATA = read_file('test_data/beacon1.xml') }}
    _G["Passport"] = {INCREASE='1'}
    lu.assertEquals(mark_helper.GetBeaconOffset(mark), 11)

    _G["Passport"] = {INCREASE='0'}
    lu.assertEquals(mark_helper.GetBeaconOffset(mark), -11)
end

-- ================================= БОЛТЫ ====================================

function TestGetCrewJoint()
    local mark = {ext = {RAWXMLDATA = "" }}

    mark.ext.RAWXMLDATA = read_file('test_data/gap1.xml')
    lu.assertEquals(mark_helper.GetCrewJointArray(mark), {2, 3, 2, 3, 2, 3})
    lu.assertEquals({mark_helper.GetCrewJointCount(mark)}, {6, 0})

    mark.ext.RAWXMLDATA = read_file('test_data/gap2.xml')
    lu.assertEquals(mark_helper.GetCrewJointArray(mark), {3, 2, -1, -1, 3, 2})
    lu.assertEquals({mark_helper.GetCrewJointCount(mark)}, {6, 2})

    mark.ext.RAWXMLDATA = read_file('test_data/beacon1.xml')
    lu.assertIsNil(mark_helper.GetCrewJointArray(mark))
    lu.assertIsNil(mark_helper.GetCrewJointCount(mark))
end

function TestCalcValidCrewJointOnHalf()
    local mark = {ext = {RAWXMLDATA = "" }}

    mark.ext.RAWXMLDATA = read_file('test_data/gap2.xml')
    lu.assertEquals({mark_helper.CalcValidCrewJointOnHalf(mark)}, {2, 1, 6})

    mark.ext.RAWXMLDATA = makeCrewJointXml({1,-1,2,3})
    lu.assertEquals({mark_helper.CalcValidCrewJointOnHalf(mark)}, {1, 1, 4})

    mark.ext.RAWXMLDATA = makeCrewJointXml({1, 2, 3, 2, 1})
    lu.assertEquals({mark_helper.CalcValidCrewJointOnHalf(mark)}, {2, 1, 6})

    mark.ext.RAWXMLDATA = makeCrewJointXml({1, -1, -1, -1, 1, 1})
    lu.assertEquals({mark_helper.CalcValidCrewJointOnHalf(mark)}, {1, 2, 6})

    mark.ext.RAWXMLDATA = makeCrewJointXml({-1, -1, -1, 1, 1, 1})
    lu.assertEquals({mark_helper.CalcValidCrewJointOnHalf(mark)}, {0, 3, 6})
end

-- =================== Накладка ===================

function TestGetFishplateState()
    local mark = {ext = {RAWXMLDATA = "" }}

    mark.ext.RAWXMLDATA = read_file('test_data/gap1.xml')
    lu.assertEquals({mark_helper.GetFishplateState(mark)}, {-1, 0})

    mark.ext.RAWXMLDATA = read_file('test_data/gap3.xml')
    lu.assertEquals({mark_helper.GetFishplateState(mark)}, {4, 1})

    mark.ext.RAWXMLDATA = read_file('test_data/beacon1.xml')
    lu.assertEquals({mark_helper.GetFishplateState(mark)}, {-1, 0})
end

-- =================== Скрепления ===================

function TestIsFastener()
    local mark = {ext = {RAWXMLDATA = "" }}

    mark.ext.RAWXMLDATA = read_file('test_data/gap1.xml')
    lu.assertIsNil(mark_helper.IsFastenerDefect(mark))
    lu.assertEquals(mark_helper.GetFastenetParams(mark), {RecogObjCoord=1977218})

    mark.ext.RAWXMLDATA = read_file('test_data/fastener1.xml')
    lu.assertIsTrue(mark_helper.IsFastenerDefect(mark))
    lu.assertEquals(mark_helper.GetFastenetParams(mark), {
        Coord="863,0,863,214,1013,214,1013,0",
        FastenerFault=1,
        FastenerType=0,
        RecogObjCoord=1994743,
        Reliability=95,
        frame_coord=1993805})
end

-- =================== Поверхностные дефекты ===================

function TestGetSurfDefectPrm()
    local mark = {ext = {RAWXMLDATA = "" }}

    mark.ext.RAWXMLDATA = read_file('test_data/fastener1.xml')
    lu.assertEquals(mark_helper.GetSurfDefectPrm(mark), {})

    mark.ext.RAWXMLDATA = read_file('test_data/surface1.xml')
    lu.assertEquals(mark_helper.GetSurfDefectPrm(mark), {
        Coord="239,774 239,876,397,876 397,774",
        Reliability="95",
        SurfaceArea=0.1,
        SurfaceFault=0,
        SurfaceLength=10.2,
        SurfaceWidth=15.8})
end

-- =================== Коннекторы ===================

function TestConnectors()
    local mark = {ext = {RAWXMLDATA = "" }}

    mark.ext.RAWXMLDATA = read_file('test_data/gap1.xml')
    lu.assertEquals(mark_helper.GetConnectorsArray(mark), {0, 0})
    lu.assertEquals({mark_helper.GetConnectorsCount(mark)}, {2, 0})

    mark.ext.RAWXMLDATA = read_file('test_data/gap2.xml')
    lu.assertEquals(mark_helper.GetConnectorsArray(mark), {1, 0, 1})
    lu.assertEquals({mark_helper.GetConnectorsCount(mark)}, {3, 2})
end

function TestWeldedBond()
    local mark = {ext = {RAWXMLDATA = "" }}

    mark.ext.RAWXMLDATA = read_file('test_data/gap1.xml')
    lu.assertIsNil(mark_helper.GetWeldedBondStatus(mark))
    lu.assertEquals(mark_helper.GetWeldedBondDefectCode(mark), "090004000521")

    mark.ext.RAWXMLDATA = read_file('test_data/gap2.xml')
    lu.assertEquals(mark_helper.GetWeldedBondStatus(mark), 0)
    lu.assertIsNil(mark_helper.GetWeldedBondDefectCode(mark))

    mark.ext.RAWXMLDATA = read_file('test_data/gap3.xml')
    lu.assertEquals(mark_helper.GetWeldedBondStatus(mark), 1)
    lu.assertEquals(mark_helper.GetWeldedBondDefectCode(mark), "090004000521")
end

-- =================== Шпалы ===================

function TestGetSleeper()
    local mark = {ext = {RAWXMLDATA = "" }}

    mark.ext.RAWXMLDATA = read_file('test_data/sleeper1.xml')
    lu.assertEquals(mark_helper.GetSleeperParam(mark), {
        Angle_mrad=-104,
        AxisSysCoord_mm=2344347,
        Material=1})
    lu.assertEquals(mark_helper.GetSleeperAngle(mark), -104)
    lu.assertEquals(mark_helper.GetSleeperFault(mark), {})
    lu.assertEquals(mark_helper.GetSleeperMeterial(mark), 1)

    mark.ext.RAWXMLDATA = read_file('test_data/sleeper2.xml')
    lu.assertEquals(mark_helper.GetSleeperParam(mark), {
        Angle_mrad=999,
        AxisSysCoord_mm=2284796,
        Material=0})
    lu.assertEquals(mark_helper.GetSleeperAngle(mark), 999)
    lu.assertEquals(mark_helper.GetSleeperFault(mark), {
        Coord="348,444,572,444,572,397,348,397",
        FaultType=2,
        Material=1})
    lu.assertEquals(mark_helper.GetSleeperMeterial(mark), 0)

    mark.ext["SLEEPERS_ANGLE"] = 123
    mark.ext["SLEEPERS_METERIAL"] = 2
    lu.assertEquals(mark_helper.GetSleeperAngle(mark), 123)
    lu.assertEquals(mark_helper.GetSleeperMeterial(mark), 2)
end

function TestCheckSleeperEpure()
    lu.assertEquals({mark_helper.CheckSleeperEpure(nil, 1840, 4, 540, 1)}, {true, ""})
    lu.assertEquals({mark_helper.CheckSleeperEpure(nil, 1840, 4, 2160, 1)}, {true, ""})
    lu.assertEquals({mark_helper.CheckSleeperEpure(nil, 1840, 3, 2160, 1)}, {false, "090004000375"})
    lu.assertEquals({mark_helper.CheckSleeperEpure(nil, 1840, 4, 540, 2)}, {true, ""})
    lu.assertEquals({mark_helper.CheckSleeperEpure(nil, 1840, 1, 543+82, 1)}, {false, "090004000375"})
    lu.assertEquals({mark_helper.CheckSleeperEpure(nil, 1840, 1, 543+163, 2)}, {false, "090004000370"})
end

-- =================== Вспомогательные ===================

function TestFilterMarks()
    local src = {1,2,3,4,5,6}
    lu.assertEquals(mark_helper.filter_marks(src, function (i)
        return i%2 == 0
    end), {2,4,6})
end

function TestFilterUserAccept()
    local function make_marks(values)
        local res = {}
        for i, val in ipairs(values) do
            res[i] = {prop = {ID = i}, ext = {ACCEPT_USER = val},}
        end
        return res
    end

    local marks = make_marks{-1, 0, 1, 2, 3}
    local values = {[-1]=true, [0]=false, [1]=true}
    local res = mark_helper.filter_user_accept(marks, values)
    res = algorithm.map(function (m) return m.prop.ID end, res)
    lu.assertEquals(res, {1, 3})
end

-- TODO: sort_marks
-- TODO: sort_stable
-- TODO: sort_mark_by_coord

function TestFormatCoord()
    local mark = {prop = {SysCoord = 12345678 }}
    _G["Driver"] = {
        GetPathCoord = function (self, coord)
            return
                utils.round(coord / 1000000, 0),
                utils.round(coord / 1000 % 1000, 0),
                utils.round(coord % 1000, 0)
        end
    }

    lu.assertEquals(mark_helper.format_path_coord(mark), "12 км 346.7 м")
    lu.assertEquals(mark_helper.format_sys_coord(12345678), "12.345.678")
end

function TestGetRail()
    _G["Passport"] = {FIRST_LEFT='0'}

    local mark = {prop = {RailMask = 1 }}
    lu.assertEquals(mark_helper.GetRailName(mark), "Правый")
    lu.assertEquals(mark_helper.GetMarkRailPos(mark), 1)

    _G["Passport"] = {FIRST_LEFT='1'}
    lu.assertEquals(mark_helper.GetRailName(mark), "Левый")
    lu.assertEquals(mark_helper.GetMarkRailPos(mark), -1)

    lu.assertEquals(mark_helper.GetRailName(2), "Правый")
    lu.assertEquals(mark_helper.GetRailName(3), "Оба")
    lu.assertEquals(mark_helper.GetRailName(1), "Левый")

    lu.assertEquals(mark_helper.GetMarkRailPos(2), 1)
    lu.assertEquals(mark_helper.GetMarkRailPos(3), 0)
    lu.assertEquals(mark_helper.GetMarkRailPos(1), -1)

    _G["Passport"] = {FIRST_LEFT='0'}
    lu.assertEquals(mark_helper.GetRailName(1), "Правый")
    lu.assertEquals(mark_helper.GetRailName(3), "Оба")
    lu.assertEquals(mark_helper.GetRailName(2), "Левый")

    lu.assertEquals(mark_helper.GetMarkRailPos(1), 1)
    lu.assertEquals(mark_helper.GetMarkRailPos(3), 0)
    lu.assertEquals(mark_helper.GetMarkRailPos(2), -1)
end

function TestGetTemperature()
    _G["Driver"] = {
        GetTemperature = function (self, rail, coord)
            if rail == 0 then
                return {target = coord / 10}
            elseif rail == 1 then
                return {head = coord / 20}
            end
        end
    }

    local mark = {prop = {
        RailMask = 1,
        SysCoord = 123,
        }}
    lu.assertEquals(mark_helper.GetTemperature(mark), 12)
    mark.prop.RailMask = 2
    lu.assertEquals(mark_helper.GetTemperature(mark), 6)
end


function TestMakeCommonMarkTemplate()
    _G["Passport"] = {
        INCREASE='1',
        FIRST_LEFT='0',
    }

    _G["Driver"] = {
        GetTemperature = function (self, rail, coord)
            return {target = 15}
        end,
        GetSumTypeName = function (self, g)
            return g .. g
        end,
        GetGPS = function (self, c)
            return (c % 180.1 - 90), (c % 360.1-180)
        end,
        GetPathCoord = function (self, coord)
            return
                utils.round(coord / 1000000, 0),
                utils.round(coord / 1000 % 1000, 0),
                utils.round(coord % 1000, 0)
        end,
    }

    local mark = {prop = {
        ID = 123,
        RailMask = 1,
        SysCoord = 1000000,
        Len = 1000,
        Guid = 'guid',
        Description = 'desc',
        }}
    lu.assertEquals(mark_helper.MakeCommonMarkTemplate(mark),{
        BEGIN_KM=1,
        BEGIN_M=0,
        BEGIN_MM=0,
        BEGIN_M_MM1="0.0",
        BEGIN_M_MM2="0.00",
        BEGIN_PATH="1 км 0.0 м",
        BEGIN_PK="1",
        KM=1,
        M=1,
        MM=500,
        M_MM1="1.5",
        M_MM2="1.50",
        PATH="1 км 1.5 м",
        PK="1",
        END_KM=1,
        END_M=1,
        END_MM=0,
        END_M_MM1="1.0",
        END_M_MM2="1.00",
        END_PATH="1 км 1.0 м",
        END_PK="1",
        mark_id=123,
        SYS=1000000,
        LENGTH=1000,
        GUID="guid",
        TYPE="guidguid",
        DESCRIPTION='desc',
        RAIL_RAW_MASK=1,
        RAIL_POS=1,
        RAIL_NAME="прав.",
        RAIL_TEMP="+15.0",
        LAT="-45 29' 60.000''",
        LAT_RAW="-45.50000000",
        LON="-37 48' 0.000''",
        LON_RAW="-37.80000000",
        DEFECT_CODE="",
        DEFECT_DESC="",
    })
end

function TestGetRecognitionStartInfo()
    local function  make_mark (id, desc)
        return {prop={
            ID = id,
            Description= desc}}
    end

    _G["Driver"] = {
        GetMarks = function (self, params)
            if params.ListType == 'all' and #params.GUIDS == 1 and params.GUIDS[1] == '{1D5095ED-AF51-43C2-AA13-6F6C86302FB0}' then
                return {
                    make_mark(153723, 'RECOGNITION_START=1626438103\nRECOGNITION_TYPE=EXPRESS\nRECOGNITION_MODE=OFFLINE\nRECOGNITION_DLL_VERSION=2.8.9.2\nRECOGNITION_DLL_CTIME=1551361609'),
                    make_mark(1,      'RECOGNITION_START=1626438103\nRECOGNITION_TYPE=EXPRESS\nRECOGNITION_MODE=ONLINE\nRECOGNITION_DLL_VERSION=2.8.9.2\nRECOGNITION_DLL_CTIME=1551361609'),
                    make_mark(153046, 'RECOGNITION_START=1574944589\nRECOGNITION_TYPE=FULL\nRECOGNITION_MODE=OFFLINE\nRECOGNITION_DLL_VERSION=3.0.0.3\nRECOGNITION_DLL_CTIME=1528904526'),
                }
            end
        end,
    }
    lu.assertEquals(mark_helper.GetRecognitionStartInfo(), {
        {RECOGNITION_DLL_CTIME="1551361609", RECOGNITION_DLL_VERSION="2.8.9.2", RECOGNITION_MODE="ONLINE", RECOGNITION_START="1626438103", RECOGNITION_TYPE="EXPRESS" },
        {RECOGNITION_DLL_CTIME="1528904526", RECOGNITION_DLL_VERSION="3.0.0.3", RECOGNITION_MODE="OFFLINE", RECOGNITION_START="1574944589", RECOGNITION_TYPE="FULL" },   
        {RECOGNITION_DLL_CTIME="1551361609", RECOGNITION_DLL_VERSION="2.8.9.2", RECOGNITION_MODE="OFFLINE", RECOGNITION_START="1626438103", RECOGNITION_TYPE="EXPRESS" },
    })
end

os.exit( lu.LuaUnit.run() )
