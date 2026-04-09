local M = {}

local augroup = nil
local writing = false

local function refresh_oil()
  local has_oil, oil = pcall(require, "oil")
  if not has_oil then
    return
  end
  local cfg = require("cilantro.config").get()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "oil" then
      local dir = oil.get_current_dir(buf)
      if dir and vim.startswith(dir, cfg.task_dir) then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("edit")
        end)
      end
    end
  end
end

function M.setup(opts)
  local cfg = require("cilantro.config").setup(opts)

  -- Ensure task directory exists
  vim.fn.mkdir(cfg.task_dir, "p")

  -- Set up highlight groups
  require("cilantro.ui.highlights").setup()

  -- Build the initial index
  require("cilantro.index").build(cfg.task_dir)

  -- Start filesystem watcher
  require("cilantro.index").watch()

  -- Register autocmd for BufWritePost on task files
  if augroup then
    vim.api.nvim_del_augroup_by_id(augroup)
  end
  augroup = vim.api.nvim_create_augroup("Cilantro", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      local list = require("cilantro.ui.list")
      if ev.buf == list.bufnr then
        local idx = require("cilantro.index")
        idx.build(cfg.task_dir)
        list.render()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = cfg.task_dir .. "/**/*.md",
    callback = function(ev)
      if writing then
        return
      end

      local task_mod = require("cilantro.task")
      local fm = require("cilantro.frontmatter")
      local idx = require("cilantro.index")
      local list = require("cilantro.ui.list")

      local bufnr = ev.buf
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local metadata, _, _ = fm.parse(lines)

      if not metadata.id or not metadata.title then
        idx.refresh_path(ev.file)
        if list.is_visible() then
          list.render()
        end
        return
      end

      -- Update updated_at
      metadata.updated_at = os.date("!%Y-%m-%dT%H:%M:%S") .. "Z"
      local new_lines = fm.replace_frontmatter(lines, metadata)

      -- Check if title changed (needs file rename)
      local expected_filename = task_mod.make_filename(metadata.id, metadata.title)
      local current_filename = vim.fn.fnamemodify(ev.file, ":t")
      local needs_rename = expected_filename ~= current_filename

      writing = true

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

      if needs_rename then
        local dir = vim.fn.fnamemodify(ev.file, ":h")
        local new_path = dir .. "/" .. expected_filename
        vim.cmd("noautocmd saveas! " .. vim.fn.fnameescape(new_path))
        vim.fn.delete(ev.file)
        idx.remove(ev.file)
        local t = task_mod.from_file(new_path)
        if t then
          idx.put(t)
        end
        refresh_oil()
      else
        vim.cmd("noautocmd write")
        idx.refresh_path(ev.file)
      end

      writing = false

      if list.is_visible() then
        list.render()
      end
    end,
  })
end

function M.open(opts)
  opts = opts or {}
  local index = require("cilantro.index")
  local list = require("cilantro.ui.list")

  index.get()

  if opts.query then
    for k, v in pairs(opts.query) do
      list.query_opts[k] = v
    end
  end

  list.open()
end

function M.close()
  local peek = require("cilantro.ui.peek")
  local list = require("cilantro.ui.list")

  peek.close()

  local list_win = list.get_win()
  if list_win then
    vim.api.nvim_win_close(list_win, false)
  end
end

function M.toggle()
  local list = require("cilantro.ui.list")
  if list.is_visible() then
    M.close()
  else
    M.open()
  end
end

function M.create_task(input)
  local cfg = require("cilantro.config").get()
  local task_mod = require("cilantro.task")
  local index = require("cilantro.index")
  local list = require("cilantro.ui.list")

  local function do_create(raw)
    if not raw or raw == "" then
      return
    end

    local title = vim.fn.fnamemodify(raw, ":t")
    local parent = vim.fn.fnamemodify(raw, ":h")

    local dir
    if parent == "." then
      dir = cfg.task_dir
    else
      dir = cfg.task_dir .. "/" .. parent
    end

    vim.fn.mkdir(dir, "p")

    local task = task_mod.create(title, dir)
    index.put(task)

    if list.is_visible() then
      list.render()
    end

    refresh_oil()

    local peek = require("cilantro.ui.peek")
    peek.open(task)
  end

  if input then
    do_create(input)
  else
    vim.ui.input({ prompt = "Task (path/to/title): " }, function(val)
      do_create(val)
    end)
  end
end

function M.refresh()
  local cfg = require("cilantro.config").get()
  local index = require("cilantro.index")
  local list = require("cilantro.ui.list")

  index.build(cfg.task_dir)

  if list.is_visible() then
    list.render()
  end
end

return M
