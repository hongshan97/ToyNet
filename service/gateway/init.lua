local skynet = require "skynet"
local s = require "service"
local socket = require "skynet.socket"
local runconfig = require "runconfig"
local pb = require "protobuf"

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
        x = 0,
        y = 0,
        z = 0,
        e = 0,
    }
end

-- 协议解析辅助函数
local str_unpack = function(msgName, msgstr)
    local msg = pb.decode(msgName, msgstr);
    return msgName, msg -- cmd, msg    --- msg[1] = cmd
end

local str_pack = function(msgName, msg)
    for k, v in pairs(msg) do
        print(k, v)
    end
    local body = pb.encode(msgName, msg)
    print("body是" .. string.len(body))
    local namelen = string.len(msgName)
    local bodylen = string.len(body)
    local format = string.format("< i2 i2 c%d c%d", namelen, bodylen)
    return string.pack(format, bodylen + namelen + 2, namelen, msgName, body)
end

local Send = function(fd, msgName, msg) 
    local buff = str_pack(msgName, msg)
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
        print("玩家" .. playerid .. "断开连接")

        local msg = {desc = conns[fd].playerid}
        -- 通知其他玩家此玩家离开
        for _fd, _ in pairs(conns) do
            if fd ~= _fd then
                Send(_fd, "Leave", msg)
            end
        end

        conns[fd] = nil
        players[playerid] = nil
    end
end


------------------------------------------------------------

local List = function(fd, msg)
    local msg = {element = {}}
    for d, v in pairs(players) do
        table.insert(msg.element, {desc = d, x = v.x, y = v.y, z = v.z, e = v.e})
    end
    Send(fd, "List", msg)
end

local Enter = function(fd, msg)
    -- 给此玩家发送当前场景其他玩家
    List(fd)

    local desc = msg.desc
    
    if not players[desc] then
        local p = player()
        p.conn = conns[fd]
        p.conn.playerid = desc
        p.playerid = desc
        p.x = msg.x or 0
        p.y = msg.y or 0
        p.z = msg.z or 0
        p.e = msg.e or 0

        players[desc] = p
    end

    -- 通知其他玩家此玩家进入场景
    for _fd, _ in pairs(conns) do
        Send(_fd, "Enter", msg)
    end
end

local Move = function(fd, msg)
    local desc = msg.desc
    local p = players[desc]
    p.x = msg.x or 0
    p.y = msg.y or 0
    p.z = msg.z or 0

    -- 通知其他玩家
    for _fd, _ in pairs(conns) do
        if fd ~= _fd then
            Send(_fd, "Move", msg) 
        end
    end
end

local Leave = function(fd)
    local msg = {}
    table.insert(msg, conns[fd].playerid)
    -- 通知其他玩家此玩家离开
    for _fd, _ in pairs(conns) do
        if fd ~= _fd then
            Send(_fd, "Leave", msg)
        end
    end
end

local Attack = function(fd, msg)
    -- 通知其他玩家
    for _fd, _ in pairs(conns) do
        if fd ~= _fd then
            Send(_fd, "Attack", msg) 
        end
    end
end

local api = {
    ["Enter"] = Enter,
    ["List"] = List,
    ["Move"] = Move,
    ["Leave"] = Leave, -- 客户端主动下线
    ["Attack"] = Attack,
}


-----------------------------------------------------------------



















local process_msg = function(fd, msgName, msgstr)
    
    local cmd, msg = str_unpack(msgName, msgstr)

    local conn = conns[fd]
    local playerid = conn.playerid

    if api[cmd] then
        api[cmd](fd, msg)
    end
end

-- 以\n分割出消息
local process_buff = function(fd, readbuff)
    while true do
        if readbuff and string.len(readbuff) > 2 then -- 确保可以解析2bytes的消息总长度msglen
            
            local len = string.len(readbuff)
            local msglen_format = string.format("< i2 c%d", len - 2)
            local msglen, other = string.unpack(msglen_format, readbuff)
            if msglen <= len - 2 then -- 确保msg本体有msglen长度
                local namelen_format = string.format("< i2 c%d c%d", msglen - 2, len - 2 - msglen)
                local namelen, name_body, _readbuff = string.unpack(namelen_format, other)
                readbuff = _readbuff
                local name_body_format = string.format("c%d c%d", namelen, msglen - 2 - namelen)
                local name, body = string.unpack(name_body_format, name_body)
                print("消息：", name, body)
                process_msg(fd, name, body)
            else
                return readbuff
            end
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

    pb.register_file("./proto/Enter.pb")
    pb.register_file("./proto/List.pb")
    pb.register_file("./proto/Move.pb")
    pb.register_file("./proto/Leave.pb")
    pb.register_file("./proto/Attack.pb")

    -- local str = pb.encode("List", {
    --     element = {
    --         {
    --             desc = "lhy",
    --             x = 1;
    --             y = 2;
    --             z = 3;
    --             e = 4;
    --         },
    --         {
    --             desc = "hyl",
    --             x = 11;
    --             y = 22;
    --             z = 33;
    --             e = 44;
    --         }            
    --     }
    -- })


    -- local t = pb.decode("List", str)
    -- for k, v in pairs(t.element) do 
    --     print(k, v.desc, v.x, v.y, v.z, v.e)
    -- end


    local listenfd = socket.listen("0.0.0.0", port)
    print("[gateway] " .. "Listen port: ", port)
    socket.start(listenfd, connect)
    
end

s.start(...)