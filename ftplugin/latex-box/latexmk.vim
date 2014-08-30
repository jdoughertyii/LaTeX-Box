" LaTeX Box latexmk functions

" Options and variables {{{

if !exists('g:LatexBox_latexmk_options')
	let g:LatexBox_latexmk_options = ''
endif
if !exists('g:LatexBox_latexmk_env')
	let g:LatexBox_latexmk_env = ''
endif
if !exists('g:LatexBox_latexmk_async')
	let g:LatexBox_latexmk_async = 0
endif
if !exists('g:LatexBox_latexmk_preview_continuously')
	let g:LatexBox_latexmk_preview_continuously = 0
endif
if !exists('g:LatexBox_output_type')
	let g:LatexBox_output_type = 'pdf'
endif
if !exists('g:LatexBox_autojump')
	let g:LatexBox_autojump = 0
endif
if ! exists('g:LatexBox_quickfix')
	let g:LatexBox_quickfix = 1
endif

" }}}

" Process ID management (used for asynchronous and continuous mode) {{{

" A dictionary of latexmk PID's (basename: pid)
if !exists('g:latexmk_running_pids')
	let g:latexmk_running_pids = {}
endif

" Set PID {{{
function! s:LatexmkSetPID(basename, pid)
	let g:latexmk_running_pids[a:basename] = a:pid
endfunction
" }}}

" kill_latexmk_process {{{
function! s:kill_latexmk_process(pid)
	if has('win32')
		silent execute '!taskkill /PID ' . a:pid . ' /T /F'
	else
		if g:LatexBox_latexmk_async
			" vim-server mode
			let pids = []
			let tmpfile = tempname()
			silent execute '!ps x -o pgid,pid > ' . tmpfile
			for line in readfile(tmpfile)
				let new_pid = matchstr(line, '^\s*' . a:pid . '\s\+\zs\d\+\ze')
				if !empty(new_pid)
					call add(pids, new_pid)
				endif
			endfor
			call delete(tmpfile)
			if !empty(pids)
				silent execute '!kill ' . join(pids)
			endif
		else
			" single background process
			silent execute '!kill ' . a:pid
		endif
	endif
	if !has('gui_running')
		redraw!
	endif
endfunction
" }}}

" kill_all_latexmk_processes {{{
function! s:kill_all_latexmk_processes()
	for pid in values(g:latexmk_running_pids)
		call s:kill_latexmk_process(pid)
	endfor
endfunction
" }}}

" }}}

" Setup for vim-server {{{
function! s:SIDWrap(func)
	if !exists('s:SID')
		let s:SID = matchstr(expand('<sfile>'), '\zs<SNR>\d\+_\ze.*$')
	endif
	return s:SID . a:func
endfunction

function! s:LatexmkCallback(basename, status)
	" Only remove the pid if not in continuous mode
	if !g:LatexBox_latexmk_preview_continuously
		call remove(g:latexmk_running_pids, a:basename)
	endif
	call LatexBox_LatexErrors(a:status, a:basename)
endfunction

function! s:setup_vim_server()
	if !exists('g:vim_program')

		" attempt autodetection of vim executable
		let g:vim_program = ''
		if has('win32')
			" Just drop through to the default for windows
		else
			if match(&shell, '\(bash\|zsh\)$') >= 0
				let ppid = '$PPID'
			else
				let ppid = '$$'
			endif

			let tmpfile = tempname()
			silent execute '!ps -o command= -p ' . ppid . ' > ' . tmpfile
			for line in readfile(tmpfile)
				let line = matchstr(line, '^\S\+\>')
				if !empty(line) && executable(line)
					let g:vim_program = line . ' -g'
					break
				endif
			endfor
			call delete(tmpfile)
		endif

		if empty(g:vim_program)
			if has('gui_macvim')
				let g:vim_program
						\ = '/Applications/MacVim.app/Contents/MacOS/Vim -g'
			else
				let g:vim_program = v:progname
			endif
		endif
	endif
endfunction
" }}}

" Latexmk {{{

