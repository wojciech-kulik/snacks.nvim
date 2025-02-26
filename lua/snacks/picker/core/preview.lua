---@class snacks.picker.Preview
---@field item? snacks.picker.Item
---@field pos? snacks.picker.Pos
---@field win snacks.win
---@field filter? snacks.picker.Filter
---@field preview snacks.picker.preview
---@field state table<string, any>
---@field main? number
---@field win_opts {main: snacks.win.Config|{}, layout: snacks.win.Config|{}, win: snacks.win.Config|{}}
---@field winhl string
---@field title? string
---@field split_layout? boolean
---@field opts? snacks.picker.previewers.Config
local M = {}
M.__index = M

---@class snacks.picker.preview.ctx
---@field picker snacks.Picker
---@field item snacks.picker.Item
---@field prev? snacks.picker.Item
---@field preview snacks.picker.Preview
---@field buf number
---@field win number

local ns = vim.api.nvim_create_namespace("snacks.picker.preview")
local ns_loc = vim.api.nvim_create_namespace("snacks.picker.preview.loc")

-- HACK: work-around for buffer-local window options mess. From the docs:
-- > When editing a buffer that has been edited before, the options from the window
-- > that was last closed are used again.  If this buffer has been edited in this
-- > window, the values from back then are used.  Otherwise the values from the
-- > last closed window where the buffer was edited last are used.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("snacks.picker.preview.wo", { clear = true }),
  callback = function(ev)
    if not vim.b[ev.buf].snacks_previewed then
      return
    end
    local reset = { "winhighlight", "cursorline", "number", "relativenumber", "signcolumn" }
    local wo = {} ---@type table<string, any>
    for _, k in ipairs(reset) do
      wo[k] = vim.api.nvim_get_option_value(k, { scope = "global" })
    end
    for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
      if not Snacks.util.is_float(win) then -- only reset non-floating windows
        Snacks.util.wo(win, wo)
        vim.b[ev.buf].snacks_previewed = nil
      end
    end
  end,
})

---@param picker snacks.Picker
function M.new(picker)
  local opts = picker.opts
  local self = setmetatable({}, M)
  self.opts = opts.previewers
  self.winhl = Snacks.picker.highlight.winhl("SnacksPickerPreview", { CursorLine = "Visual" })
  local win_opts = Snacks.win.resolve(
    {
      title_pos = "center",
      minimal = false,
      wo = {
        cursorline = false,
        colorcolumn = "",
        number = opts.win.preview.minimal ~= true,
        relativenumber = false,
        list = false,
      },
    },
    opts.win.preview,
    {
      show = false,
      enter = false,
      width = 0,
      height = 0,
      on_win = function()
        self.item = nil
        self:reset()
      end,
      wo = {
        winhighlight = self.winhl,
      },
      scratch_ft = "snacks_picker_preview",
    }
  )
  self.win_opts = {
    main = {
      relative = "win",
      backdrop = false,
    },
    layout = {
      backdrop = win_opts.backdrop == true,
    },
  }
  self.win = Snacks.win(win_opts)
  self:update(picker)
  self.state = {}

  self.win:on("WinClosed", function()
    self:clear(self.win.buf)
  end, { win = true })

  self.preview = Snacks.picker.config.preview(opts)
  return self
end

function M:close()
  self.win:destroy()
  self.item = nil
  self.win_opts = { main = {}, layout = {}, win = {} }
end

---@param picker snacks.Picker
function M:update(picker)
  local main = picker.resolved_layout.preview == "main" and picker.main or nil
  self.main = main
  self.win_opts.main.win = main
  self.win.opts = vim.tbl_deep_extend("force", self.win.opts, main and self.win_opts.main or self.win_opts.layout)
  if not main then
    self.win.opts.relative = nil
    self.win.opts.win = nil
    self.win.layout = nil
  end
  local winhl = self.winhl
  if main then
    winhl = (vim.wo[main].winhighlight .. ",Normal:Normal," .. "CursorLine:SnacksPickerPreviewCursorLine"):gsub(
      "^,",
      ""
    )
  end
  self.win.opts.wo.winhighlight = winhl
