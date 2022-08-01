--[[
    knaphelper.lua: helper script for interacting with 
       neovim instance running the knap plugin
    Copyright (C) 2019–2022 Kevin C. Klement

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
    ]]--

-- sends rpc request to server to jump to a certain line and column in
-- a file
local function relayjump(server, file, line, column)
    -- default to column -
    column = column or 0
    -- determine what servers to send to
    local servers = {}
    if (server == 'all') then
        -- get all sockets in /tmp/nvim*/0
        servers = vim.split(vim.fn.glob('/tmp/nvim*/0'),'\n')
    else
        -- actually know what server to use, so use only it
        servers = {server}
    end
    -- loop through server list, send message to each one
    for i,srvr in ipairs(servers) do
        pcall(function(srvr,file,line,column)
            -- open socket to server
            local sock = vim.fn.sockconnect("pipe", srvr, { rpc = true })
            -- send request to jump to a certain spot
            vim.rpcrequest(sock, "nvim_exec_lua",
                'require("knap").jump("' .. file .. '",' .. tostring(line) ..
                ',' .. tostring(column) .. ')',{})
            -- close channel
            vim.fn.chanclose(sock)
        end, srvr, file, line, column)
    end
    -- quit after loop
    vim.cmd('quit')
end

-- export the function
return {
    relayjump = relayjump,
}
