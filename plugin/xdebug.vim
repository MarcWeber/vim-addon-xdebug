command! -bar -nargs=0 XDbgStart call XDebugMappings() | call xdebug#Start()
command! -bar -nargs=0 XDbgKill  call g:xdebug.ctx.kill()
command! -bar -nargs=0 XDbgStop  call g:xdebug.ctx.send('stop')
command! -bar -nargs=0 XDbgStack call xdebug#StackGet()
command! -bar -nargs=0 XDbgPrintKey :echo '?XDEBUG_SESSION_START=ECLIPSE_DBGP&KEY=12894211795611'


sign define xdebug_current_line text=> linehl=Type

if !exists('*XDebugMappings')
  fun! XDebugMappings()
     noremap <F5> :call g:xdebug.ctx.send('step_into')<cr>
     noremap <F6> :call g:xdebug.ctx.send('step_over')<cr>
     noremap <F7> :call g:xdebug.ctx.send('step_out')<cr>
     noremap <F8> :call g:xdebug.ctx.send('run')<cr>
  endf
endif
