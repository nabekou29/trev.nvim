local M = {}

--- Get the runtime directory for trev sockets.
--- Resolution order: XDG_RUNTIME_DIR -> TMPDIR -> /tmp
--- @return string
function M.get_runtime_dir()
  local runtime_dir = vim.env.XDG_RUNTIME_DIR
  if runtime_dir and runtime_dir ~= "" then
    return runtime_dir .. "/trev"
  end
  local tmpdir = vim.fn.getenv("TMPDIR")
  if not tmpdir or tmpdir == vim.NIL or tmpdir == "" then
    tmpdir = "/tmp"
  end
  return tmpdir .. "/trev"
end

--- Compute workspace key matching trev's Rust implementation.
--- Format: <dir_name>-<sha256_hash_first_8_chars>
--- @param path string absolute workspace path
--- @return string
function M.compute_workspace_key(path)
  local dir_name = vim.fn.fnamemodify(path, ":t")
  if dir_name == "" then
    dir_name = "trev"
  end
  local canonical = vim.fn.resolve(path)
  local hash = vim.fn.sha256(canonical):sub(1, 8)
  return dir_name .. "-" .. hash
end

--- Find socket for a given PID with retry logic.
--- Retries at 50ms intervals for up to 500ms.
--- @param pid number process ID
--- @param callback fun(socket_path: string|nil)
function M.find_for_pid(pid, callback)
  local runtime_dir = M.get_runtime_dir()
  local pattern = runtime_dir .. "/*-" .. pid .. ".sock"
  local max_attempts = 10
  local interval_ms = 50
  local attempt = 0

  local function try()
    attempt = attempt + 1
    local matches = vim.fn.glob(pattern, false, true)
    if #matches > 0 then
      callback(matches[1])
      return
    end
    if attempt >= max_attempts then
      callback(nil)
      return
    end
    vim.defer_fn(try, interval_ms)
  end

  -- Initial delay to give trev time to start
  vim.defer_fn(try, 300)
end

return M
