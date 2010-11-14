" exec scriptmanager#DefineAndBind('s:c','g:xdebug','{}')
if !exists('g:xdebug') | let g:xdebug = {} | endif | let s:c = g:xdebug

let s:c.cmd_nr = get(s:c,'cmd_nr',0)
let s:c.request_handlers = get(s:c, 'request_handlers', {})
let s:c.max_depth = get(s:c, 'max_depth', 5)
let s:c.max_children = get(s:c, 'max_depth', 5)

fun! xdebug#Start(...)
  echom "switching syn off because Vim crashes when keeping it on ??"
  syn off
  let override = a:0 > 0 ? a:1 : {}
  let opts = {'port': 9000}

  let s:c.log = []

  call extend(opts , override, "force")

  let ctx = {'cmd' : 'socat TCP-L:'.opts['port'].' -', 'zero_aware': 1}
  let s:c.ctx = ctx
  if !has_key(opts,'log_bufnr')
    sp | enew
    let ctx.log_bufnr = bufnr('%')
  else
    let ctx.log_bufnr = opts.log_bufnr
  endif
  let ctx.pending = [""]

  fun ctx.log(lines)
    call async#DelayUntilNotDisturbing('xdebug', {'delay-when': ['buf-invisible:'. self.log_bufnr, 'in-cmdbuf'], 'fun' : function('async#ExecInBuffer'), 'args':  [self.log_bufnr, function('append'), ['$',a:lines]]})
  endf

  let ctx.receive = function("xdebug#Receive")

  fun ctx.sendCmd(s)
    " \0 terminated!
    call self.write([a:s,''])
  endf

  fun ctx.terminated()
    if s:c.debugging
      call self.log(["socat died with code : ". self.status." restarting"])
    endif
    " reuse same bufnr
    call xdebug#Start({'log_bufnr' : self.log_bufnr})
  endf

  fun ctx.started()
    call self.log(["socat pid :". self.pid])
  endf

  " send command using automatic unique id
  fun ctx.send(cmd, ...)
    let append = a:0 > 0 ? ' -- '.base64#b64encode(a:1) : ""
    let s:c.cmd_nr +=1
    let l = matchlist(a:cmd, '^\(\S\+\)\(.*\)')
    let cmd = l[1].' -i '. s:c.cmd_nr.l[2].append
    call self.log('>'.cmd)
    call self.write([cmd,''])
    return s:c.cmd_nr
  endf

  call async#Exec(ctx)

endf

fun! xdebug#Receive(data, ...) dict
  let self.pending[-1] = self.pending[-1].a:data[0]
  let self.pending += a:data[1:]

  while len(self.pending) > 2
    " pending[0] is length encoding
    " parse XML result
    try
      call xdebug#HandleXdebugReply(self.pending[1])
    catch /.*/
      call self.log(v:exception)
    endtry

    let self.pending = self.pending[2:]
  endwhile
endf


function! s:dump(node, indent, reslist)
  if type(a:node) == 1
    let value = a:node
	let value = substitute(value, "\n", '\\n', 'g')
	let value = substitute(value, "\t", '\\t', 'g')
	let value = substitute(value, '"', '\"', 'g')
    call add(a:reslist, repeat(' ',a:indent).'"'.value.'"')
  elseif type(a:node) == 3
    for n in a:node
	  call s:dump(n, a:indent, a:reslist)
    endfor
    return
  elseif type(a:node) == 4
    call add(a:reslist, repeat(' ',a:indent).a:node.name)
    for attr in keys(a:node.attr)
      call add(a:reslist, repeat(' ',a:indent + 2).'* '.attr.'='.a:node.attr[attr])
    endfor
    for c in a:node.child
      call s:dump(c, a:indent + 4, a:reslist)
      unlet c
    endfor
  endif
endfunction

