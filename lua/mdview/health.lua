-- F17: :checkhealth mdview support for Neovim users.
-- Usage: :checkhealth mdview

local M = {}

local function ok(msg)
  if vim.health and vim.health.ok then vim.health.ok(msg)
  else vim.health.report_ok(msg) end
end
local function warn(msg)
  if vim.health and vim.health.warn then vim.health.warn(msg)
  else vim.health.report_warn(msg) end
end
local function err(msg)
  if vim.health and vim.health.error then vim.health.error(msg)
  else vim.health.report_error(msg) end
end
local function start(name)
  if vim.health and vim.health.start then vim.health.start(name)
  else vim.health.report_start(name) end
end

function M.check()
  start('mdview')

  if vim.fn.exists('*matchaddpos') == 1 then
    ok('matchaddpos available')
  else
    err('matchaddpos not available — requires Vim 7.4.330+ / Neovim 0.5+')
  end

  if vim.fn.exists('g:loaded_mdview') == 1 then
    ok('plugin loaded (g:loaded_mdview is set)')
  else
    err('plugin not loaded — check your runtimepath')
  end

  if vim.fn.exists('*mdview#open') == 1 then
    ok('autoload/mdview.vim functions registered')
  else
    err('autoload/mdview.vim not on runtimepath')
  end

  local mcw = vim.g.mdview_max_col_width or 20
  ok(('g:mdview_max_col_width = %d'):format(mcw))

  local placement = vim.g.mdview_open or 'replace'
  if vim.tbl_contains({ 'replace', 'split', 'vsplit', 'tab' }, placement) then
    ok(('g:mdview_open = %q'):format(placement))
  else
    warn(('g:mdview_open = %q (unrecognized; falling back to "replace")'):format(placement))
  end

  if vim.fn.has('mac') == 1 then ok('platform: macOS — gx will use `open`')
  elseif vim.fn.has('unix') == 1 then ok('platform: unix — gx will use `xdg-open`')
  elseif vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    ok('platform: windows — gx will use `start`')
  else warn('platform unrecognized — gx may not open URLs externally') end
end

return M
