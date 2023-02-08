-- https://bt.abisoft.spb.ru/view.php?id=932
-- https://bt.abisoft.spb.ru/view.php?id=1006

local GUIDS =
{
	"{29FF08BB-C344-495B-82ED-00000000000C}", -- Дефектоподобн.пачка в зоне болт.стыка -- TYPES.OTMETKA_12,
	"{29FF08BB-C344-495B-82ED-000000000010}", -- Дефектоподобн.пачка в Ч/Р -- TYPES.OTMETKA_16,
}


local LEVEL =
{
	HI      = 1,
	MED     = 2,
	LO      = 3,
	NONE    = 4,
}

local function get_recog_params(mark)
	local desc = mark.Description or mark.prop.Description  -- отметка из sum_process.lua или нового типа
    if type(desc) == "string" then
        local IP, CN, G = string.match(desc, "IP:%s*(%d+)%s*CN:%s*(%d+)%s*G:%s*(%d+)")
	    return tonumber(IP), tonumber(CN), tonumber(G)
    end
end

local function get_lvl(mark)
    local IP, CN, G = get_recog_params(mark)
    if IP then
        if        1 <= IP and IP <= 200  then   return  LEVEL.NONE
        elseif  201 <= IP and IP <= 600  then   return  LEVEL.LO
        elseif  601 <= IP and IP <= 1400 then   return  LEVEL.MED
        elseif 1401 <= IP                then   return  LEVEL.HI
        end
    end
end


-- =======================================================

return
{
    LEVEL = LEVEL,
    GUIDS = GUIDS,
    get_lvl = get_lvl,
    get_recog_params = get_recog_params
}
