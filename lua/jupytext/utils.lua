local M = {}

local language_extensions = {
  python = "py",
  julia = "jl",
  r = "r",
  R = "r",
  bash = "sh",
  javascript = "js",
  typescript = "ts",
}

local language_names = {
  python3 = "python",
}

function M.get_ipynb_metadata(filename)
  local metadata = vim.json.decode(io.open(filename, "r"):read "a")["metadata"]
  local language = metadata.kernelspec.language
  if language == nil then
    language = language_names[metadata.kernelspec.name]
  end
  local extension = language_extensions[language]

  return { language = language, extension = extension }
end

function M.get_jupytext_file(filename, extension)
  local fileroot = vim.fn.fnamemodify(filename, ":r")
  return fileroot .. "." .. extension
end

function M.check_key(tbl, key)
  for tbl_key, _ in pairs(tbl) do
    if tbl_key == key then
      return true
    end
  end

  return false
end

return M
