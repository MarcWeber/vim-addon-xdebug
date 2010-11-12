" exec scriptmanager#DefineAndBind('s:c','g:xdebug','{}')
if !exists('g:xdebug') | let g:xdebug = {} | endif | let s:c = g:xdebug

let s:c.cmd_nr = get(s:c,'cmd_nr',0)
let s:c.request_handlers = get(s:c, 'request_handlers', {})

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
    call self.log(["socat died with code : ". self.status." restarting"])
    " reuse same bufnr
    call xdebug#Start({'log_bufnr' : self.log_bufnr})
  endf

  fun ctx.started()
    call self.log(["socat pid :". self.pid])
  endf

  " send command using automatic unique id
  fun ctx.send(cmd)
    let s:c.cmd_nr +=1
    let l = matchlist(a:cmd, '^\(\S\+\)\(.*\)')
    let cmd = l[1].' -i '. s:c.cmd_nr.(l[2] == '' ? '' : ' ').l[2]
    call self.log('>'.cmd)
    call self.write([cmd,''])
    return s:c.cmd_nr
  endf

  call async#Exec(ctx)

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

fun! xdebug#Receive(...) dict
  call call(function('xdebug#Receive2'),a:000, self)
endf

fun! xdebug#Receive2(data, ...) dict
  try
    let self.pending[-1] = self.pending[-1].a:data[0]
    let self.pending += a:data[1:]

    while len(self.pending) > 2
      " pending[0] is length encoding
      " parse XML result
      let xml = self.pending[1]
      let xmlO = xml#parse(xml)
      let debugView = []
      call s:dump(xmlO, 0, debugView)
      " let debugView = split(xmlO.toString(),"\n")
      call self.log(['<'.xml] + debugView)
      let self.pending = self.pending[2:]

      let transaction_id = get(xmlO.attr,'transaction_id',"-1").''
      if has_key(s:c.request_handlers, transaction_id)
        let args = s:c.request_handlers[transaction_id]
        call add(args[1], xmlO)
        call call(function('call'), args)
        unlet s:c.request_handlers[transaction_id]
      elseif xmlO.name == 'init'
        " step to first line so that user sees that something happened
        sp | call self.send('step_into')
      elseif xmlO.find('xdebug:message') != {}
        call s:SetCurrentLine(xmlO.find('xdebug:message'))
      endif
    endwhile
  catch /.*/
    call self.log(v:excption)
  endtry
endf

fun! s:SetCurrentLine(message)
  if has_key(a:message,'attr') && has_key(a:message.attr,'filename') && has_key(a:message.attr,'lineno')
    let file = s:FileNameFromUri(a:message.attr.filename)
    if bufnr(file) == -1
      exec 'e '.fnameescape(file)
    else
      exec 'b '.bufnr(file)
    endif
    exec a:message.attr.lineno
    call vim_addon_signs#Push("xdebug_current_line", [[bufnr('%'), a:message.attr.lineno, "xdebug_current_line"]] )
  endif
endf

fun! s:FileNameFromUri(uri)
  return substitute(a:uri,'^file:\/\/','', '')
endf

fun! xdebug#HandleStackReply(xmlO, ...)
  let l = []
  for s in a:xmlO.findAll('stack')
    let a = s.attr
    call add(l, {'filename': s:FileNameFromUri(a.filename), 'lnum': a.lineno, 'text' : a.level.' '. a.type . ' ' . a.where })
  endfor
  call setqflist(l)
endf

fun! xdebug#StackGet(...)
  let depth = a:0 > 0 ? ' -d'.a:1 : ''
  let s:c.request_handlers[g:xdebug.ctx.send('stack_get'.depth)] = [function('xdebug#HandleStackReply'),[]]
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
