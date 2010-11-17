if !exists('g:xdebug') | let g:xdebug = {} | endif | let s:c = g:xdebug
command! -bar -nargs=0 XDbgStart let g:xdebug.debugging = 1 |call XDebugMappings() | call xdebug#Start()
command! -bar -nargs=0 XDbgKill  let g:xdebug.debugging = 0 | call g:xdebug.ctx.kill()
command! -bar -nargs=0 XDbgStop  call g:xdebug.ctx.send('stop')
command! -bar -nargs=0 XDbgStackToQF call xdebug#StackToQF()
command! -bar -nargs=0 XDbgCopyKey call setreg('*', '?XDEBUG_SESSION_START=ECLIPSE_DBGP&KEY=12894211795611')
command! -bar -nargs=0 XDbgVarView call xdebug#VarView()
command! -bar -nargs=0 XDbgBreakPoints call xdebug#BreakPointsBuffer()

command! -bar -nargs=0 XDbgRun call xdebug.ctx.send('run')

command! -bar -nargs=1 XDbgSetMaxDepth    call g:xdebug.ctx.send('feature_set -n max_depth -v '. <f-args>)
command! -bar -nargs=1 XDbgSetMaxData    call g:xdebug.ctx.send('feature_set -n max_data -v '. <f-args>)
command! -bar -nargs=1 XDbgSetMaxChildren call g:xdebug.ctx.send('feature_set -n max_children -v '. <f-args>)
command! -bar -nargs=0 XDbgToggleLineBreakpoint call xdebug#ToggleLineBreakpoint()

command! -bar -nargs=0 XDbgRunTillCursor call g:xdebug.ctx.send('breakpoint_set -f '. xdebug#UriOfFilename(expand('%')).' -t line -n '.getpos('.')[1].' -r 1') | XDbgRun 

sign define xdebug_current_line text=> linehl=Type
sign define xdebug_breakpoint text=O   linehl=ErrorMsg

if !exists('*XDebugMappings')
  fun! XDebugMappings()
     noremap <F5> :call g:xdebug.ctx.send('step_into')<cr>
     noremap <F6> :call g:xdebug.ctx.send('step_over')<cr>
     noremap <F7> :call g:xdebug.ctx.send('step_out')<cr>
     noremap <F8> :XDbgRun<cr>
     noremap <F9> :XDbgToggleLineBreakpoint<cr>
  endf
endif
