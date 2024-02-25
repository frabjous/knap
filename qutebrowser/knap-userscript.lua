#!/usr/bin/luajit
----------------------------------------------------------------------
-- Qutebrowser userscript for communicating with neovim knap plugin --
----------------------------------------------------------------------
--[[
    Qutebrowser userscript for communicating with neovim knap plugin
    Copyright (C) 2022 Kevin C. Klement

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

--[[

NOTE: all this script does is record the path to the fifo pipe
for the userscript in a place neovim/knap can find it later on.

Suggested use: activate this userscript when launching qutebrowser
with an argument unique to the file being edited as part of your
viewerlaunchcmd for the knap plugin; the viewerrefreshcmd can then
send a refresh command to the pipe whose location is saved in
/tmp/knap-[uniqueid]-qute-fifo, if need be using the tab index saved
as /tmp/knap-[uniqueid]-tabindex. E.g.:

--]]

-- read arguments
local fileinfobase = arg[1]
local tabindex = os.getenv("QUTE_TAB_INDEX")
local qutefifo = os.getenv("QUTE_FIFO")

-- determine where to store information
local tabinfofile = '/dev/shm/knap/knap-' .. fileinfobase .. '-qute-tabindex'
local fifoinfofile = '/dev/shm/knap/knap-' .. fileinfobase .. '-qute-fifo'

-- write tab index info file
local f = io.open(tabinfofile, 'w')
f:write(tabindex)
f:close()

-- write fifo info file
local g = io.open(fifoinfofile, 'w')
g:write(qutefifo)
g:close()

-- do nothing, but keep process alive so qutebrowser doesn't
-- close the fifo
while true do
    os.execute('sleep 99999')
end
