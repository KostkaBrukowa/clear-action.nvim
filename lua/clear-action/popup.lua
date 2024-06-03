local M = {}

local config = require("clear-action.config")

vim.api.nvim_set_hl(0, "CodeActionHeader", { link = "Bold" })
vim.api.nvim_set_hl(0, "CodeActionTitle", { link = "Normal" })
vim.api.nvim_set_hl(0, "CodeActionLabel", { fg = "#f7768e", bold = true, italic = true })
vim.api.nvim_set_hl(0, "CodeActionCursor", { reverse = true, blend = 100 })

local function hide_cursor() vim.opt.guicursor:append("a:CodeActionCursor/CodeActionCursor") end
local function show_cursor() vim.opt.guicursor:remove("a:CodeActionCursor/CodeActionCursor") end

local function hide_cursor_until_leave_buffer()
  hide_cursor()
  vim.api.nvim_create_autocmd({ "bufleave" }, {
    group = config.augroup,
    callback = show_cursor,
    buffer = 0,
  })
end

-- Hide cursor in popup
M.hide_cursor_autocmd = function()
  vim.api.nvim_create_autocmd("FileType", {
    group = config.augroup,
    pattern = "CodeAction",
    callback = hide_cursor_until_leave_buffer,
  })
end

local function client_name(client_id)
  local client = vim.lsp.get_client_by_id(client_id)
  return client and client.name or ""
end

local function findIndex(table, element)
  for i, value in ipairs(table) do
    if value == element then return i end
  end
  return nil
end

local function create_popup(action_tuples)
  local opts = config.options.popup
  local max_len = 0
  for _, value in pairs(action_tuples) do
    local len = #value[2].title
    if not config.options.popup.hide_client then
      len = len + #client_name(value[1])
    end
    if max_len < len then max_len = len end
  end
  local width = max_len + 6
  local height = #action_tuples + 1
  local row, col, position

  if opts.center then
    local ui = vim.api.nvim_list_uis()[1]
    row = (ui.height - height) * 0.5
    col = (ui.width - width) * 0.5
    position = "editor"
  else
    row = 1
    col = 0
    position = "cursor"
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(bufnr, true, {
    row = row,
    col = col,
    width = width,
    height = height,
    border = opts.border,
    relative = position,
    style = "minimal",
  })

  vim.wo[win].signcolumn = "yes:1"
  vim.bo[bufnr].filetype = "CodeAction"

  return win, bufnr
end

local function fill_popup(bufnr, action_tuples, labels)
  local opts = config.options.popup

  local lines = vim.tbl_map(function(value)
    local title = value[2].title
    local row = labels[title] .. " " .. title
    if not config.options.popup.hide_client then
      row = row .. " " .. client_name(value[1])
    end
    return row
  end, action_tuples)

  table.insert(lines, 1, "Code actions:")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
  vim.api.nvim_buf_add_highlight(bufnr, config.ns_popup, opts.highlights.header, 0, 0, -1)

  for i, action_tuple in ipairs(action_tuples) do
    vim.api.nvim_buf_add_highlight(bufnr, config.ns_popup, opts.highlights.label, i, 0, 1)
    local len = #action_tuple[2].title
    vim.api.nvim_buf_add_highlight(bufnr, config.ns_popup, opts.highlights.title, i, 2, len + 2)
    vim.api.nvim_buf_add_highlight(bufnr, config.ns_popup, opts.highlights.lsp, i, len + 2, -1)
  end

  vim.bo[bufnr].modifiable = false
end

local function create_labels(action_tuples)
  local labels = {}
  local used = {}

  for _, value in pairs(action_tuples) do
    local title = value[2].title
    local first_letter = title:sub(1, 1):lower()
    local client = client_name(value[1])

    local user_defined = (config.options.action_labels[client] or {})[title]

    if user_defined then
      used[user_defined] = true
      labels[title] = user_defined
    else
      if not used[first_letter] then
        used[first_letter] = true
        labels[title] = first_letter
      end
    end
  end

  local fallback = "n"
  for _, value in pairs(action_tuples) do
    local title = value[2].title

    if not labels[title] then
      -- stylua: ignore
      local alphabet = {  "n", "e", "i", "o", "a", "r", "s", "t", "b", "c", "f", "g", "h", "j", "k", "l", "m", "p", "q", "u", "v", "w", "x", "y", "z", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", }
      local index = findIndex(alphabet, fallback)
      while used[fallback] do
        index = index + 1
        fallback = alphabet[index]
      end
      if fallback:byte() > 122 then fallback = "A" end
      used[fallback] = true
      labels[title] = fallback
    end
  end

  return labels
end

local function apply_keymaps(win, bufnr, action_tuples, labels, on_select)
  local close_win = function()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end

  for _, value in pairs(action_tuples) do
    vim.keymap.set("n", labels[value[2].title], function()
      on_select(value)
      close_win()
    end, { buffer = bufnr, nowait = true })
  end

  vim.keymap.set("n", "<Esc>", close_win, { buffer = bufnr })
  vim.keymap.set("n", "<Enter>", function()
    on_select(action_tuples[1])
    close_win()
  end, { buffer = bufnr })
end

M.select = function(action_tuples, on_select)
  local win, bufnr = create_popup(action_tuples)
  local labels = create_labels(action_tuples)
  fill_popup(bufnr, action_tuples, labels)
  apply_keymaps(win, bufnr, action_tuples, labels, on_select)
end

return M
