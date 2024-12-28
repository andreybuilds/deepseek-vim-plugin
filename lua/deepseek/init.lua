local M = {}

-- Set a default endpoint and model. Adjust these as needed.
M.config = {
  endpoint = "https://api.deepseek.com/chat/completions",
  model = "deepseek-chat",
  api_key = "", -- put your default here or set from environment variable
}

-- Simple helper to get text from visual selection
local function get_visual_selection()
  -- Save the current register
  local save_reg = vim.fn.getreg('"')
  local save_regtype = vim.fn.getregtype('"')

  -- Yank the visual selection into the default register
  vim.cmd('normal! ""y')

  -- Get the text from the register
  local selection = vim.fn.getreg('"')

  -- Restore previous register state
  vim.fn.setreg('"', save_reg, save_regtype)

  return selection
end

-- Function to ask DeepSeek something about the selected code
M.ask_deepseek = function(start_line, end_line)
  -- Fall back if no range is provided
  if not start_line or not end_line then
    -- user didn’t provide a range, so you might default
    -- to the old get_visual_selection() approach, or do something else.
    -- For simplicity, just error out:
    vim.notify("DeepSeek: No valid line range provided.", vim.log.levels.ERROR)
    return
  end

  -- Retrieve the lines from the current buffer
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local code_snippet = table.concat(lines, "\n")

  -- If user selected nothing (empty snippet), handle gracefully:
  if code_snippet == "" then
    vim.notify("DeepSeek: No text selected.", vim.log.levels.ERROR)
    return
  end

  -- Prompt the user for a question about those lines
  vim.ui.input({ prompt = "Ask DeepSeek about this code: " }, function(user_input)
    if not user_input or user_input == "" then
      vim.notify("DeepSeek: No question asked. Aborting.", vim.log.levels.WARN)
      return
    end

    -- Build messages to send to DeepSeek
    local messages = {
      { role = "system", content = "You are a helpful assistant." },
      {
        role = "user",
        content = string.format(
          "Here is my code snippet:\n\n%s\n\nQuestion: %s",
          code_snippet,
          user_input
        )
      },
    }

    -- Make the request
    require("plenary.curl").post(M.config.endpoint, {
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. (M.config.api_key or "")
      },
      body = vim.fn.json_encode({
        model = M.config.model,
        messages = messages,
        stream = false,
      }),
      callback = function(res)
        if res.status == 200 and res.body then
          local data = vim.json.decode(res.body)
          local deepseek_reply = data.choices
            and data.choices[1]
            and data.choices[1].message
            and data.choices[1].message.content
            or "No valid response."

          vim.schedule(function()
            M.show_in_floating_window(deepseek_reply)
          end)
        else
          vim.schedule(function()
            vim.notify(
              "DeepSeek API Error: HTTP " .. tostring(res.status) .. "\n" .. (res.body or ""),
              vim.log.levels.ERROR
            )
          end)
        end
      end,
    })
  end)
end

-- Show the DeepSeek response in a floating window
M.show_in_floating_window = function(content)
  local buf = vim.api.nvim_create_buf(false, true) -- create new scratch buffer
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.6)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win_id = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
  })

  -- Optional: set some keymaps inside the floating window to close it
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
end

-- The setup function for user configuration
M.setup = function(opts)
  -- Merge user config with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Example: create a user command to call ask_deepseek
  -- You could also map a key in your config.
vim.api.nvim_create_user_command(
  "DeepSeekAsk",
  function(opts)
    M.ask_deepseek(opts.line1, opts.line2)
  end,
  { range = true }
)
end

return M

