--[[
通用的配置和全局变量, 以及共用的函数

]]--


local this = {}

-- 宏定义, 根据具体项目随便定
this.ERR_OK = 0
this.ERR_TIME_OUT = -1
this.ERR_LENGTH_ERR = -2
this.ERR_CRC_ERR = -3
this.ERR_UART3_INUSE = -4

-- 串口命令放这里
this.cmd_dict = {}
-- weaving_app 注册的指令放到这里方便让其他文件引用
this.acmd_dict = {}

-- 默认的IP:PORT
local dft_IPPORT = "111.111.111.111:1111"

this.cfg = {
    IPPORT = dft_IPPORT,
    sn = "sn001",
    err_check = "default", -- 当 err 是空的这里写原因否则写md5. 在运维人员验收完错误信息后可以手动发指令重置 err 相关标签, ota 升级成功后也可以重置 err 相关标签
    err_datetime = "0000-00-00,00:00:00", -- 上次 errdump 更新日期时间, 在 op_errdump 文件中进行设置, 由于开机后4G网络对时较慢, 需要对接RTC外设,在 op_errdump 初始化之前配置好时间, 不然这个时间是错的
}

-- 会放到 get_status 返回值里的全局变量
this.g = {
    some_status = "ok",
    err = "", -- errDump 错误信息
}

-- 不会放到 get_status 返回值里的全局变量
this.g2 = {
    in_sensor_tc = false, -- 是否在透传模式,为true表示cfg_485和sensor_485进行透传
}


this.save_cfg = function()
    for k,v in pairs(this.cfg) do
        fskv.set(k,v)
    end
end
this.set_cfg = function(k,v)
    this.cfg[k] = v
    fskv.set(k,v)
end
this.load_cfg = function()
    for k,v in pairs(this.cfg) do
        this.cfg[k] = fskv.get(k)
        -- 没读到值则使用默认值
        if nil == this.cfg[k] then
            this.cfg[k] = v
        end
    end
end
this.reboot = function()
    -- 有 TF 卡的话可以在这里先卸载 TF 卡
    rtos.reboot()
end
this.deep_copy = function(t)
    local t2 = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            t2[k] = this.deep_copy(v)
        else
            t2[k] = v
        end
    end
    return t2
end

-- Function to save JSON configuration with size limit check
this.save_json_cfg = function(key, value)
    local json_str = json.encode(value)
    
    -- Check if the JSON string exceeds 4095 bytes
    if #json_str > 4095 then
        log.error("save_json_cfg", "JSON config size exceeds 4095 bytes limit")
        return false
    end
    
    local result = fskv.set(key, json_str)
    if result then
        log.info("save_json_cfg", "Successfully saved config for key: " .. key)
    else
        log.error("save_json_cfg", "Failed to save config for key: " .. key)
    end
    
    return result
end

this.load_json_cfg = function(key, default_value)
    local value = fskv.get(key)
    
    if value == nil then
        -- Return default value if key doesn't exist
        return default_value
    end
    
    local status, result = pcall(json.decode, value)
    if status then
        return result
    else
        log.error("load_json_cfg", "Failed to decode JSON for key: " .. key)
        return default_value
    end
end

this.cmd_dict["get_cfg"] = function(cmdl)
    local ret = this.cfg
    print("get_cfg:",json.encode(ret))
    return json.encode(ret)
end

function this.init()
    -- sys.wait(1000) -- 免得日志刷没了, 生产环境不需要

    if not fskv then
        while true do
            log.info("fskv", "this demo need fskv")
            sys.wait(1000)
        end
    end

    -- 初始化kv数据库
    fskv.init()
    log.info("fskv", "init complete")
    log.info("fskv", fskv.status()) -- 已用字节, 总字节, 总kv对数 8192 65536 0, 单条值最大 4095 字节

    this.load_cfg()
end













return this

