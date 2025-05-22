local commands = require "jupytext.commands"
local utils = require "jupytext.utils"

local M = {}

M.config = {
  style = "hydrogen",
  output_extension = "auto",
  force_ft = nil,
  custom_language_formatting = {},
}

M.should_delete = {}

local function write_to_ipynb(event, output_extension)
  local ipynb_filename = event.match
  local jupytext_filename = utils.get_jupytext_file(ipynb_filename, output_extension)
  jupytext_filename = vim.fn.resolve(vim.fn.expand(jupytext_filename))

  vim.cmd.write({ jupytext_filename, bang = true })
  local buf = vim.api.nvim_get_current_buf()

  commands.run_jupytext(jupytext_filename, {
    ["--update"] = "",
    ["--to"] = "ipynb",
    ["--output"] = ipynb_filename,
  }, function(ok)
    if ok then
      vim.schedule(function()
        vim.api.nvim_set_option_value("modified", false, { buf = buf })

        local post_write = "BufWritePost"
        if event.event == "FileWriteCmd" then
          post_write = "FileWritePost"
        end
        vim.api.nvim_exec_autocmds(post_write, { pattern = ipynb_filename })
      end)
    end
  end)
end

local function style_and_extension(metadata)
  local to_extension_and_style
  local output_extension

  local custom_formatting = nil
  if utils.check_key(M.config.custom_language_formatting, metadata.language) then
    custom_formatting = M.config.custom_language_formatting[metadata.language]
  end

  if custom_formatting then
    output_extension = custom_formatting.extension
    to_extension_and_style = output_extension .. ":" .. custom_formatting.style
  else
    if M.config.output_extension == "auto" then
      output_extension = metadata.extension
    else
      output_extension = M.config.output_extension
    end
    to_extension_and_style = M.config.output_extension .. ":" .. M.config.style
  end

  return custom_formatting, output_extension, to_extension_and_style
end

local function cleanup(ipynb_filename, delete)
  local metadata = utils.get_ipynb_metadata(ipynb_filename)

  local _, output_extension, _ = style_and_extension(metadata)

  local jupytext_filename = utils.get_jupytext_file(ipynb_filename, output_extension)
  if delete then
    vim.fn.delete(vim.fn.resolve(vim.fn.expand(jupytext_filename)))
  end
end