end

--- refresh the preview after layout change
---@param picker snacks.Picker
function M:refresh(picker)
  self.item = nil
  self:reset()
  if self.main then
    self.win:update()
  end
  vim.schedule(function()
    picker:show_preview()
  end)
end

---@param picker snacks.Picker
---@param opts? {force?: boolean}
function M:show(picker, opts)
  if not self.win:valid() then
    return
  end
  opts = opts or {}
  self.split_layout = not picker.layout.root:is_floating()
  local item, prev = picker:current({ resolve = false }), self.item
  if not opts.force and self.item == item and self.pos == (item and item.pos or nil) then
    return
  end
  Snacks.picker.util.resolve(item)
  self.item = item
  self.filter = picker:filter()
  self.pos = item and item.pos or nil
  if item then
    local buf = self.win.buf
    local ok, err = pcall(
      self.preview,
      setmetatable({
        preview = self,
        item = item,
        prev = prev,
        picker = picker,
      }, {
        __index = function(_, k)
          if k == "buf" then
            return self.win.buf
          elseif k == "win" then
            return self.win.win
          end
        end,
      })
    )
    if not ok then
      self:notify(err, "error")
    end
    if self.win.buf ~= buf then
      self:clear(buf)
    end
  else
    self:reset()
  end
end

---@param title? string
function M:set_title(title)
  self.title = title
end

---@param wo vim.wo|{}
function M:wo(wo)
  if self.win:win_valid() then
    Snacks.util.wo(self.win.win, wo)
  end
end

---@param buf? number
function M:clear(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, ns_loc, 0, -1)
end

---@param buf number
function M:set_buf(buf)
  vim.b[buf].snacks_previewed = true
  self.win:set_buf(buf)
end

function M:reset()
  if not self.win:valid() then
    return
  end
  if self.win.scratch_buf and vim.api.nvim_buf_is_valid(self.win.scratch_buf) then
    self.win:set_buf(self.win.scratch_buf)
  else
    self.win:scratch()
  end
  vim.api.nvim_buf_clear_namespace(self.win.buf, -1, 0, -1)
  self:set_title()
  vim.treesitter.stop(self.win.buf)
  vim.bo[self.win.buf].modifiable = true
  self:set_lines({})
  self:clear(self.win.buf)
  local ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.bo[self.win.buf].filetype = "snacks_picker_preview"
  vim.bo[self.win.buf].syntax = ""
  vim.bo[self.win.buf].buftype = "nofile"
  self:wo({ cursorline = false })
  self:wo(self.win.opts.wo)
  vim.o.eventignore = ei
end

function M:minimal()
  self:wo({ number = false, relativenumber = false, signcolumn = "no" })
end

-- create a new scratch buffer
function M:scratch()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.bo[buf].filetype = "snacks_picker_preview"
  vim.o.eventignore = ei
  self.win:set_buf(buf)
  self.win:map()
  self:minimal()
  return buf
end

--- highlight the buffer
---@param opts? {file?:string, buf?:number, ft?:string, lang?:string}
function M:highlight(opts)
  opts = opts or {}
  local ft = opts.ft
  if not ft and opts.buf then
    local modeline = Snacks.picker.util.modeline(opts.buf)
    ft = modeline and modeline.ft
  end
  if not ft and (opts.file or opts.buf) then
    ft = vim.filetype.match({
      buf = opts.buf or self.win.buf,
      filename = opts.file,
    })
  end
  self:check_big()
  local lang = Snacks.util.get_lang(opts.lang or ft)
  if not (lang and pcall(vim.treesitter.start, self.win.buf, lang)) and ft then
    vim.bo[self.win.buf].syntax = ft
  end
end

