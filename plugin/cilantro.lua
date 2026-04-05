if vim.g.loaded_cilantro then
  return
end
vim.g.loaded_cilantro = true

vim.api.nvim_create_user_command("Cilantro", function()
  require("cilantro").open()
end, { desc = "Open cilantro task list" })

vim.api.nvim_create_user_command("CilantroCreate", function(cmd)
  require("cilantro").create_task(cmd.args ~= "" and cmd.args or nil)
end, { nargs = "?", desc = "Create a new task" })

vim.api.nvim_create_user_command("CilantroRefresh", function()
  require("cilantro").refresh()
end, { desc = "Refresh cilantro index" })

vim.api.nvim_create_user_command("CilantroClose", function()
  require("cilantro").close()
end, { desc = "Close cilantro UI" })

vim.api.nvim_create_user_command("CilantroToggle", function()
  require("cilantro").toggle()
end, { desc = "Toggle cilantro UI" })
