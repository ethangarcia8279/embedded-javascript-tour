--[[
使用串口进行本地配置

通过 op_com.cmd_dict 可以进行本地指令注册
比如 op_com.cmd_dict["ipport"] = ... 注册完后, 可以通过使用串口输入 "ipport" 查询IPPORT 配置, 也可通过 "ipport,XXX.XXX.XXX.XXX,XXXX" 设置IPPORT配置
]]--

local this = {}

local op_com = require "op_com"

-- 这个是 usb 虚拟串口, 换成 uart1 等物理串口也行
local UART_ID = uart.VUART_0
local rxbuff = zbuff.create(4096)
-- 这样可以被其他文件引用
this.rxbuff = rxbuff
-- 下面这几个是传输文件用的
local rti = 0 -- recv tts index
local rtl = 0 -- recv tts len
local rff = nil -- recv file File*
local rfi = 0 -- recv file index
local rfl = 0 -- recv file len
-- local rfs = false -- recv file system, false: 保存到非fs区, true: 保存到 fs 区

-- 使用 sscom 发送指令需要将 gb2312 转换成 utf8
local function gb2312ToUtf8(gb2312s)
    local cd = iconv.open("ucs2", "gb2312")
    local ucs2s = cd:iconv(gb2312s)
    cd = iconv.open("utf8", "ucs2")
    return cd:iconv(ucs2s)
end

-- 会显示好多东西，所以就不开放这个了
-- op_com.cmd_dict["help"] = function()
--     local _ret = {}
--     for k,v in pairs(op_com.cmd_dict) do
--         table.insert(_ret,k)
--     end
--     local _ret = json.encode(_ret)
--     return _ret
-- end

-- 下面随便添加一些指令
op_com.cmd_dict["flyoff"] = function()
    mobile.flymode(0,false)
    return "flyoff"
end
op_com.cmd_dict["flyon"] = function()
    mobile.flymode(0,true)
    return "flyon"
end
op_com.cmd_dict["iccid"] = function()
    return mobile.iccid() or ""
end
op_com.cmd_dict["imei"] = function()
    return mobile.imei() or ""
end
op_com.cmd_dict["ls"] = function(cmdl)
    local ret, data = io.lsdir(cmdl[2], 50, 0)
    if ret then
    log.info("fs", "lsdir", #data, json.encode(data))
    else
    log.info("fs", "lsdir", "fail", ret, data)
    end
    return json.encode(data)
end
op_com.cmd_dict.reboot = function(cmdl)
    sys.taskInit(function()
        sys.wait(500)
        op_com.reboot()
    end)
    return "will reboot"
end

-- 获取状态
op_com.cmd_dict.get_status = function()
    local allmem,nowmem,maxmem = rtos.meminfo()
    op_com.g.nowmem = string.format("%.2f%%",nowmem/allmem*100)
    op_com.g.maxmem = string.format("%.2f%%",maxmem/allmem*100)
    local data = {
        csq = mobile.csq() or "",
        g = op_com.g,
    }
    return json.encode(data)
end



-- uart usb
local function task_parse_cmd()
    while true do
        local result,id = sys.waitUntil("rxbuff")
        local cmdl = rxbuff:query():trim():split(",",true)
        print("cmdl[1]:",cmdl[1])

        func = op_com.cmd_dict[cmdl[1]]
        if type(func) == "function" then
            local ret = func(cmdl)
            if ret and #ret > 0 then
                uart.write(id,ret)
            end
        end

        rxbuff:seek(0)
    end
end


local function read(id,len)
    uart.read(id,len,rxbuff)
    -- 这个和下面那个是传文件用的, 在 air780e 上可用, 在 air8000 上未做测试, 需要加 sfud 外设
    if rfl > 0 then
        rfl = rfl - len
        print("recv: ",len, rxbuff:used(),"rfl: ",rfl)
        local tmpq = rxbuff:query()
        if #tmpq > 0 then
            rff:write(tmpq)
            rfi = rfi + len
            rxbuff:seek(0)
            if rfl <= 0 then
                rfl = 0
                rfi = 0
                rff:close()
                print("finish")
            end
        end
        uart.write(id,"C")
    elseif rtl > 0 then
        print("recv: ",len, rxbuff:used())
        rtl = rtl - len
        -- sfud.write(sfud_device,rti,rxbuff:query(0,len))
        sfud.write(sfud_device,rti,rxbuff:query())
        rti = rti + len
        rxbuff:seek(0)
        if rtl <= 0 then
            rtl = 0
            rti = 0
        end
        uart.write(id,"C")
    -- 这是透出功能
    elseif op_com.g2.in_sensor_tc then
        if (rxbuff:used() == 3) and (rxbuff:query() == "***") then
            op_com.g2.in_sensor_tc = false
            rxbuff:copy(0,"stc,off")
            sys.publish("rxbuff",id)
        else
            -- 这里透传给了12号串口
            uart.write(12,rxbuff:query())
            rxbuff:seek(0)
        end
    -- 这里就进行指令解析了
    else
        if rxbuff:used() > 0 then
            sys.publish("rxbuff",id)
        end
    end
end

-- 进入文件接收模式
op_com.cmd_dict["recv_file"] = function(cmdl)
    -- recv_file,/spiffs/update.bin,15364
    print("recv_file, ",json.encode(cmdl))
    local fn = cmdl[2]
    rfl = tonumber(cmdl[3]) or 0
    print("fn:",fn,"rfl:",rfl)
    if fn and rfl and rfl > 0 then
        rff = io.open(fn,"wb")
        rfi = 0
        return "C"
    end
    return "E"
end

-- 配置 IPPORT
op_com.cmd_dict["ipport"] = function(cmdl)
    if #cmdl == 1 then
        return op_com.cfg["IPPORT"]
    elseif #cmdl == 2 then
        if cmdl[2]:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$") then
            op_com.set_cfg("IPPORT",cmdl[2])
            return "ok"
        end
        return "format error"
    end
end

-- 查询内存使用情况
op_com.cmd_dict["meminfo"] = function(cmdl)
    local total_sys, used_sys, max_used_sys = rtos.meminfo("sys")
    local total_lua, used_lua, max_used_lua = rtos.meminfo("lua")
    local total_psram, used_psram, max_used_psram = rtos.meminfo("psram")
    local ret = "\r\ntotal, used, max_used\r\n".."sys: "..total_sys..", "..used_sys..", "..max_used_sys.."\r\n".."lua: "..total_lua..", "..used_lua..", "..max_used_lua.."\r\n".."psram: "..total_psram..", "..used_psram..", "..max_used_psram.."\r\n"
    return ret
end



function this.init()
    sys.taskInit(function()
        uart.setup(UART_ID,115200,8,1)
        uart.on(UART_ID,"receive",read)

        sys.taskInit(task_parse_cmd)
    end)
end


return this
