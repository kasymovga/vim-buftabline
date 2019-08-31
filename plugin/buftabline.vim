" Vim global plugin for rendering the buffer list in the tabline
" Licence:     The MIT License (MIT)
" Commit:      $Format:%H$
" {{{ Copyright (c) 2015 Aristotle Pagaltzis <pagaltzis@gmx.de>
" 
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to deal
" in the Software without restriction, including without limitation the rights
" to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
" copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
" 
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
" 
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
" OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
" THE SOFTWARE.
" }}}

if v:version < 700
	echoerr printf('Vim 7 is required for buftabline (this is only %d.%d)',v:version/100,v:version%100)
	finish
endif

scriptencoding utf-8

hi default link BufTabLineCurrent TabLineSel
hi default link BufTabLineActive  PmenuSel
hi default link BufTabLineHidden  TabLine
hi default link BufTabLineFill    TabLineFill

let g:buftabline_numbers    = get(g:, 'buftabline_numbers',    2)
let g:buftabline_indicators = get(g:, 'buftabline_indicators', 1)
let g:buftabline_separator_left = get(g:, 'buftabline_separator_left', '[')
let g:buftabline_separator_right = get(g:, 'buftabline_separator_right', ']')
let g:buftabline_separator_first = get(g:, 'buftabline_separator_first', g:buftabline_separator_left)
let g:buftabline_separator_last = get(g:, 'buftabline_separator_last', g:buftabline_separator_right)
let g:buftabline_separator_center = get(g:, 'buftabline_separator_center', ' ')
let g:buftabline_show       = get(g:, 'buftabline_show',       2)

function! buftabline#user_buffers() " help buffers are always unlisted, but quickfix buffers are not
	return filter(range(1,bufnr('$')),'buflisted(v:val) && "quickfix" !=? getbufvar(v:val, "&buftype")')
endfunction

function! buftabline#num_to_buf(num)
	if !a:num
		return bufnr('')
	endif
	let bufnums = buftabline#user_buffers()
	if len(bufnums) < a:num || a:num <= 0
		return -1
	endif
	return bufnums[a:num - 1]
endfunction

function! buftabline#goto_tab(num)
	let buf = buftabline#num_to_buf(a:num)
	if buf > 0
		execute "b" . buf
	endif
endfunction

function! buftabline#close_tab(action, bang, num)
	let buffer = buftabline#num_to_buf(a:num)
	let w:bbye_back = 1
	if buffer < 0
		return
	endif
	if getbufvar(buffer, "&modified") && empty(a:bang)
		echohl ErrorMsg
		echomsg "E89: No write since last change for " . (a:num ? "tab " . a:num : "current tab") . " (add ! to override)"
		echohl NONE
		return
	endif
	" If the buffer is set to delete and it contains changes, we can't switch
	" away from it. Hide it before eventual deleting:
	if getbufvar(buffer, "&modified") && !empty(a:bang)
		call setbufvar(buffer, "&bufhidden", "hide")
	endif
	" For cases where adding buffers causes new windows to appear or hiding some
	" causes windows to disappear and thereby decrement, loop backwards.
	for window in reverse(range(1, winnr("$")))
		" For invalid window numbers, winbufnr returns -1.
		if winbufnr(window) != buffer | continue | endif
			execute window . "wincmd w"
		" Bprevious also wraps around the buffer list, if necessary:
			try
				exe bufnr("#") > 0 && buflisted(bufnr("#")) ? "buffer #" : "bprevious"
			catch /^Vim([^)]*):E85:/ " E85: There is no listed buffer
			endtry
		" If found a new buffer for this window, mission accomplished:
		if bufnr("%") != buffer | continue | endif
		exe "enew" . a:bang
		"setl noswapfile
		" If empty and out of sight, delete it right away:
		"setl bufhidden=wipe
		" Regular buftype warns people if they have unsaved text there.  Wouldn't
		" want to lose someone's data:
		"setl buftype=
		" Hide the buffer from buffer explorers and tabbars:
		" setl nobuflisted
	endfor
	" Because tabbars and other appearing/disappearing windows change
	" the window numbers, find where we were manually:
	let back = filter(range(1, winnr("$")), "getwinvar(v:val, 'bbye_back')")[0]
	if back | exe back . "wincmd w" | unlet w:bbye_back | endif
	" If it hasn't been already deleted by &bufhidden, end its pains now.
	" Unless it previously was an unnamed buffer and :enew returned it again.
	"
	" Using buflisted() over bufexists() because bufhidden=delete causes the
	" buffer to still _exist_ even though it won't be :bdelete-able.
	if buflisted(buffer) && buffer != bufnr("%")
		exe a:action . a:bang . " " . buffer
	endif
