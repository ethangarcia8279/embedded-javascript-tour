local this = {}

--[[
pdata is protocol data or pack data
bdata is binary data
]]--

----------------------- crc begin ------------------------
-- crc16_xmodem
-- 0x11 0x22 0x33 0x44 crc is 0xdd 0x33
-- 0x12 0x34 0x56 0x78 crc is 0xb4 0x2c

-- 位操作
-- >> bit.rshift(value,shift)
-- << bit.lshift(value,shift)
-- ^  bit.bxor(val1,val2,...,valn)
-- |  bit.bor(val1,val2,...,valn)
-- &  bit.band(val1,val2,...,valn)

-- 添加CRC校验字
-- b: the bytes will add crc
local function ConCRC(b)
    return b..pack.pack(">H",crypto.crc16("XMODEM",b))
end

-- CRC数据验证
-- b: the bytes will check crc
local function DataCRC(b)
    -- log.info('DataCRC','b is '..b:toHex())
    return b:sub(-2,-1) == pack.pack(">H",crypto.crc16("XMODEM",b:sub(1,-3)))
end
----------------------- crc end ------------------------

----------------------- net begin -----------------------

-- local rxbuf = zbuff.create(1024)
local rxbuf = zbuff.create(128)
local all_bdata = ""
local flag_start_4G = false
local netc


local function netCB(netc, event, param)
    if param ~= 0 then
        sys.publish("socket_disconnect")
        return
    end
	if event == socket.LINK then
	elseif event == socket.ON_LINE then
        sys.publish("socket_connected") -- use for netLed.lua
        if type(this.on_connect) == "function" then
            this.on_connect()
        end
        -- socket.tx(netc, "hello,luatos!")
	elseif event == socket.EVENT then
        socket.rx(netc, rxbuf)
        socket.wait(netc)
        if rxbuf:used() > 0 then
            -- log.info("收到", rxbuf:toStr(0,rxbuf:used()):toHex())
            -- log.info("发送", rxbuf:used(), "bytes")
            -- socket.tx(netc, rxbuf)
            all_bdata = all_bdata .. rxbuf:query()
            sys.publish("proc_pdata")
        end
        rxbuf:del()
	elseif event == socket.TX_OK then
        socket.wait(netc)
        log.info("发送完成")
	elseif event == socket.CLOSE then
        sys.publish("socket_disconnect")
    end
end

local function socketTask()
    log.info("socketTask")
	netc = socket.create(nil, netCB)
	-- socket.debug(netc, true)
	socket.config(netc, nil, nil, nil, 300, 5, 6)   --开启TCP保活，防止长时间无数据交互被运营商断线
    while true do
        flag_start_4G = true
        while true do
            if this.server_ip == "" or this.server_port == 0 then
                sys.wait(5000)
            else
                local succ, result = socket.connect(netc, this.server_ip, this.server_port)
                if not succ then
                    log.info("未知错误，5秒后重连")
                else
                    local result, msg = sys.waitUntil("socket_disconnect")
                end
                if flag_start_4G then
                    log.info("服务器断开了，5秒后重连")
                    socket.close(netc)
                    log.info(rtos.meminfo("sys"))
                    sys.wait(5000)
                else
                    break
                end
            end
        end
    end
end

----------------------- net end -------------------------

this.wcmd_dict = {} -- weaving_socket cmd
this.cmd_dict = {} -- user cmd

local function weaving_pack(icmd,bdata)
    -- 为了方便固定将长度编码为2字节，最大发送65536字节
    local lens = pack.pack("<H",#bdata)
    len_lens = lens:len() -- int
    local ret = string.char(icmd)..string.char(len_lens)..lens
    ret = ConCRC(ret)..bdata
    return ret
end

local function weaving_unpack(bdata)
    flag_result = false
    local icmd = 0x00
    bmsg = ""
    local len_blen = 0
    local len_bdata = 0

    while true do
        if #bdata < 4 then
            return flag_result, icmd, bmsg, bdata
        end
        len_blen = string.byte(bdata,2)
        if #bdata < len_blen+4 then
            return flag_result,icmd,bmsg,bdata
        end
        len_bdata = 0
        for i = 1,len_blen do
            len_bdata = len_bdata + bit.lshift(string.byte(bdata,2+i),(i-1)*8)
        end
        if #bdata < len_blen+4+len_bdata then
            return flag_result,icmd,bmsg,bdata
        end
        if DataCRC(bdata:sub(1,4+len_blen)) then
            return true, string.byte(bdata,1), bdata:sub(5+len_blen,4+len_blen+len_bdata), bdata:sub(5+len_blen+len_bdata)
        end -- else continue
    end
end

local function proc_pdata()
    local flag_result, icmd, bmsg
    flag_result, icmd, bmsg, all_bdata = weaving_unpack(all_bdata)
    if(flag_result) then
        local func = this.wcmd_dict[icmd]
        if type(func) == "function" then
            sys.taskInit(func,bmsg)
        end
        return true
    else
        return false
    end
end

local function task_proc_pdata()
    while true do
        sys.waitUntil("proc_pdata")
        local flag_need_proc = true
        while flag_need_proc do
            flag_need_proc = proc_pdata()
        end
    end
end

local last_msgid = nil
local last_msgid_05 = nil

function this.proc_bmsg(bmsg)
    local dmsg,result,errinfo = json.decode(bmsg)
    log.info("json:",bmsg)
    if result then
        log.info('task_parse: ','json decode ok')
        local msgid = dmsg['msgid']
        -- dmsg 中不含 msgid 的话就一定执行 cmd, 否则根据 msgid 做判断
        if msgid then
            -- 首次接受到 msgid 肯定要执行并记录
            if not last_msgid then
                last_msgid = msgid
            else
                if msgid > last_msgid then
                    last_msgid = msgid
                else
                    log.info('weaving_client.proc_bmsg: ','recv past msgid: '..msgid)
                    return
                end
            end
        end
        local cmd = dmsg['cmd']
        local func = this.cmd_dict[cmd]
        if type(func) == "function" then
            func(dmsg)
        end
    else
        log.info('weaving_client.proc_bmsg: ','json errinfo:'..errinfo)
    end
end

this.send_data = function(cmd,bdata)
    if netc then
        local bdata = weaving_pack(cmd,bdata)
        socket.tx(netc, bdata)
    end
end

this.reg_wcmd = function(cmd,func)
    this.wcmd_dict[cmd] = func
end
this.reg_cmd = function(cmd,func)
    this.cmd_dict[cmd] = func
end


this.start = function(server_path)
    local tmp_ip,tmp_port = server_path:match("(%d+%.%d+%.%d+%.%d+):(%d+)")
    if tmp_ip and tmp_port then
        this.server_ip = tmp_ip
        this.server_port = tmp_port
        sys.taskInit(socketTask)
        sys.taskInit(task_proc_pdata)
    end
end

return this
