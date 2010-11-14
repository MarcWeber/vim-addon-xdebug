if !exists('g:xdebug') | let g:xdebug = {} | endif | let s:c = g:xdebug
command! -bar -nargs=0 XDbgStart let g:xdebug.debugging = 1 |call XDebugMappings() | call xdebug#Start()
command! -bar -nargs=0 XDbgKill  let g:xdebug.debugging = 0 | call g:xdebug.ctx.kill()
command! -bar -nargs=0 XDbgStop  call g:xdebug.ctx.send('stop')
command! -bar -nargs=0 XDbgStackToQF call xdebug#StackToQF()
command! -bar -nargs=0 XDbgPrintKey :echo '?XDEBUG_SESSION_START=ECLIPSE_DBGP&KEY=12894211795611'
command! -bar -nargs=0 XDbgVarView call xdebug#VarView()


sign define xdebug_current_line text=> linehl=Type

if !exists('*XDebugMappings')
  fun! XDebugMappings()
     noremap <F5> :call g:xdebug.ctx.send('step_into')<cr>
     noremap <F6> :call g:xdebug.ctx.send('step_over')<cr>
     noremap <F7> :call g:xdebug.ctx.send('step_out')<cr>
     noremap <F8> :call g:xdebug.ctx.send('run')<cr>
  endf
endif
