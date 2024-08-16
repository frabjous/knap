-----------------------------------------
-- KNAP: Kevin's Neovim Auto-Previewer --
-----------------------------------------
--[[
    Neovim script for previewing files in customizable ways
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

-- shorter name for api
local api = vim.api
-- set variable for update timer
local knaptimer = vim.loop.new_timer()

-- determine maximum width of messages
local knap_max_col_width = (vim.v.echospace - 1)

-- make the function names local
local attach_to_changes, basename, buffer_init, check_to_process_again, close_viewer, dirname, err_msg, fill_in_cmd, forward_jump, get_docroot, get_extension, get_extension_or_ft, get_outputfile, get_os, is_running, jump, launch_viewer, mark_viewer_closed, on_exit, on_stderr, on_stdout, process_once, refresh_viewer, restart_timer, set_variables, start_autopreviewing, start_processing, stop_autopreviewing, toggle_autopreviewing


-- this function attaches listeners to buffer events for changes to
-- the text starts the timer to update the preview
function attach_to_changes()
    local succ = api.nvim_buf_attach(0,
        false,
        {
            on_lines = function(s, b, ct, fl, ll, nll, bc, dcp, dcu)
                return restart_timer()
            end,
            on_reload = function(s, b)
                return restart_timer()
            end
        }
    )
    -- api.nvim_buf_attach returns false if attaching did not succeed
    if not (succ) then
        err_msg('Could not attach to buffer changes. ' ..
            'Autopreviewing not activated.')
        stop_autopreviewing(false)
    end
end

-- returns the basename of a full path to a file
function basename(path)
    return path:gsub('^.*/','')
end

-- sets the relevant knap_settings for the buffer
function buffer_init()
    -- determine settings by merging tables
    -- get global and local settings from startup files if exists
    local gsettings = vim.g.knap_settings or {}
    local bsettings = vim.b.knap_settings or {}
    -- buffer settings take precedent over global settings
    bsettings = vim.tbl_extend("keep", bsettings, gsettings)
    -- default settings if neither in buffer nor global settings
    local dsettings = {
        htmloutputext = "html",
        htmltohtml = "none",
        htmltohtmlviewerlaunch = "falkon %outputfile%",
        htmltohtmlviewerrefresh = "none",
        mdoutputext = "html",
        mdtohtml = "pandoc --standalone %docroot% -o %outputfile%",
        mdtohtmlviewerlaunch = "falkon %outputfile%",
        mdtohtmlviewerrefresh = "none",
        mdtopdf = "pandoc %docroot% -o %outputfile%",
        mdtopdfviewerlaunch = "sioyek %outputfile%",
        mdtopdfviewerrefresh = "none",
        markdownoutputext = "html",
        markdowntohtml = "pandoc --standalone %docroot% -o %outputfile%",
        markdowntohtmlviewerlaunch = "falkon %outputfile%",
        markdowntohtmlviewerrefresh = "none",
        markdowntopdf = "pandoc %docroot% -o %outputfile%",
        markdowntopdfviewerlaunch = "sioyek %outputfile%",
        markdowntopdfviewerrefresh = "none",
        texoutputext = "pdf",
        textopdf = "pdflatex -interaction=batchmode -halt-on-error -synctex=1 %docroot%",
        textopdfviewerlaunch = "sioyek %outputfile% --new-window --inverse-search 'nvim --headless -c \"lua require('\"'\"'knaphelper'\"'\"').relayjump('\"'\"'%servername%'\"'\"','\"'\"'%1'\"'\"',%2,%3)\"'",
        textopdfviewerrefresh = "none",
        textopdfforwardjump = "sioyek --inverse-search 'nvim --headless -c \"lua require('\"'\"'knaphelper'\"'\"').relayjump('\"'\"'%servername%'\"'\"','\"'\"'%1'\"'\"',%2,%3)\"' --reuse-window --forward-search-file %srcfile% --forward-search-line %line% %outputfile%",
        textopdfshorterror = "A=%outputfile% ; LOGFILE=\"${A%.pdf}.log\" ; rubber-info \"$LOGFILE\" 2>&1 | head -n 1",
        delay = 250
    }
    -- merge settings; buffer and global take precedent over default
    bsettings = vim.tbl_extend("keep", bsettings, dsettings)
    -- set initial variable for buffer
    vim.b.knap_settings = bsettings
    vim.b.knap_viewer_launched = false
    vim.b.knap_autopreviewing = false
    vim.b.knap_currently_processing = false
    vim.b.knap_buffer_initialized = true
end

-- checks to see if it should process
function check_to_process_again()
    -- do not process if autopreview turned off
    -- or the last process is still underway
    if not (vim.b.knap_autopreviewing) or
       (vim.b.knap_currently_processing) then
       return
    end
    -- do not process if nothing has changed
    local currbufcontents = ''
    if (vim.b.knap_buffer_as_stdin) then
        currbufcontents = table.concat(api.nvim_buf_get_lines(0,0,-1,false),'\n')
        if (currbufcontents == vim.b.knap_last_buf_contents) then
            return
        end
    else
        if not (vim.opt_local.modified:get()) then
            return
        end
    end
    start_processing(currbufcontents)
end

function get_os()
    local os_current = vim.loop.os_uname().sysname
    local isWindows,j = string.find(os_current,"Windows")

    if os_current == "Linux" then
        return "linux"
    elseif isWindows ~= nil then
        return "windows"
    else
        err_msg("Unknown operating system")
    end
end
local os_cur = get_os()

function kill_command()
    if os_cur == "linux" then
        return 'pkill -P '
    elseif os_cur == "windows" then
        return 'taskkill /PID '
    else
        err_msg("Unknown operating system")
    end
end
local kill_com = kill_command()

-- Get null output, according to the OS in use.
function null_output()
    if os_cur == "linux" then
        return '/dev/null'
    elseif os_cur == "windows" then
        return 'NUL'
    else
        err_msg("Unknown operating system")
    end
end
local null_out = null_output()

-- sends kill command to the pid of the viewer application
function close_viewer()
    if not (vim.b.knap_buffer_initialized) then
        buffer_init()
    end
    if (vim.b.knap_viewerpid) and (is_running(vim.b.knap_viewerpid)) then
        local waskilled = os.execute(kill_com ..
            tostring(vim.b.knap_viewerpid) .. ' > ' .. null_out .. ' 2>&1' )
        -- above returns exit code of kill command
        if not (waskilled) then
            err_msg("Could not kill process " ..
                tostring(vim.b.knap_viewerpid))
        end
    end
    -- mark viewer closed and stop autopreviewing if on
    mark_viewer_closed()
    stop_autopreviewing(true)
end

-- gets the directory part of a full path
function dirname(fn)
    if not (fn:match('/')) then
        return '.'
    end
    return fn:gsub('/[^/]*$','')
end

-- function for display error messages
function err_msg(msg)
    api.nvim_echo({{msg:sub(1, knap_max_col_width), 'ErrorMsg'}}, true, {})
end

-- fills in the %variable%-style variables in the defined routines
-- and associated commands
function fill_in_cmd(cmd)
    -- replace %fields% in cmd with values
    local pos = api.nvim_win_get_cursor(0)
    local row, col = pos[1], pos[2]
    local srcfile = api.nvim_buf_get_name(0)
    cmd = cmd:gsub('%%column%%', tostring(col))
            :gsub('%%line%%', tostring(row))
            :gsub('%%srcfile%%', '"' .. srcfile .. '"')
    if (vim.b.knap_docroot) then
        cmd = cmd:gsub('%%docroot%%', '"' ..
            basename(vim.b.knap_docroot) .. '"')
    end
    if (vim.b.knap_outputfile) then
        cmd = cmd:gsub('%%outputfile%%',
            '"' .. basename(vim.b.knap_outputfile) .. '"')
    end
    if (vim.b.knap_viewerpid) then
        cmd = cmd:gsub('%%pid%%', vim.b.knap_viewerpid)
    end
    if (vim.v.servername) then
        cmd = cmd:gsub('%%servername%%', vim.v.servername)
    end
    return cmd
end

-- execute command to jump to appropriate place in viewer
function forward_jump()
    -- initialize if not already initialized
    if not (vim.b.knap_buffer_initialized) then
        buffer_init()
    end
    -- ensure there is a routine set
    if not (vim.b.knap_routine) then
        err_msg("No routine set. Process at least once first.")
        return
    end
    -- make sure viewer is still running
    if not (vim.b.knap_viewerpid) or
       not (is_running(vim.b.knap_viewerpid)) then
        err_msg("Viewer not currently active.")
        mark_viewer_closed()
        return
    end
    --get forward jump command; return if nil
    local fjcmd = vim.b.knap_settings[vim.b.knap_routine .. "forwardjump"]
    if not (fjcmd) then
        err_msg("No forward jump method has been defined for routine " ..
            vim.b.knap_routine .. ".")
        return
    end
    -- fill in details of command
    fjcmd = fill_in_cmd(fjcmd)
    print("Attempting to jump to matching location.")
    local fjprecmd = ''
    if (vim.b.knap_docroot) then
        fjprecmd = 'cd "' .. dirname(vim.b.knap_docroot) .. '" && '
    end
    local result = os.execute(fjprecmd .. fjcmd .. ' > ' .. null_out .. ' 2>&1' )
    -- report if error
    if not (result) then
        err_msg("Jump command not successful. (Cmd: " .. fjcmd .. ")")
    end
end

-- get the name of the "root" document, i.e., the one that is
-- actually processed by the routine
function get_docroot()
    -- look through first five lines for 'root = '
    local fivelines = vim.api.nvim_buf_get_lines(0, 0, 5, false)
    local specified=''
    for l,line in ipairs(fivelines) do
        if line:match('[Rr][Oo][Oo][Tt]%s*=') then
            specified=line:gsub('^.*[Rr][Oo][Oo][Tt]%s*=%s*','')
                :gsub('%s*$','')
            break
        end
    end
    -- if nothing found, return sourcefile
    if (specified == '') then
        return api.nvim_buf_get_name(0)
    end
    -- if absolute path given, return it
    if (specified:sub(1,1) == '/') then
        return specified
    end
    -- otherwise, combine paths
    return dirname(api.nvim_buf_get_name(0)) .. '/' .. specified
end

-- get the extension part of a filename
function get_extension(fn)
    if fn:match('^%.?[^%.]*$') then
        return ''
    end
    return fn:gsub('^.*%.',''):lower()
end

-- get the extension, or if not, found, the vim filetype
function get_extension_or_ft(fn)
    local ext=get_extension(fn)
    if (ext == '') then
        return vim.opt_local.filetype:get() or ''
    end
    return ext
end

-- get the name of the output file for the routine based on the
-- document root and the output extension set for it
function get_outputfile()
    -- make sure docroot is set
    if not (vim.b.knap_docroot) then
        err_msg("Could not read document root filename. Is it set?")
        return 'unknown'
    end
    -- get extension of docroot and its output extension
    local docrootext = get_extension_or_ft(vim.b.knap_docroot)
    if not (vim.b.knap_settings[docrootext .. 'outputext']) then
        err_msg("Could not determine output type. Is one set for " ..
            docrootext .. " files?")
        return 'unknown'
    end
    local outputext = vim.b.knap_settings[docrootext .. 'outputext'];
    -- derive outputname from docroot bys swapping extensions
    return vim.b.knap_docroot:gsub('%.[^%.]*$','.' .. outputext)
end

-- see if a process is still running
function is_running(pid)
    -- use ps to see if process is active
    local running = os.execute('ps -p ' .. tostring(pid) .. ' > ' ..  null_out .. ' 2>&1')
    if (running) then
        return true
    end
    if not (vim.b.knap_viewer_launch_cmd) then
        return false
    end
    -- check by process name, which will executable after any ; or &&
    local procname = vim.b.knap_viewer_launch_cmd:gsub('.*;%s*','')
    procname = procname:gsub('.*&&%s*','')
    procname = procname:gsub('%s.*','')
    print('is_running  '.. procname)
    running = os.execute('pgrep "' .. procname .. '"  > ' ..  null_out .. ' 2>&1' )
    return running
end

local get_window_id_x11, focus_window


--
function get_window_id_x11()
  if (vim.b.xwindowid == nil) then
    vim.b.xwindowid=os.getenv("WINDOWID") -- way1 to get windowid
  end
  if vim.b.xwindowid ~= nil then
    return vim.b.xwindowid
  end
  if (vim.fn.executable('xdotool') == 1 ) then
    print("Please click on the vim window. Using xdotool selectwindow to get window ID") -- to get window id
    local out = io.popen("xdotool selectwindow") -- way2 to get windowid
    if (out ~= nil) then
      vim.b.xwindowid = out:read("a")
      out:close()
    else
      vim.b.xwindowid = -1 -- if both way can't find windowid
      print("You are using X11. But can't find window id even though xdotool is executable.")
    end
  else
    vim.b.xwindowid = -1 -- Can't find xdotool. Way2 can't be done
    print("You are using X11. But xdotool is not found")
  end
  -- when vim.b.xwindowid == -1 it means that we can't find windowid.
  return vim.b.xwindowid
end

function focus_window()
  local xdg_session_type = os.getenv("XDG_SESSION_TYPE")
  if (xdg_session_type == "x11") then
    local window_id_x11 = get_window_id_x11()
    -- print(window_id_x11)
    if (window_id_x11 ~= -1) then
      os.execute('xdotool windowactivate ' .. window_id_x11)
    end
  elseif (xdg_session_type == "wayland") then
    -- https://github.com/lucaswerkmeister/activate-window-by-title
    -- This way is not very perfect but work
    -- I don't know how to get something similar to windows id like in X.
    -- So I only activate window which has suffix '.tex'
    os.execute("busctl --user call org.gnome.Shell /de/lucaswerkmeister/ActivateWindowByTitle de.lucaswerkmeister.ActivateWindowByTitle activateBySuffix s 'tex' > /dev/null")
  end
end

-- move the cursor to a location if the file requested is the current
-- one, or else just report where it should go
function jump(filename,line,column)
  local bufnr = vim.fn.bufnr(filename)

  -- switch buffer if opened
  if (bufnr == -1) then
    -- open file file if necessary
    if (not vim.fn.filereadable(filename)) then
      print('W: jump spot at line ' .. tostring(line) .. ' col ' ..
          tostring(column) .. ' in ' .. filename)
      return -- early
    end
    api.nvim_command("edit " .. vim.fn.fnameescape(filename))
    bufnr = vim.fn.bufnr(filename)
    print('jump to line ' .. tostring(line) .. ' in ' .. filename)
  end

  api.nvim_set_current_buf(bufnr)
  api.nvim_win_set_cursor(0,{line,column})
  vim.cmd.normal('z.')
  focus_window()
    -- print('jumping to line ' .. tostring(line) .. ' col ' ..
        -- tostring(column))
end

function get_pid_viewer(lcmd)
    local vpid
    if (os_cur=="linux") then
        local lproc = io.popen(lcmd)
        -- try to read pid
        vpid = lproc:read()
        lproc:close()
        return vpid
    else
        if (os_cur == "windows") then
            os.execute(lcmd)

            -- TODO get_process_cmd according to OS; test TEX format
            -- Get process PID
            local viewer_name = string.match(vim.b.knap_viewer_launch_cmd, "%S+")
            local get_process_cmd = 'wmic process where "name=\''.. viewer_name ..'.exe\'" get ProcessId /value'
            local lproc = io.popen(get_process_cmd)
            local output = lproc:read("*a")
            lproc:close()
            vpid = output:match("ProcessId=(%d+)")
            return vpid
        end
    end
end
-- run the specified command to open the viewing application
function launch_viewer()
    -- launch viewer in background and echo pid
    local  lcmd = '';
    if (os_cur == 'windows') then
        lcmd = lcmd .. 'start '
    end
    lcmd = lcmd ..  vim.b.knap_viewer_launch_cmd .. ' > ' .. null_out .. ' 2>&1'
    if (os_cur ~= 'windows') then
        lcmd = lcmd .. ' & echo $!'
    end

    if (vim.b.knap_docroot) then
        lcmd = 'cd "' .. dirname(vim.b.knap_docroot) .. '" && ' .. lcmd
    end

    local vpid = get_pid_viewer(lcmd)

    -- if couldn't read pid then it was a failure
    if not (vpid) or (vpid == '') then
        err_msg("Could not launch viewer.")
        mark_viewer_closed()
        return
    end

    -- set variables for viewer
    vim.b.knap_viewerpid = tonumber(vpid)
    vim.b.knap_viewer_launched = 1
    -- set viewer refresh command
    local vwrrefcmd = vim.b.knap_settings[vim.b.knap_routine ..
    'viewerrefresh'] or 'none';
    vim.b.knap_viewer_refresh_cmd = fill_in_cmd(vwrrefcmd)
end

-- set variables to the effect that viewer is closed, whether done
-- by close_viewer() or having been done external to the plugin
function mark_viewer_closed()
    -- unset variables for viewer
    vim.b.knap_viewer_launched = false
    vim.b.knap_viewerpid = nil
end

-- what happens when a processing routine is finished running
function on_exit(jobid, exitcode, event)
    -- close job channel if can
    pcall(function()
        vim.fn.chanclose(vim.b.knap_process_job)
    end)
    -- job is over, no longer mark as processing
    vim.b.knap_currently_processing = false
    -- check if process was succesful
    if (exitcode == 0) then
        -- process was successful
        if (vim.b.knap_viewer_launched) then
            -- if viewer launched already, refresh it
            print("process successful; refreshing preview")
            refresh_viewer()
        else
            -- if viewer not launched already; launch it
            print("process successful; launching preview")
            launch_viewer()
        end
    else
        local settings = vim.b.knap_settings
        -- no shorterror routine defined; report some of stderr
        if (settings[vim.b.knap_routine .. "shorterror"] == nil) then
            err_msg('ERR: ' .. vim.b.knap_process_stderr)
        else
            if (settings[vim.b.knap_routine .. "shorterror"] == "none") then
                -- print very generic error
                err_msg('Process unsuccessful; returned exit code ' .. tostring(exitcode))
            else
                -- print result of short error command for routine
                local shorterrcmd = fill_in_cmd(settings[vim.b.knap_routine ..
                 "shorterror"])
                if (vim.b.knap_docroot) then
                    shorterrcmd = 'cd "' .. dirname(vim.b.knap_docroot) .. '" && '
                        .. shorterrcmd
                end
                local errproc = io.popen(shorterrcmd)
                local errmsg = vim.trim(errproc:read("*a"))
                errproc:close()
                err_msg('ERR: ' .. errmsg)
            end
        end
    end
    --  check once more in case there are new edits
    check_to_process_again()
end

-- process stderr returned from processing routine
function on_stderr(jobid, data, event)
    -- concat new stderr output to what has been collected
    vim.b.knap_process_stderr = (vim.b.knap_process_stderr or '') ..
        table.concat(data,'')
end

-- process stdout returned from processing routine
function on_stdout(jobid, data, event)
    -- concat new stdout output to what has been collected
    vim.b.knap_process_stdout = (vim.b.knap_process_stdout or '') ..
        table.concat(data,'')
end

-- save, run routine, and refresh viewer one time
function process_once()
    -- initialize if not already
    if not (vim.b.knap_buffer_initialized) then
        buffer_init()
    end
    -- try to set variables, return on failure
    if not (set_variables()) then
        return
    end
    -- check if another process is currently underway
    if (vim.b.knap_currently_processing) then
        err_msg('Another process is currently underway. ' ..
            'Kill it first if need be.')
        return
    end
    -- start processing the document
    start_processing('')
end

-- run command specified to refresh the viewer application
function refresh_viewer()
    -- check if there is actually a command for refreshing
    if not (vim.b.knap_viewer_refresh_cmd) or
        (vim.b.knap_viewer_refresh_cmd == 'none') or
        (vim.b.knap_viewer_refresh_cmd == '') then
        return
    end
    -- check if viewer is still open
    if not (vim.b.knap_viewerpid) or
        not (is_running(vim.b.knap_viewerpid)) then
        err_msg('Viewer is not open.')
        mark_viewer_closed()
        return
    end
    -- execute refresh command
    local rcmd = '(' .. vim.b.knap_viewer_refresh_cmd .. ') > ' .. null_out .. ' 2>&1 &'
    if (vim.b.knap_docroot) then
        rcmd = 'cd "' .. dirname(vim.b.knap_docroot) .. '" && ' .. rcmd
    end
    local succ = os.execute(rcmd)
    -- report if error
    if not (succ) then
        err_msg('Error when attempting to refresh viewer.')
    end
end

-- restart the delay from editing to starting processing
function restart_timer()
    -- stop the timer if in progress
    pcall(function()
        knaptimer:close()
    end)
    -- note: returning true detaches the callbacks from buffer changes
    -- do so if autopreviewing has been turned off or no delay is set
    if not (vim.b.knap_autopreviewing) or
       not (vim.b.knap_settings.delay) then
        return true
    end
    -- start new timer
    knaptimer = vim.loop.new_timer()
    knaptimer:start(vim.b.knap_settings.delay, 0, vim.schedule_wrap(
        check_to_process_again
    ))
end

-- read settings and determine processing, viewing and refreshing commands
function set_variables()
    -- set docroot or rage quit
    vim.b.knap_docroot = get_docroot()
    if not (vim.b.knap_docroot) or (vim.b.knap_docroot == '') then
        return false
    end
    -- set outputfile or ragequit
    vim.b.knap_outputfile = get_outputfile()
    if not (vim.b.knap_outputfile) or
        (vim.b.knap_outputfile == 'unknown') then
        return false
    end
    -- set routine and processing command or ragequit
    vim.b.knap_routine = get_extension_or_ft(vim.b.knap_docroot) ..
        'to' .. get_extension(vim.b.knap_outputfile)
    local routinecmd = vim.b.knap_settings[vim.b.knap_routine]
    if not (routinecmd) then
        err_msg('Could not determine processing cmd for ' ..
            vim.b.knap_routine .. '. Is one set?')
        return false
    end
    vim.b.knap_processing_cmd = fill_in_cmd(routinecmd)
    -- determine whether buffer should be send as stdin to processing cmd
    vim.b.knap_buffer_as_stdin = (vim.b.knap_settings[vim.b.knap_routine ..
        'bufferasstdin'] == true)
    vim.b.knap_last_buf_contents = ''
    -- set viewer launch command or ragequit
    local vlcmd = vim.b.knap_settings[vim.b.knap_routine .. 'viewerlaunch']
    if not (vlcmd) then
        err_msg('Could not determine viewing command for ' ..
            vim.b.knap_routine .. '. Is one set?')
        return false
    end
    vim.b.knap_viewer_launch_cmd = fill_in_cmd(vlcmd)
    -- everything worked OK?
    return true
end

-- turn on autoupdating preview process
function start_autopreviewing()
    -- initialize if need be
    if not (vim.b.knap_buffer_initialized) then
        buffer_init()
    end
    -- try to set variables; errors will result if this fails
    if not (set_variables()) then
        stop_autopreviewing(true)
        return
    end
    vim.b.knap_autopreviewing = true
    -- new method: attach lua to buffer changes
    attach_to_changes()
    -- start right away
    start_processing('')
end

-- save and begin the processing command
function start_processing(bufcontents)
    bufcontents = bufcontents or ''
    vim.b.knap_currently_processing = true
    vim.b.knap_process_stdout = ''
    vim.b.knap_process_stderr = ''
    -- save file unless using buffer as stdin
    if (not(vim.b.knap_buffer_as_stdin)) then
        vim.cmd('silent! update')
    end
    -- if processing command is none or blank,
    -- skip right to exiting processing
    if (vim.b.knap_processing_cmd == 'none') or
        (vim.b.knap_processing_cmd == '') then
        on_exit(0,0,'exit')
        return
    end
    -- determine working folder as dirname of edited file or docroot
    local workingdir = ''
    if (vim.b.knap_docroot) then
        workingdir = dirname(vim.b.knap_docroot)
    else
        workingdir = dirname(api.nvim_buf_get_name(0))
    end
    -- start process job
    vim.b.knap_process_job = vim.fn.jobstart(
        vim.b.knap_processing_cmd, {
            cwd = workingdir,
            on_exit = on_exit,
            on_stdout = on_stdout,
            on_stderr = on_stderr
        })

    -- send current buffer as stdin in buffer_as_stdin mode
    if (vim.b.knap_buffer_as_stdin) then
        -- read buffer only if not sent as argument
        if (bufcontents == '') then
            bufcontents = table.concat(api.nvim_buf_get_lines(0,0,-1,false),'\n')
        end
        -- send buffer as stdin
        vim.fn.chansend(vim.b.knap_process_job,
            bufcontents
        )
        -- save current state of buffer to check if changed
        vim.b.knap_last_buf_contents = bufcontents
        -- close stdin to the job
        vim.fn.chanclose(vim.b.knap_process_job, 'stdin')
    end
    print("knap routine started")
end

-- turn auto-previewing off (actually takes effect when restart_timer
-- discovers the changed variables)
function stop_autopreviewing(report)
    if not (vim.b.knap_autopreviewing) then
        return
    end
    vim.b.knap_autopreviewing = false
    if (report) then
        print('autopreview stopped')
    end
end

-- toggle whether auto-previewing is on
function toggle_autopreviewing()
    -- initialize if need be
    if not (vim.b.knap_buffer_initialized) then
        buffer_init()
    end
    -- check if viewer is open
    local vieweropen = (vim.b.knap_viewerpid) and
        (is_running(vim.b.knap_viewerpid))
    -- if previewing with an open viewer, stop previewing
    if (vim.b.knap_autopreviewing) and (vieweropen) then
        stop_autopreviewing(true)
    else
        -- otherwise start previewing
        if not (vieweropen) then
            mark_viewer_closed()
        end
        start_autopreviewing()
    end
end

-- export these functions
return {
    close_viewer = close_viewer,
    get_docroot = get_docroot,
    forward_jump = forward_jump,
    jump = jump,
    process_once = process_once,
    toggle_autopreviewing = toggle_autopreviewing,
    get_os = get_os
}
