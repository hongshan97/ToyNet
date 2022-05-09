local skynet = require "skynet"
local runconfig = require "runconfig"

skynet.start(function()
    -- 初始化
    skynet.error("[start main]" .. runconfig.node1.gateway[1].port)

    -- 退出自身
    skynet.exit()
end)