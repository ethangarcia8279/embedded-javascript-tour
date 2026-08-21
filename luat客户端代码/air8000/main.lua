--[[

]]
PROJECT = "AIR8000_WA"
VERSION = "1.0.1"
PRODUCT_KEY = "YourProductKey"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

-- mobile.flymode(0,true)
if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- mcu.hardfault(0)    --死机后停机，一般用于调试状态
mcu.hardfault(1)    --死机后重启
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300) -- 所有GPIO高电平输出3.3V

local op_com = require "op_com"
local op_errdump = require "op_errdump"
local op_lccfg = require "op_lccfg"
local wa = require "weaving_app"

sys.taskInit(function ()
    errDump.config(true, 0)
    op_com.init()
    -- 建议在 op_errdump.init() 之前通过 rtc 外设配置好时间, 否则 errdump.load_errDump 加载的时间会不对
    op_errdump.init()
    op_lccfg.init()
    wa.start()
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
