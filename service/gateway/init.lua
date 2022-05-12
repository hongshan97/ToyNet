local skynet = require "skynet"
local s = require "service"
local socket = require "skynet.socket"
local runconfig = require "runconfig"

conns = {} -- [fd] = conn
players = {} -- [playerid] = gateplayer

-- 连接类
function conn() 
    return {
        fd = nil,
        playerid = nil,
    }
end

-- 玩家类
function player()
    return {
        playerid = nil,
        -- agent = nil,
        conn = nil,
        x,
        y,
        z,
        e,
    }
end

-- 协议解析辅助函数
local str_unpack = function(msgstr)
    local cmd, msgstr = string.match(msgstr, "(.-)|(.*)")
    local msg = {cmd}

    while true do
        local arg, rest = string.match(msgstr, "(.-),(.*)")
        if arg then
            msgstr = rest
            table.insert(msg, arg)
        else
            table.insert(msg, msgstr)
            break
        end
    end

    return msg[1], msg -- cmd, msg    --- msg[1] = cmd
end

local str_pack = function(msg)
    return msg[1] .. "|" .. table.concat(msg, ",", 2) .. "\n"
end

local Send = function(fd, msg) 
    local buff = str_pack(msg)
    print("[gateway] " .. "send to fd: " .. fd .. "：" .. buff)
    socket.write(fd, buff)
end

local disconnect = function(fd) 
    local c = conns[fd]
    if not c then
        return
    end

    local playerid = c.playerid
    if not playerid then
        return
    else
        print("玩家" .. playerid .. "销毁")
        conns[fd] = nil
        players[playerid] = nil
    end
end


------------------------------------------------------------

local List = function(fd, msg)
    local msg = {"List"}
    for desc, v in pairs(players) do
        table.insert(msg, desc)
        table.insert(msg, v.x)
        table.insert(msg, v.y)
        table.insert(msg, v.z)
        table.insert(msg, v.e)
    end
    Send(fd, msg)
end

local Enter = function(fd, msg)
    -- 给此玩家发送当前场景其他玩家
    List(fd)

    local cmd = msg[1]
    local desc = msg[2]
    
    if not players[desc] then
        local p = player()
        p.conn = conns[fd]
        p.conn.playerid = desc
        p.playerid = desc
        p.x = msg[3]
        p.y = msg[4]
        p.z = msg[5]
        p.e = msg[6]

        players[desc] = p
    end

    -- 通知其他玩家此玩家进入场景
    for _fd, _ in pairs(conns) do
        Send(_fd, msg)
    end
end

local Move = function(fd, msg)
    -- 通知其他玩家
    for _fd, _ in pairs(conns) do
        if fd ~= _fd then
            Send(_fd, msg) 
        end
    end
end


local api = {
    ["Enter"] = Enter,
    ["List"] = List,
    ["Move"] = Move,
}


-----------------------------------------------------------------



















local process_msg = function(fd, msgstr)
    print("[gateway] " .. "process_msg 收到客户端" .. fd .. "的消息" .. msgstr)
    
    local cmd, msg = str_unpack(msgstr)

    local conn = conns[fd]
    local playerid = conn.playerid

    if api[cmd] then
        api[cmd](fd, msg)
    end
end

-- 以\n分割出消息
local process_buff = function(fd, readbuff)
    while true do
        local msgstr, rest = string.match( readbuff, "(.-)\n(.*)")
        if msgstr then
            readbuff = rest
            process_msg(fd, msgstr)
        else
            return readbuff
        end
    end
end

local recv_loop = function(fd)
    socket.start(fd)
    print("[gateway] " .. "socket connected" .. fd)
    local readbuff = ""
    while true do
        local recvstr = socket.read(fd)
        if recvstr then
            readbuff = readbuff .. recvstr
            readbuff = process_buff(fd, readbuff)
        else
            print("[gateway] " .. "socket close" .. fd)
            disconnect(fd)
            socket.close(fd)
            return
        end
    end
end

local connect = function(fd, addr) 
    print("[gateway] " .. "connect from " .. addr .. "  " .. fd)

    local c = conn()
    conns[fd] = c
    c.fd = fd

    skynet.fork(recv_loop, fd)
end

function s.init()
    print("[gateway] " .. "init " .. s.name .. "  " .. s.id)

    local node = skynet.getenv("node") -- 配置文件里的node
    local nodecfg = runconfig[node]
    local port = nodecfg.gateway[s.id].port

    local listenfd = socket.listen("0.0.0.0", port)
    print("[gateway] " .. "Listen port: ", port)
    socket.start(listenfd, connect)
    
end

s.start(...)