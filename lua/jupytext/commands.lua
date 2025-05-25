local M = {}

function M.run_jupytext(args, callback)
  local cmd = { "jupytext" }

  for key, value in pairs(args) do
    if type(key) == "number" then
      table.insert(cmd, value)
    else
      table.insert(cmd, key)
      if value ~= "" then
        table.insert(cmd, value)
      end
    end
  end

  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data, _)
      if data then
        vim.list_extend(stdout_data, data)
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        vim.list_extend(stderr_data, data)
      end
    end,
    on_exit = function(_, exit_code, _)
      if exit_code ~= 0 then
        local error_msg = table.concat(stderr_data, "\n")
        vim.notify("jupytext command failed: " .. error_msg, vim.log.levels.ERROR, { title = "Jupytext" })
      end
      if callback then
        callback(exit_code == 0)
      end
    end,
  })
end

return M
