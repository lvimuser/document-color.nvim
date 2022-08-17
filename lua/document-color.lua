local helpers = require("document-color.helpers")

local M = {}
local NAMESPACE = vim.api.nvim_create_namespace("lsp_documentColor")
local MODE_NAMES = { background = "mb", foreground = "mf", single = "mb" }

local OPTIONS = {
  mode = "background",
}

local STATE = {
  ATTACHED_BUFFERS = {},
  ATTACHED_CLIENTS = {},
  HIGHLIGHTS = {},
}

function M.setup(options)
  OPTIONS = helpers.merge(OPTIONS, options)
end

local function create_highlight(color)
  -- This will create something like "mb_d023d9"
  local cache_key = table.concat({ MODE_NAMES[OPTIONS.mode], color }, "_")

  if STATE.HIGHLIGHTS[cache_key] then
    return STATE.HIGHLIGHTS[cache_key]
  end

  -- This will create something like "lsp_documentColor_mb_d023d9", safe to start adding to neovim
  local highlight_name = table.concat({ "lsp_documentColor", MODE_NAMES[OPTIONS.mode], color }, "_")

  if OPTIONS.mode == "foreground" then
    vim.cmd(string.format("highlight %s guifg=#%s", highlight_name, color))
  else
    -- TODO: Make this bit less dumb, especially since helpers.lsp_color_to_hex exists
    local r, g, b = color:sub(1, 2), color:sub(3, 4), color:sub(5, 6) -- consider "3b82f6". `r` = "3b"
    r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) -- eg. Change "3b" -> "59"

    vim.cmd(
      string.format(
        "highlight %s guifg=%s guibg=#%s",
        highlight_name,
        helpers.color_is_bright(r, g, b) and "Black" or "White",
        color
      )
    )
  end

  STATE.HIGHLIGHTS[cache_key] = highlight_name

  return highlight_name
end

local function handler(results, bufnr)
  -- TODO namespace/cleanup per client id
  for id, r in pairs(results) do
    if not STATE.ATTACHED_CLIENTS[id] then
      goto continue
    end

    if r.error and #r.error > 0 then
      vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
      vim.notify_once("document color\n" .. vim.inspect(r.error), vim.log.levels.ERROR)
      goto continue
    end

    local colors = r.result
    if not colors then
      goto continue
    end

    for _, info in pairs(colors) do
      info.color = helpers.lsp_color_to_hex(info.color)

      local range = info.range
      -- Start highlighting range with color inside `bufnr`
      vim.api.nvim_buf_add_highlight(
        bufnr,
        NAMESPACE,
        create_highlight(info.color),
        range.start.line,
        range.start.character,
        OPTIONS.mode == "single" and range.start.character + 1 or range["end"].character
      )
    end
    ::continue::
  end
end

--- Fetch and update highlights in the buffer
function M.update_highlights(bufnr)
  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  vim.lsp.buf_request_all(bufnr, "textDocument/documentColor", params, function(results)
    handler(results, bufnr)
  end)
end

local debounced_fn
local function set_debounced_fn(client)
  if debounced_fn then
    return debounced_fn
  end

  local delay = math.max(client.config.flags.debounce_text_changes or 0, 200)
  local _, fn = require("document-color.defer").debounce(function(bufnr)
    M.update_highlights(bufnr)
  end, delay)

  debounced_fn = fn
end

function M.buf_attach(bufnr, client)
  set_debounced_fn(client)
  bufnr = helpers.get_bufnr(bufnr)

  STATE.ATTACHED_CLIENTS[client.id] = true
  if STATE.ATTACHED_BUFFERS[bufnr] then
    return
  end
  STATE.ATTACHED_BUFFERS[bufnr] = true

  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      if not STATE.ATTACHED_BUFFERS[bufnr] then
        return true -- detach
      end
      debounced_fn(bufnr)
    end,
    on_detach = function()
      STATE.ATTACHED_BUFFERS[bufnr] = nil
    end,
  })

  -- Wait for server to load.
  vim.defer_fn(function()
    M.update_highlights(bufnr)
  end, 3000)
end

--- Can be used to detach from the buffer at any time
function M.buf_detach(bufnr)
  bufnr = helpers.get_bufnr(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  STATE.ATTACHED_BUFFERS[bufnr] = nil
end

function M.buf_toggle(bufnr)
  bufnr = helpers.get_bufnr(bufnr)
  if STATE.ATTACHED_BUFFERS[bufnr] then
    M.buf_detach(bufnr)
  else
    M.buf_attach(bufnr)
  end
end

return M
