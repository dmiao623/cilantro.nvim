local M = {}

function M.setup()
  local groups = {
    CilantroStatusTodo = { link = "Keyword" },
    CilantroStatusInProgress = { link = "WarningMsg" },
    CilantroStatusDone = { link = "DiagnosticOk" },
    CilantroStatusCancelled = { link = "NonText" },
    CilantroTitle = { link = "Normal" },
    CilantroTitleDone = { link = "DiagnosticOk" },
    CilantroDate = { link = "Number" },
    CilantroHeader = { link = "Comment" },
    CilantroEmpty = { link = "Comment" },
    CilantroEventTime = { link = "Number" },
    CilantroRecurring = { link = "Special" },
  }

  for name, def in pairs(groups) do
    def.default = true
    vim.api.nvim_set_hl(0, name, def)
  end
end

return M