function! LatexBox_Latexmk(force)
	execute 'w'
	if expand("%:e") == "nw"
		execute '!make'
	else
		execute '!make ' . fnameescape(fnamemodify(LatexBox_GetMainTexFile(), ':t:r'))
	endif
endfunction

" }}}

" LatexmkClean {{{
function! LatexBox_LatexmkClean(cleanall)
    execute '!make clean'
endfunction
" }}}

" LatexErrors {{{
function! LatexBox_LatexErrors(status, ...)
	if a:0 >= 1
		let log = a:1 . '.log'
	else
		let log = LatexBox_GetLogFile()
	endif

	cclose

	" set cwd to expand error file correctly
	let l:cwd = fnamemodify(getcwd(), ':p')
	execute 'lcd ' . fnameescape(LatexBox_GetTexRoot())
	try
		if g:LatexBox_autojump
			execute 'cfile ' . fnameescape(log)
		else
			execute 'cgetfile ' . fnameescape(log)
		endif
	finally
		" restore cwd
		execute 'lcd ' . fnameescape(l:cwd)
	endtry

	" Always open window if started by LatexErrors command
	if a:status < 0
		botright copen
	else
		" Write status message to screen
		redraw
		if a:status > 0 || len(getqflist())>1
			echomsg 'Compiling to ' . g:LatexBox_output_type . ' ... failed!'
		else
			echomsg 'Compiling to ' . g:LatexBox_output_type . ' ... success!'
		endif

		" Only open window when an error/warning is detected
		if g:LatexBox_quickfix
			belowright cw
			if g:LatexBox_quickfix==2
				wincmd p
			endif
		endif
	endif
endfunction
" }}}

" LatexmkStatus {{{
function! LatexBox_LatexmkStatus(detailed)
	if a:detailed
		if empty(g:latexmk_running_pids)
			echo "latexmk is not running"
		else
			let plist = ""
			for [basename, pid] in items(g:latexmk_running_pids)
				if !empty(plist)
					let plist .= '; '
				endif
				let plist .= fnamemodify(basename, ':t') . ':' . pid
			endfor
			echo "latexmk is running (" . plist . ")"
		endif
	else
		let basename = LatexBox_GetTexBasename(1)
		if has_key(g:latexmk_running_pids, basename)
			echo "latexmk is running"
		else
			echo "latexmk is not running"
		endif
	endif
endfunction
" }}}

" LatexmkStop {{{
function! LatexBox_LatexmkStop(silent)
	if empty(g:latexmk_running_pids)
		if !a:silent
			let basepath = LatexBox_GetTexBasename(1)
			let basename = fnamemodify(basepath, ':t')
			echoerr "latexmk is not running for `" . basename . "'"
		endif
	else
		let basepath = LatexBox_GetTexBasename(1)
		let basename = fnamemodify(basepath, ':t')
		if has_key(g:latexmk_running_pids, basepath)
			call s:kill_latexmk_process(g:latexmk_running_pids[basepath])
			call remove(g:latexmk_running_pids, basepath)
			if !a:silent
				echomsg "latexmk stopped for `" . basename . "'"
			endif
		elseif !a:silent
			echoerr "latexmk is not running for `" . basename . "'"
		endif
	endif
endfunction
" }}}

" Commands {{{

command! -bang	Latexmk			call LatexBox_Latexmk(<q-bang> == "!")
command! -bang	LatexmkClean	call LatexBox_LatexmkClean(<q-bang> == "!")
command! -bang	LatexmkStatus	call LatexBox_LatexmkStatus(<q-bang> == "!")
command! LatexmkStop			call LatexBox_LatexmkStop(0)
command! LatexErrors			call LatexBox_LatexErrors(-1)

if g:LatexBox_latexmk_async || g:LatexBox_latexmk_preview_continuously
	autocmd BufUnload <buffer> 	call LatexBox_LatexmkStop(1)
	autocmd VimLeave * 			call <SID>kill_all_latexmk_processes()
endif

" }}}

" vim:fdm=marker:ff=unix:noet:ts=4:sw=4
