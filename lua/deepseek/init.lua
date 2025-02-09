local M = {}

-- Default configuration.
M.config = {
  endpoint = "https://api.deepseek.com/chat/completions",
  model = "deepseek-chat",
  api_key = "", -- set your default API key or load from an environment variable
  max_workspace_chars = 100000, -- maximum characters to send from the workspace
}

-- Simple helper to get text from visual selection
local function get_visual_selection()
  local save_reg = vim.fn.getreg('"')
  local save_regtype = vim.fn.getregtype('"')
  vim.cmd('normal! ""y')
  local selection = vim.fn.getreg('"')
  vim.fn.setreg('"', save_reg, save_regtype)
  return selection
end

-- Function to ask DeepSeek something about the selected code
M.ask_deepseek = function(start_line, end_line)
  if not start_line or not end_line then
    vim.notify("DeepSeek: No valid line range provided.", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local code_snippet = table.concat(lines, "\n")

  if code_snippet == "" then
    vim.notify("DeepSeek: No text selected.", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({ prompt = "Ask DeepSeek about this code: " }, function(user_input)
    if not user_input or user_input == "" then
      vim.notify("DeepSeek: No question asked. Aborting.", vim.log.levels.WARN)
      return
    end

    local messages = {
      {
        role = "system",
        content = "You are a helpful code refactoring assistant. Do not include explanations or commentary, only return the refactored code."
      },
      {
        role = "user",
        content = string.format("Here is my code snippet:\n\n%s\n\nQuestion: %s", code_snippet, user_input)
      },
    }

    require("plenary.curl").post(M.config.endpoint, {
      headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. (M.config.api_key or "")
      },
      body = vim.fn.json_encode({
        model = M.config.model,
        messages = messages,
        temperature = 0.0,
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

-- Helper function to recursively read all files in the workspace,
-- ignoring folders like "node_modules" and "target" and skipping files that are too large.
local function read_workspace_files()
  local cwd = vim.fn.getcwd()
  local pattern = cwd .. "/**/*"
  local files = vim.fn.glob(pattern, false, true)
  local workspace_contents = {}
  local max_file_size = 100 * 1024  -- 100 KB per file

  for _, file in ipairs(files) do
    -- Skip files that reside in node_modules or target directories.
    if not (file:find("node_modules") or file:find("/target/")) then
      if vim.fn.filereadable(file) == 1 then
        local size = vim.fn.getfsize(file)
        if size > 0 and size <= max_file_size then
          local f = io.open(file, "r")
          if f then
            local content = f:read("*a")
            f:close()
            table.insert(workspace_contents, string.format("File: %s\n%s", file, content))
          end
        end
      end
    end
  end

  local all_content = table.concat(workspace_contents, "\n\n")
  local max_chars = M.config.max_workspace_chars or 100000
  if #all_content > max_chars then
    all_content = all_content:sub(1, max_chars) .. "\n\n[Workspace content truncated]"
  end
  return all_content
end

-- New function: ask DeepSeek something about the entire project workspace.
M.ask_deepseek_workspace = function()
  local workspace_content = read_workspace_files()
  if workspace_content == "" then
    vim.notify("DeepSeek: No workspace content found.", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({ prompt = "Ask DeepSeek about your workspace: " }, function(user_input)
    if not user_input or user_input == "" then
      vim.notify("DeepSeek: No question asked. Aborting.", vim.log.levels.WARN)
      return
    end

    local messages = {
      {
        role = "system",
        content = "You are a helpful code refactoring assistant. Do not include explanations or commentary, only return the refactored code."
      },
      {
        role = "user",
        content = string.format("Here is my project workspace content:\n\n%s\n\nQuestion: %s", workspace_content, user_input)
      },
    }

    require("plenary.curl").post(M.config.endpoint, {
      headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. (M.config.api_key or "")
      },
      body = vim.fn.json_encode({
        model = M.config.model,
        messages = messages,
        temperature = 0.0,
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
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
  })
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<CR>", { noremap = true, silent = true })
end

-- The setup function for user configuration
M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command(
    "DeepSeekAsk",
    function(opts)
      M.ask_deepseek(opts.line1, opts.line2)
    end,
    { range = true }
  )

  vim.api.nvim_create_user_command(
    "DeepSeekAskWorkspace",
    function()
      M.ask_deepseek_workspace()
    end,
    {}
  )

  -- Map Command+Shift+D (i.e. <D-S-d>) to the workspace query.
  vim.api.nvim_set_keymap("n", "<D-S-d>", "<cmd>lua require('deepseek').ask_deepseek_workspace()<CR>", { noremap = true, silent = true })
end

return M