fun! xdebug#HandleXdebugReply(xml) abort
  let xmlO = xml#parse(a:xml)
  let debugView = []
  call s:dump(xmlO, 0, debugView)
  " let debugView = split(xmlO.toString(),"\n")
  call s:c.ctx.log(['call xdebug#HandleXdebugReply('''.substitute(a:xml,"'","''",'g').''')'] + debugView)

  let transaction_id = get(xmlO.attr,'transaction_id',"-1").''
  if has_key(s:c.request_handlers, transaction_id)
    let args = s:c.request_handlers[transaction_id]
    call add(args[1], xmlO)
    call call(function('call'), args)
    " unlet s:c.request_handlers[transaction_id]
  elseif xmlO.name == 'init'
    " step to first line so that user sees that something happened
    sp | call s:c.ctx.send('step_into')

    " call s:c.ctx.send('show_hidden -v 1')
    call s:c.ctx.send('feature_set -n max_depth -v '. s:c.max_depth)
    call s:c.ctx.send('feature_set -n max_children -v '. s:c.max_children)

  elseif xmlO.find('xdebug:message') != {}
    call s:SetCurrentLine(xmlO.find('xdebug:message'))
  elseif xmlO.attr.status == 'stopping'
    call xdebug#SetCurr()
    " finish debugging:
    call s:c.ctx.send('run')
  endif
endf

fun! s:SetCurrentLine(message)
  if has_key(a:message,'attr') && has_key(a:message.attr,'filename') && has_key(a:message.attr,'lineno')
    call xdebug#SetCurr(s:FileNameFromUri(a:message.attr.filename), a:message.attr.lineno)
  endif
endf

" SetCurr() (no debugging active
" SetCurr(file, line)
" mark that line as line which will be executed next
fun! xdebug#SetCurr(...)
  if a:0 == 0
    call vim_addon_signs#Push("xdebug_current_line", [] )
  else
    call buf_utils#GotoBuf(a:1, {'create':1})
    exec a:2
    call vim_addon_signs#Push("xdebug_current_line", [[bufnr(a:1), a:2, "xdebug_current_line"]] )
    "normal zz
  endif
  call xdebug#UpdateVarView()
endf

fun! s:FileNameFromUri(uri)
  return substitute(a:uri,'^file:\/\/','', '')
endf
fun! xdebug#UriOfFilename(f)
  return 'file://'.fnamemodify(a:f,':p')
endf

fun! xdebug#HandleStackReply(xmlO, ...)
  let l = []
  for s in a:xmlO.findAll('stack')
    let a = s.attr
    call add(l, {'filename': s:FileNameFromUri(a.filename), 'lnum': a.lineno, 'text' : a.level.' '. a.type . ' ' . a.where })
  endfor
  call setqflist(l)
endf

fun! xdebug#StackToQF(...)
  let depth = a:0 > 0 ? ' -d'.a:1 : ''
  let s:c.request_handlers[g:xdebug.ctx.send('stack_get'.depth)] = [function('xdebug#HandleStackReply'),[]]
endf

fun! xdebug#FormatResult(xmlO)
  let type = a:xmlO.attr.type
  let n = get(a:xmlO.attr,'name','')
  if type == "array"
    let lines = []
    let childs_found = len(a:xmlO.child)
    for lx in map(copy(a:xmlO.child), 'xdebug#FormatResult(v:val)')
      let lines = lines + lx
    endfor
    let num_should = a:xmlO.attr.numchildren * 1
    if num_should * 1 != childs_found
      call add(lines, num_should - childs_found. ' childs omitted, increase max_depth ')
    endif
  elseif type == "null"
    let lines = [ "null" ]
  else
    let cdata = matchstr(a:xmlO.child[0],'[\r\n ]*\zs[^\r\n ]*\ze')
    if type == "int"
      let lines = [cdata]
    elseif type == "string"
      let lines = [string(base64#b64decode(cdata))]
    else
      let lines = ['TODO: FormatResult '. a:xmlO.toString()]
    endif
  endif
  if n == ''
    return lines
  else
    " return [n] + map(map(lines), string(repeat(' ',2)).'.v:val')
    return [n.': '. lines[0]] + map(copy(lines[1:]), string(repeat(' ',len(n)+2)).'.v:val')
  endif
endf

fun! xdebug#ShowEvalResult(xmlO, ...)
  let lines = xdebug#FormatResult(a:xmlO.find('property'))
  call s:c.ctx.log(lines)
endf

fun! xdebug#Eval(expr)
  let s:c.request_handlers[g:xdebug.ctx.send('eval', a:expr)] = [function('xdebug#ShowEvalResult'),[]]
endf

let s:auto_watch_end = '== auto watch end =='

" creates / shows the var view buffer.
" Add "watch: $_GET" lines if you want to watch the contents of $_GET
fun! xdebug#VarView()
  let buf_name = "XDEBUG_VAR_VIEW"
  let cmd = buf_utils#GotoBuf(buf_name, {'create':1} )
  if cmd == 'e' && !exists('b:did_init')
    let b:did_init = 1
    " new buffer, set commands etc
    let s:c.var_view_buf_nr = bufnr('%')
    au BufWinEnter <buffer> call xdebug#VarView()
    command -buffer UpdateWatchView call xdebug#UpdateVarView()
    vnoremap <buffer> <cr> y:let g:xdebug.request_handlers[g:xdebug.ctx.send('eval', getreg('"'))] = [function('xdebug#AppendToVarView'),[]]<cr>
    call append(0,['watch $_GET', s:auto_watch_end
          \ , 'The watch results will be pasted below the watch: lines'
          \ , 'This text here will not be touched. You can eval PHP by typing, visually selecting and pressing <cr>'
          \ ])
    set buftype=nofile
  endif

  let buf_nr = bufnr(buf_name)
  if buf_nr == -1
    exec 'sp '.fnameescape(buf_name)
  endif
endf

fun! xdebug#BreakPointsBuffer()
  let buf_name = "XDEBUG_BREAK_POINTS_VIEW"
  let cmd = buf_utils#GotoBuf(buf_name, {'create':1} )
  if cmd == 'e' && !exists('b:did_init')
    let b:did_init = 1
    " new buffer, set commands etc
    let s:c.var_view_buf_nr = bufnr('%')
    au BufWinEnter <buffer> call xdebug#VarView()
    command -buffer UpdateWatchView call xdebug#UpdateVarView()
    vnoremap <buffer> <cr> y:let g:xdebug.request_handlers[g:xdebug.ctx.send('eval', getreg('"'))] = [function('xdebug#AppendToVarView'),[]]<cr>
    call append(0,['watch $_GET', s:auto_break_end
          \ , 'XDebug supports different types of breakpoints. The following types are supported
          \ , '#line:file:line: [if condition]'
          \ , '#call:function [if condition]'
          \ , '#return:function [if condition]'
          \ , '#exception:exception_name [if condition]'
          \ , '#conditional:filename: condition'
          \ , '#watch: expr'
          \ ])
    set buftype=nofile
  endif

  let buf_nr = bufnr(buf_name)
  if buf_nr == -1
    exec 'sp '.fnameescape(buf_name)
  endif
endf

fun! xdebug#AppendToVarView(xmlO)
  let lines = xdebug#FormatResult(a:xmlO.find('property'))
  " make buffer visible
  call xdebug#VarView()
  call append('$',lines)
endf

" see xdebug#VarView()
fun! xdebug#UpdateVarView()
  let win_nr = bufwinnr(get(s:c, 'var_view_buf_nr', -1))
  " only update view if buffer is visible (for speed reasons
  if win_nr == -1 | return | endif
  let old_win_nr = winnr()
  exec win_nr.' wincmd w'

  for l in getline('0',line('$'))
    if l =~ s:auto_watch_end | break | endif
    let watch_expr = matchstr(l, '^watch\s\+\zs.*\ze')
    if watch_expr != ''
      " should be using get_var or such which accepts stack level (not supported yet)
      " let watch_expr = " try { $result_XYZ = ".watch_expr."; } catch (Exception $e) { $result_XYZ = $e->getMessage(); } $result_XYZ"
      let s:c.request_handlers[g:xdebug.ctx.send('eval', watch_expr)] = [function('xdebug#HandleWatchExprResult'),[watch_expr]]
    endif
  endfor
  let curr_buf = bufnr('%')

  normal gg
  let end = search(s:auto_watch_end,'')
  exec 1.','.end.':g/'.'^|  '.'/d'
  exec old_win_nr.' wincmd w'
endf
fun! xdebug#HandleWatchExprResult(watch_expr, xmlO, ...)
  let lines = xdebug#FormatResult(a:xmlO.find('property'))

  let win_nr = bufwinnr(get(s:c, 'var_view_buf_nr', -1))
  let old_win_nr = winnr()
  exec win_nr.' wincmd w'

  normal gg
  let line = search('^watch\s\+'.escape(a:watch_expr, '$%\'),'w', s:auto_watch_end)
  call append(line, map(lines, string('|  ').'.v:val'))
  exec old_win_nr.' wincmd w'
endf

" stack_get  (stdout which will be flushed in CDATA base64 encoded)
" detach (stop debugging, continue runnig)
"
" breakpoint_set
" breakpoint_get
" breakpoint_update
" breakpoint_remove
" breakpoint_list
"
" breakpoint types:
"  line, call, return, exception, conditional, watch
"
" break (run -> break)
" eval -i transaction_id -- {DATA}
" json_encoding#Encode(
"
"  stack_get [-d depth]
