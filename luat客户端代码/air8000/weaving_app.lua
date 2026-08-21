local this = {}

-- require ----------------------------
local op_com = require "op_com"
local op_errdump = require "op_errdump"
local wc = require "weaving_client"

-- define -----------------------------
WCMD_CAMERA = 0x03
WCMD_USER = WCMD_CAMERA
-- 下面的 IP 地址和端口号要填入实际值, 如 111.111.111.111:11111
local server_path = "<IP>:<PORT>"

-- func -------------------------------
this.send_msg = function(dmsg)
    dmsg["sn"] = op_com.cfg.sn
    dmsg["imei"] = this.imei
    -- dmsg["imei"] = "0000000000" -- for_test

    local bdata = json.encode(dmsg)
    if not bdata then
        dmsg["data"] = "send_msg json.encode error, len(data):"..#dmsg.data
        dmsg["result"] = "error"
        dmsg["log"] = "send_msg json.encode error"
        bdata = json.encode(dmsg)
        if not bdata then
            print("send_msg json.encode error")
            return
        end
    end
    log.info("send_msg",bdata)
    wc.send_data(WCMD_USER,bdata)
end

function this.reg_self()
    local dmsg = {cmd = 'reg',version = VERSION, Type = PRJ}
    -- dmsg = {cmd = 'reg',version = "v0.0.0.11"}
    log.info("reg_self")
    this.send_msg(dmsg)
end

----------- cmd begin ----------------

local function cmd_get_cfg(dmsg)
    local ret = {
        msgid = dmsg.msgid,
        cmd = "get_cfg",
        result = "ok",
        data = op_com.deep_copy(op_com.cfg),
        -- data = op_com.cfg,
    }
    ret.data["version"] = VERSION
    this.send_msg(ret)
end

local function cmd_get_status(dmsg)
    local allmem,nowmem,maxmem = rtos.meminfo()
    op_com.g.nowmem = string.format("%.2f%%",nowmem/allmem*100)
    op_com.g.maxmem = string.format("%.2f%%",maxmem/allmem*100)
    local ret = {
        msgid = dmsg.msgid,
        cmd = "get_status",
        result = "ok",
        data = {
            csq = mobile.csq() or "",
            g = op_com.g,
        }
    }
    this.send_msg(ret)
end


local function cmd_check_online(dmsg)
    local imei = mobile.imei() or ""
    if #imei > 0 then
        local ret = {
            msgid = dmsg.msgid,
            cmd = "check_online",
            result = "ok",
            data = {
                imei=imei,
                sn = op_com.cfg.sn
            }
        }
        this.send_msg(ret)
    end
end

local function cmd_hello(dmsg)
    local data = dmsg['data']
    if type(data) == "string" then
        log.info("get "..data)
        local ret = {cmd="hello",result="ok",data="hi, I get "..data}
        log.info("send: ",json.encode(ret))
        this.send_msg(ret)
    end
end

local function cmd_reset(dmsg)
    sys.taskInit(function()
        sys.wait(3000)
        op_com.reboot()
    end)
end

local function fota_cb(ret)
    log.info("weaving_app fota", ret)
    if ret == 0 then
        op_com.reboot()
    end
end
local function cmd_ota(dmsg)
    -- local libfota = require "libfota"
    libfota.request(fota_cb)
end

local function cmd_test(dmsg)
    for k,v in pairs(dmsg) do
        print(k,v)
    end
end

-- 远程执行本地指令
local function cmd_lccfg(dmsg)
    local data = dmsg['data']
    if not data then
        dmsg["result"] = "error"
        dmsg["log"] = "empty cmd"
        this.send_msg(dmsg)
    else
        local cmdl = data:split(",")
        func = op_com.cmd_dict[cmdl[1]]
        if type(func) == "function" then
            dmsg["data"] = func(cmdl)
        end
        this.send_msg(dmsg)
    end
end

local function cmd_err(dmsg)
    print("in cmd_err !!!!!!!!!!!!!!")
    local data = dmsg['data']
    if type(data) == "string" then
        local _data_list = data:split(",")
        local _option = _data_list[1]

        ret1 = "usage: err:<load|clear>"
        if _option == "load" then
            local status, err = pcall(op_errdump.load_errDump,true)
            
            if not status then
                ret1 = err
            else
                ret1 = "<"..op_com.g.err..">"
            end
        elseif _option == "clear" then
            op_errdump.clear_errDump("remote_cmd")
            ret1 = "ok"
        end

        local ret = {msgid=dmsg.msgid,cmd="err",result="ok",data=ret1}
        this.send_msg(ret)
    end
end


---------- cmd end ---------------------



this.start = function()
    this.imei = mobile.imei()
    this.sn = op_com.cfg.sn
    wc.on_connect = this.reg_self
    wc.reg_wcmd(WCMD_USER,wc.proc_bmsg)
    wc.reg_cmd("get_cfg",cmd_get_cfg)
    wc.reg_cmd("hello",cmd_hello)
    wc.reg_cmd("reboot",cmd_reset)
    wc.reg_cmd("reset",cmd_reset)
    wc.reg_cmd("test",cmd_test)
    wc.reg_cmd("ota",cmd_ota)
    wc.reg_cmd("get_status",cmd_get_status)
    wc.reg_cmd("check_online",cmd_check_online)
    wc.reg_cmd("lccfg",cmd_lccfg)
    wc.reg_cmd("err",cmd_err)
    if op_com.cfg["IPPORT"] and op_com.cfg["IPPORT"]:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$") then
        wc.start(op_com.cfg["IPPORT"])
    else
        wc.start(server_path)
    end
end

return this