local function read_from_ipynb(ipynb_filename)
  local metadata = utils.get_ipynb_metadata(ipynb_filename)
  ipynb_filename = vim.fn.resolve(vim.fn.expand(ipynb_filename))

  -- Decide output extension and style
  local custom_formatting, output_extension, to_extension_and_style = style_and_extension(metadata)

  local jupytext_filename = utils.get_jupytext_file(ipynb_filename, output_extension)
  local jupytext_file_exists = vim.fn.filereadable(jupytext_filename) == 1

  if not vim.fn.filereadable(ipynb_filename) then
    error("File does not exist: " .. ipynb_filename)
    return
  end

  local function load_buffer()
    -- This is when the magic happens and we read the new file into the buffer
    if vim.fn.filereadable(jupytext_filename) then
      local jupytext_content = vim.fn.readfile(jupytext_filename)

      -- Need to add an extra line so that the undo dance that comes later on
      -- doesn't delete the first line of the actual input
      table.insert(jupytext_content, 1, "")

      -- Replace the buffer content with the jupytext content
      vim.api.nvim_buf_set_lines(0, 0, -1, false, jupytext_content)
    else
      error "Couldn't find jupytext file."
      return
    end

    -- If jupytext version already existed then don't delete otherwise consider
    -- it to be sort of a temp file.
    M.should_delete[ipynb_filename] = not jupytext_file_exists
    vim.api.nvim_create_autocmd("BufUnload", {
      pattern = "<buffer>",
      group = "jupytext-nvim",
      callback = function(ev)
        cleanup(ev.match, M.should_delete[ev.match])
        M.should_delete[ev.match] = nil
      end,
    })

    vim.api.nvim_create_autocmd({ "BufWriteCmd", "FileWriteCmd" }, {
      pattern = "<buffer>",
      group = "jupytext-nvim",
      callback = function(ev)
        write_to_ipynb(ev, output_extension)
      end,
    })

    local ft = M.config.force_ft

    if custom_formatting ~= nil then
      if custom_formatting.force_ft then
        if custom_formatting.style == "quarto" then
          ft = "quarto"
        else
          -- just let the user set whatever ft they want
          ft = custom_formatting.force_ft
        end
      end
    end

    if not ft then
      ft = metadata.language
    end

    -- In order to make :undo a no-op immediately after the buffer is read, we
    -- need to do this dance with 'undolevels'.  Actually discarding the undo
    -- history requires performing a change after setting 'undolevels' to -1 and,
    -- luckily, we have one we need to do (delete the extra line from the :r
    -- command)
    -- (Comment straight from goerz/jupytext.vim)
    local levels = vim.o.undolevels
    vim.o.undolevels = -1
    vim.api.nvim_command "silent 1delete"
    vim.o.undolevels = levels

    vim.api.nvim_command("setlocal nomod fenc=utf-8 ft=" .. ft)

    -- First time we enter the buffer redraw. Don't know why but jupytext.vim was
    -- doing it. Apply Chesterton's fence principle.
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "<buffer>",
      group = "jupytext-nvim",
      once = true,
      command = "redraw",
    })
  end

  if jupytext_file_exists then
    -- if ipynb_file is newer than jupytext_file, prompt to update
    local ipynb_mtime = vim.fn.getftime(ipynb_filename)
    local jupytext_mtime = vim.fn.getftime(jupytext_filename)
    if ipynb_mtime > jupytext_mtime then
      local msg = string.format(
        "Notebook was modified since last jupytext conversion.\nRefresh `%s` from `%s`?",
        vim.fn.fnamemodify(jupytext_filename, ":t"),
        vim.fn.fnamemodify(ipynb_filename, ":t")
      )
      local choice = vim.fn.confirm(msg, "&Refresh\n&No", 2)
      if choice == 1 then
        commands.run_jupytext(ipynb_filename, {
          ["--to"] = to_extension_and_style,
          ["--output"] = jupytext_filename,
        }, function(ok)
          if ok then
            vim.schedule(load_buffer)
          end
        end)
      else
        load_buffer()
      end
    else
      load_buffer()
    end
  else
    commands.run_jupytext(ipynb_filename, {
      ["--to"] = to_extension_and_style,
      ["--output"] = jupytext_filename,
    }, function(ok)
      if ok then
        vim.schedule(load_buffer)
      end
    end)
  end
end

function M.save_jupytext()
  local buf = vim.api.nvim_get_current_buf()
  local filename = vim.api.nvim_buf_get_name(buf)
  if vim.fn.expand "%:e" == "ipynb" then
    if M.should_delete[filename] then
      M.should_delete[filename] = false
    end
    local metadata = utils.get_ipynb_metadata(filename)
    local _, output_extension, _ = style_and_extension(metadata)
    local jupytext_filename = utils.get_jupytext_file(filename, output_extension)
    jupytext_filename = vim.fn.fnamemodify(jupytext_filename, ":t")
    vim.notify("File saved: " .. jupytext_filename, vim.log.levels.INFO, { title = "Jupytext" })
  else
    vim.notify("Not a ipynb file", vim.log.levels.WARN, { title = "Jupytext" })
  end
end

function M.setup(config)
  vim.validate("config", config, { "table" }, true)
  M.config = vim.tbl_deep_extend("force", M.config, config or {})

  vim.validate("style", M.config.style, { "string" })
  vim.validate("output_extension", M.config.output_extension, { "string" })

  vim.api.nvim_create_augroup("jupytext-nvim", { clear = true })
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = { "*.ipynb" },
    group = "jupytext-nvim",
    callback = function(ev)
      read_from_ipynb(ev.match)
    end,
  })

  vim.api.nvim_create_user_command("JupytextSave", M.save_jupytext, { desc = "Save Jupytext file" })

  -- If we are using LazyVim make sure to run the LazyFile event so that the LSP
  -- and other important plugins get going
  if pcall(require, "lazy") then
    vim.api.nvim_exec_autocmds("User", { pattern = "LazyFile", modeline = false })
  end
end

return M
