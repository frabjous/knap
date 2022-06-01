#!/usr/bin/luajit
---------------------------------------
-- SyncTeX Inverse Function for LLPP --
---------------------------------------
--[[
    Lua script for relaying SyncTeX search info from llpp to neovim
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

-- read arguments
local filename = arg[1]
local page = arg[2]
local x = arg[3]
local y = arg[4]

-- if any are blank print instructions and exixt
if (filename == nil) or
   (page == nil) or
   (x == nil) or
   (y == nil) then
   print [[
Usage: synctex-inverse.lua [filename.pdf] [0-based-page] [x] [y]

This is meant to be called from llpp with

    synctex-command='synctex-inverse.lua'

    or

    synctex-command='luajit /path/to/synctex-inverse.lua'

in $HOME/.config/llpp.conf.

It will send an appropriate command to all current instances of
neovim whose remote socket it can find.

   ]]
   os.exit()
end

-- add one because llpp's pages are zero based
page = page + 1

-- start synctex process
local proc = io.popen('synctex edit -o "' .. page .. ':' .. x .. ':' ..
    y .. ':' .. filename .. '"')

-- read output
for line in proc:lines() do
    if (line:match('SyncTeX result end')) then
        break
    end
    if (line:match('^Input:')) then
        infile = line:gsub('^.*:','')
        infile = infile:gsub('%s*$','')
    end
    if (line:match('^Line:')) then
        linenum = line:gsub('^.*:','')
        linenum = linenum:gsub('%s*$','')
    end
    if (line:match('^Column:')) then
        col = line:gsub('^.*:','')
        col = col:gsub('%s*$','')
    end
    if (col) and (linenum) and (infile) then
        break
    end
end

-- sanity check on col
if (tonumber(col) < 0) then
    col = '0'
end

-- close process
proc:close()

-- fire up headless neovim instance to do jump
local cmd = 'nvim --headless -es --cmd "lua require(\'knaphelper\')' ..
    '.relayjump(\'all\',\'' .. infile .. '\',' .. linenum .. ','
    .. col .. ')"'
local succ = os.execute(cmd)
os.exit(succ)
