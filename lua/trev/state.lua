local M = {}

--- @type trev.State
local state = {
  handle = nil,
  mode = nil,
  dir = nil,
  prev_win = nil,
  pipe = nil,
  socket_path = nil,
  read_buf = "",
  request_id = 1,
  pending = {},
  override_path = nil,
  augroup = nil,
}

--- @return trev.State
function M.get()
  return state
end

function M.reset()
  state.handle = nil
  state.mode = nil
  state.dir = nil
  state.prev_win = nil
  state.pipe = nil
  state.socket_path = nil
  state.read_buf = ""
  state.request_id = 1
  state.pending = {}
  state.override_path = nil
  state.augroup = nil
end

return M
