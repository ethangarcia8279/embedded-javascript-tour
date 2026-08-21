--[[
用于记录程序运行时错误
只使用 errDump.TYPE_SYS

使用方法:
使用 get_cfg 指令获取上次出错时间
使用 get_status 指令获取上次出错信息
使用 err_test 测试
使用 err,clear 可以清除错误信息
]]

local this = {}

local op_com = require("op_com")
local flag_need_to_tf = false



op_com.cmd_dict["err_test"] = function(cmdl)
    -- 死循环
    if cmdl[2] == "1" then
        local i = 0
        while true do
            i = i + 1
        end
    -- 数值与字符串比较
    elseif cmdl[2] == "2" then
        local a = "nihao"
        local b = 99
        if a > b then
            print("a > b")
        else
            print("a <= b")
        end
    -- 调用不存在的库
    elseif cmdl[2] == "3" then
        lllllllllllll.info("haha")
    -- 栈溢出
    elseif cmdl[2] == "4" then
        local a = {}
        for i = 1, 1000000 do
            a[i] = i
        end
    end
end
-- errDump.TYPE_SYS 和 errDump.TYPE_USR 参考合宙 API
op_com.cmd_dict["err_read"] = function(cmdl)
    local buff = zbuff.create(4096)
    local buff2 = zbuff.create(4096)
    local f1 = errDump.dump(buff, errDump.TYPE_SYS, false)
    local f2 = errDump.dump(buff2, errDump.TYPE_USR, false)
    if buff:used() > 0 then
        -- print("f1:",f1)
        log.info(buff:toStr(0, buff:used()))
    end
    if buff2:used() > 0 then
        -- print("f2:",f2)
        log.info(buff2:toStr(0, buff2:used()))
    end
    return "ok"
end
op_com.cmd_dict["err_write"] = function(cmdl)
    if #cmdl == 2 then
        errDump.record(cmdl[2])
    end
    return "ok"
end
op_com.cmd_dict["err"] = function(cmdl)
    ret = "usage: err,<load|clear>"
    if cmdl[2] == "load" then
        local status, err = pcall(this.load_errDump,true)
        
        if not status then
            ret = err
        else
            ret = "<"..op_com.g.err..">"
        end
    elseif cmdl[2] == "clear" then
        this.clear_errDump("local_cmd")
        ret = "ok"
    end
    return ret
end

local buff = zbuff.create(4096)
this.load_errDump = function(flag_write_tf)
    local ret = errDump.dump(buff, errDump.TYPE_SYS, false)
    local err = ""
    local err_check = ""
    if buff:used() > 0 then
        err = buff:toStr(0, buff:used())
        op_com.g.err = err
        err_check = crypto.md5(err)
        if err_check ~= op_com.cfg.err_check then
            op_com.set_cfg("err_datetime",os.date("%Y-%m-%d,%H:%M:%S"))
            op_com.set_cfg("err_check",err_check)
            if flag_write_tf then
                -- 这里可以写到TF卡里
                print("write to tf card")
            else
                flag_need_to_tf = true
            end
        end
    end
end

-- 除了通过命令清除, 只有 fota_cb 中会自动清除 errDump
this.clear_errDump = function(reason)
    errDump.dump(nil, errDump.TYPE_SYS, true)
    op_com.set_cfg("err_datetime",os.date("%Y-%m-%d,%H:%M:%S"))
    op_com.set_cfg("err_check",reason)
    op_com.g.err = ""
end

function this.init()
    pcall(this.load_errDump,false)
end

return this