endfunction


function! buftabline#list_tabs()
	let bufnums = buftabline#user_buffers()
	let i = 0
	for bufnum in bufnums
		let i += 1
		let modified = (getbufvar(bufnum, '&modified') ? "+" : " ")
		echo printf("%3d%s %s", i, modified, bufname(bufnum))
	endfor
endfunction

let s:dirsep = fnamemodify(getcwd(),':p')[-1:]
let s:centerbuf = winbufnr(0)
function! buftabline#render()
	let show_num = g:buftabline_numbers == 1
	let show_ord = g:buftabline_numbers == 2
	let show_mod = g:buftabline_indicators
	let lpad     = g:buftabline_separator_left
	let rpad     = g:buftabline_separator_right
	let cpad     = g:buftabline_separator_center
	let bufnums = buftabline#user_buffers()
	if !len(bufnums)
		return ""
	endif
	let centerbuf = s:centerbuf " prevent tabline jumping around when non-user buffer current (e.g. help)
	" pick up data on all the buffers
	let tabs = []
	let path_tabs = []
	let tabs_per_tail = {}
	"let currentbuf = winbufnr(0)
	let currentbuf = bufnr('%')
	let screen_num = 0
	for bufnum in bufnums
		let screen_num = show_num ? bufnum : show_ord ? screen_num + 1 : ''
		let tab = { 'num': bufnum }
		let tab.hilite = currentbuf == bufnum ? 'Current' : bufwinnr(bufnum) > 0 ? 'Active' : 'Hidden'
		if currentbuf == bufnum | let [centerbuf, s:centerbuf] = [bufnum, bufnum] | endif
		let bufpath = bufname(bufnum)
		if strlen(bufpath)
			let tab.path = fnamemodify(bufpath, ':p:~:.')
			let tab.sep = strridx(tab.path, s:dirsep, strlen(tab.path) - 2) " keep trailing dirsep
			let tab.label = tab.path[tab.sep + 1:]
			let pre = ( show_mod && getbufvar(bufnum, '&mod') ? '+' : '' ) . screen_num
			let tab.pre = strlen(pre) ? pre . cpad : ''
			let tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
			let path_tabs += [tab]
		elseif -1 < index(['nofile','acwrite'], getbufvar(bufnum, '&buftype')) " scratch buffer
			let tab.label = ( show_mod ? '!' . screen_num : screen_num ? screen_num . ' !' : '!' )
		else " unnamed file
			let tab.label = ( show_mod && getbufvar(bufnum, '&mod') ? '+' : '' )
			\ . ( screen_num ? screen_num : '*' )
		endif
		let tabs += [tab]
	endfor
	" disambiguate same-basename files by adding trailing path segments
	while len(filter(tabs_per_tail, 'v:val > 1'))
		let [ambiguous, tabs_per_tail] = [tabs_per_tail, {}]
		for tab in path_tabs
			if -1 < tab.sep && has_key(ambiguous, tab.label)
				let tab.sep = strridx(tab.path, s:dirsep, tab.sep - 1)
				let tab.label = tab.path[tab.sep + 1:]
			endif
			let tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
		endfor
	endwhile
	" now keep the current buffer center-screen as much as possible:
	" 1. setup
	let lft = { 'lasttab':  0, 'cut':  '.', 'indicator': '<', 'width': 0, 'half': &columns / 2 }
	let rgt = { 'lasttab': -1, 'cut': '.$', 'indicator': '>', 'width': 0, 'half': &columns - lft.half }
	if len(tabs) > 1
		for tab in tabs[:len(tabs) - 2]
			let tab.label = tab.label . rpad
		endfor
	endif
	let tab = tabs[0]
	let tab.label = g:buftabline_separator_first . get(tab, 'pre', '') . tab.label
	let tab = tabs[len(tabs) - 1]
	let tab.label = tab.label . g:buftabline_separator_last
	for tab in tabs[1:len(tabs) - 1]
		let tab.label = lpad . get(tab, 'pre', '') . tab.label
	endfor
	" 2. sum the string lengths for the left and right halves
	let currentside = lft
	for tab in tabs
		let tab.width = strwidth(strtrans(tab.label))
		if centerbuf == tab.num
			let halfwidth = tab.width / 2
			let lft.width += halfwidth
			let rgt.width += tab.width - halfwidth
			let currentside = rgt
			continue
		endif
		let currentside.width += tab.width
	endfor
	if currentside is lft " centered buffer not seen?
		" then blame any overflow on the right side, to protect the left
		let [lft.width, rgt.width] = [0, lft.width]
	endif
	" 3. toss away tabs and pieces until all fits:
	if ( lft.width + rgt.width ) > &columns
		let oversized
		\ = lft.width < lft.half ? [ [ rgt, &columns - lft.width ] ]
		\ : rgt.width < rgt.half ? [ [ lft, &columns - rgt.width ] ]
		\ :                        [ [ lft, lft.half ], [ rgt, rgt.half ] ]
		for [side, budget] in oversized
			let delta = side.width - budget
			" toss entire tabs to close the distance
			while delta >= tabs[side.lasttab].width
				let delta -= remove(tabs, side.lasttab).width
			endwhile
			" then snip at the last one to make it fit
			let endtab = tabs[side.lasttab]
			while delta > ( endtab.width - strwidth(strtrans(endtab.label)) )
				let endtab.label = substitute(endtab.label, side.cut, '', '')
			endwhile
			let endtab.label = substitute(endtab.label, side.cut, side.indicator, '')
		endfor
	endif
	let swallowclicks = '%'.(1 + tabpagenr('$')).'X'
	return swallowclicks . join(map(tabs,'printf("%%#BufTabLine%s#%s",v:val.hilite,strtrans(v:val.label))'),'') . '%#BufTabLineFill#'