-- show the item location
function M:loc()
  vim.api.nvim_buf_clear_namespace(self.win.buf, ns_loc, 0, -1)
  if not self.item then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(self.win.buf)
  Snacks.picker.util.resolve_loc(self.item, self.win.buf)

  local function show(pos)
    local center = true
    if self.split_layout and self.main and self.item and self.item.buf then
      local main_buf = vim.api.nvim_win_get_buf(self.main)
      if main_buf == self.item.buf then
        center = false
        local view = vim.api.nvim_win_call(self.main, vim.fn.winsaveview)
        vim.api.nvim_win_call(self.win.win, function()
          vim.fn.winrestview(view)
        end)
      end
    end
    vim.api.nvim_win_set_cursor(self.win.win, pos)
    vim.api.nvim_win_call(self.win.win, function()
      if center then
        vim.cmd("norm! zzze")
      end
      self:wo({ cursorline = true })
    end)
  end

  if self.item.pos and self.item.pos[1] > 0 and self.item.pos[1] <= line_count then
    show(self.item.pos)
    if self.item.end_pos then
      vim.api.nvim_buf_set_extmark(self.win.buf, ns_loc, self.item.pos[1] - 1, self.item.pos[2], {
        end_row = self.item.end_pos[1] - 1,
        end_col = self.item.end_pos[2],
        hl_group = "SnacksPickerSearch",
      })
    elseif self.filter and vim.trim(self.filter.search) ~= "" then
      local ok, re = pcall(vim.regex, vim.trim(self.filter.search))
      if ok and re then
        local start = self.item.pos[2]
        local from, to ---@type number?, number?
        pcall(function()
          from, to = re:match_line(self.win.buf, self.item.pos[1] - 1, start)
        end)
        if from and to then
          show({ self.item.pos[1], start + to }) -- make sure the to column is visible
          vim.api.nvim_buf_set_extmark(self.win.buf, ns_loc, self.item.pos[1] - 1, start + from, {
            end_col = start + to,
            hl_group = "SnacksPickerSearch",
          })
        end
      end
    end
  elseif self.item.search then
    vim.api.nvim_win_call(self.win.win, function()
      vim.cmd("keepjumps norm! gg")
      if pcall(vim.cmd, self.item.search) then
        vim.cmd("norm! zz")
        self:wo({ cursorline = true })
      end
    end)
  end
end

function M:check_big()
  local big = self:is_big()
  vim.b[self.win.buf].snacks_scroll = not big
end

function M:is_big()
  local lines = vim.api.nvim_buf_line_count(self.win.buf)
  if lines > 2000 then
    return true
  end
  local path = self.item and self.item.file and Snacks.picker.util.path(self.item)
  if path and vim.fn.getfsize(path) > 1.5 * 1024 * 1024 then
    return true
  end
  return false
end

---@param lines string[]
function M:set_lines(lines)
  lines = vim.split(table.concat(lines, "\n"), "\n", { plain = true })
  vim.bo[self.win.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.win.buf, 0, -1, false, lines)
  vim.bo[self.win.buf].modifiable = false
end

---@param msg string
---@param level? "info" | "warn" | "error"
---@param opts? {item?:boolean}
function M:notify(msg, level, opts)
  if not self.win:buf_valid() then
    Snacks.notify(msg, { level = level })
    return
  end
  self:reset()
  level = level or "info"
  local lines = vim.split(level .. ": " .. msg, "\n", { plain = true })
  local msg_len = #lines
  if not (opts and opts.item == false) then
    lines[#lines + 1] = ""
    vim.list_extend(lines, vim.split(vim.inspect(self.item), "\n", { plain = true }))
  end
  self:set_lines(lines)
  vim.api.nvim_buf_set_extmark(self.win.buf, ns, 0, 0, {
    hl_group = "Diagnostic" .. level:sub(1, 1):upper() .. level:sub(2),
    end_row = msg_len,
  })
  self:highlight({ lang = "lua" })
end

return M
