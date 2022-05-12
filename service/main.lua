local skynet = require "skynet"
local runconfig = require "runconfig"

skynet.start(function()
    -- 初始化
    print("[main]" .. runconfig.node1.gateway[1].port)

    skynet.newservice("gateway", "gateway", 1) -- 1可以索引runconfig中gateway[1]

    -- 退出自身
    skynet.exit()
end)