endfunction

function! buftabline#update(zombie)
	set tabline=
	if tabpagenr('$') > 1 | set guioptions+=e showtabline=2 | return | endif
	set guioptions-=e
	if 0 == g:buftabline_show
		set showtabline=1
		return
	elseif 1 == g:buftabline_show
		" account for BufDelete triggering before buffer is actually deleted
		let bufnums = filter(buftabline#user_buffers(), 'v:val != a:zombie')
		let &g:showtabline = 1 + ( len(bufnums) > 1 )
	elseif 2 == g:buftabline_show
		set showtabline=2
	endif
	set tabline=%!buftabline#render()
endfunction

augroup BufTabLine
autocmd!
autocmd VimEnter  * call buftabline#update(0)
autocmd TabEnter  * call buftabline#update(0)
autocmd BufAdd    * call buftabline#update(0)
autocmd BufDelete * call buftabline#update(str2nr(expand('<abuf>')))
augroup END

if v:version < 703
	function s:transpile()
		let [ savelist, &list ] = [ &list, 0 ]
		redir => src
			silent function buftabline#render
		redir END
		let &list = savelist
		let src = substitute(src, '\n\zs[0-9 ]*', '', 'g')
		let src = substitute(src, 'strwidth(strtrans(\([^)]\+\)))', 'strlen(substitute(\1, ''\p\|\(.\)'', ''x\1'', ''g''))', 'g')
		return src
	endfunction
	exe "delfunction buftabline#render\n" . s:transpile()
	delfunction s:transpile
endif

command! -nargs=0 BTLList call buftabline#list_tabs()
command! -nargs=1 BTLGo call buftabline#goto_tab(<args>)
command! -bang -complete=buffer -nargs=? BTLDelete :call buftabline#close_tab("bdelete", <q-bang>, <q-args>)
command! -bang -complete=buffer -nargs=? BTLWipeout :call buftabline#close_tab("bwipeout", <q-bang>, <q-args>)
