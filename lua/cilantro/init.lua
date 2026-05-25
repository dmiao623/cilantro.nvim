local M = {}

local augroup = nil
local writing = false

local function refresh_file_tree()
  local cfg = require("cilantro.config").get()

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ft = vim.bo[buf].filetype

      if ft == "oil" then
        local name = vim.api.nvim_buf_get_name(buf)
        local dir = name:match("^oil://(.*)")
        if dir and vim.startswith(dir, cfg.task_dir) then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("edit")
          end)
        end
      elseif ft == "netrw" then
        local dir = vim.b[buf].netrw_curdir or ""
        if vim.startswith(dir, cfg.task_dir) then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("edit")
          end)
        end
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
    pattern = { cfg.task_dir .. "/*.md", cfg.task_dir .. "/**/*.md" },
    callback = function(ev)
      if writing then
        return
      end

      local task_mod = require("cilantro.task")
      local event_mod = require("cilantro.event")
      local fm = require("cilantro.frontmatter")
      local idx = require("cilantro.index")
      local list = require("cilantro.ui.list")

      local bufnr = ev.buf
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local raw_metadata, fm_end, _ = fm.parse(lines)
      local metadata = fm.flatten(raw_metadata)

      local is_event = metadata.type == "event"
      local model = is_event and event_mod or task_mod

      if not metadata.id or not metadata.title then
        if fm_end == 0 and not is_event then
          local new_lines, new_task = task_mod.bootstrap_lines(lines, ev.file)
          if new_lines and new_task then
            writing = true
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)

            local expected_filename = task_mod.make_filename(new_task.title)
            local current_filename = vim.fn.fnamemodify(ev.file, ":t")

            if expected_filename ~= current_filename then
              local dir = vim.fn.fnamemodify(ev.file, ":h")
              local new_path = dir .. "/" .. expected_filename
              vim.cmd("noautocmd saveas! " .. vim.fn.fnameescape(new_path))
              vim.fn.delete(ev.file)
              new_task.path = new_path
              idx.remove(ev.file)
              refresh_file_tree()
            else
              vim.cmd("noautocmd write")
            end

            idx.put(new_task)
            writing = false

            if list.is_visible() then
              list.render()
            end
            return
          end
        end

        idx.refresh_path(ev.file)
        if list.is_visible() then
          list.render()
        end
        return
      end

      -- Update updated_at, ensure type is preserved
      metadata.type = metadata.type or "task"
      metadata.updated_at = os.date("!%Y-%m-%dT%H:%M:%S") .. "Z"
      local new_lines = fm.replace_frontmatter(lines, metadata)

      -- Check if title changed (needs file rename)
      local expected_filename = task_mod.make_filename(metadata.title)
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
        local item = model.from_file(new_path)
        if item then
          idx.put(item)
        end
        refresh_file_tree()
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
  local calendar = require("cilantro.ui.calendar")

  peek.close()

  calendar.teardown_layout()

  if calendar.is_visible() then
    calendar.close()
  end

  local list_win = list.get_win()
  if list_win then
    if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
      -- Last window: can't close it, so swap in an empty buffer instead.
      vim.api.nvim_win_set_buf(list_win, vim.api.nvim_create_buf(true, false))
    else
      vim.api.nvim_win_close(list_win, false)
    end
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

    refresh_file_tree()

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

function M.create_event(input)
  local cfg = require("cilantro.config").get()
  local event_mod = require("cilantro.event")
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

    local event = event_mod.create(title, dir)
    index.put(event)

    if list.is_visible() then
      list.render()
    end

    refresh_file_tree()

    local peek = require("cilantro.ui.peek")
    peek.open(event)
  end

  if input then
    do_create(input)
  else
    vim.ui.input({ prompt = "Event (path/to/title): " }, function(val)
      do_create(val)
    end)
  end
end

function M.delete(item)
  if not item or not item.path then
    return
  end

  local cfg = require("cilantro.config").get()
  local index = require("cilantro.index")
  local list = require("cilantro.ui.list")
  local peek = require("cilantro.ui.peek")

  local kind = item.type == "event" and "event" or "task"
  local label = item.title or item.path

  if cfg.confirm_delete then
    local answer = vim.fn.confirm('Delete ' .. kind .. ' "' .. label .. '"?', "&Yes\n&No", 2)
    if answer ~= 1 then
      return
    end
  end

  -- Close the peek window if it is showing the file being deleted.
  if peek.is_open() and peek.buf and vim.api.nvim_buf_is_valid(peek.buf) then
    if vim.api.nvim_buf_get_name(peek.buf) == item.path then
      peek.close()
    end
  end

  vim.fn.delete(item.path)
  index.remove(item.path)

  if list.is_visible() then
    list.render()
  end

  refresh_file_tree()
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
