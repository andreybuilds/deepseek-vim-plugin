local M = {}

-- Default configuration.
M.config = {
  endpoint = "https://api.deepseek.com/chat/completions",
  model = "deepseek-chat",
  api_key = "", -- set your API key here or load from an environment variable
  max_workspace_chars = 100000, -- maximum characters to send from the workspace
}

-- Simple helper to get text from visual selection.
local function get_visual_selection()
  local save_reg = vim.fn.getreg('"')
  local save_regtype = vim.fn.getregtype('"')
  vim.cmd('normal! ""y')
  local selection = vim.fn.getreg('"')
  vim.fn.setreg('"', save_reg, save_regtype)
  return selection
end

-- Function to ask DeepSeek something about the selected code (basic query).
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
            vim.notify("DeepSeek API Error: HTTP " .. tostring(res.status) .. "\n" .. (res.body or ""),
              vim.log.levels.ERROR)
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

-- Function to ask DeepSeek something about the entire workspace.
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
            vim.notify("DeepSeek API Error: HTTP " .. tostring(res.status) .. "\n" .. (res.body or ""),
              vim.log.levels.ERROR)
          end)
        end
      end,
    })
  end)
end

--------------------------------------------------------------------------------
-- New Feature: Refactor & Apply Workspace Changes
-- This function reads the entire workspace, prompts for a refactoring request,
-- sends the content and request to DeepSeek, and then immediately applies the changes.
--------------------------------------------------------------------------------
M.ask_deepseek_refactor = function()
  local workspace_content = read_workspace_files()
  if workspace_content == "" then
    vim.notify("DeepSeek: No workspace content found.", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({ prompt = "Enter your refactoring request (e.g., Change the attribute CPF to Long instead of String): " }, function(user_input)
    if not user_input or user_input == "" then
      vim.notify("DeepSeek: No refactoring request provided. Aborting.", vim.log.levels.WARN)
      return
    end

    local messages = {
      {
        role = "system",
        content = "You are a code refactoring assistant. When given a project workspace and a refactoring request, return only a valid JSON object with exactly one key, 'changes'. 'changes' should be an array of objects, each having 'file' (the relative file path) and 'new_content' (the complete new content for that file). Do not include any extra commentary or formatting."
      },
      {
        role = "user",
        content = string.format("Here is my project workspace content:\n\n%s\n\nRequest: %s", workspace_content, user_input)
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
        -- First, decode the entire API response.
        local full_response = vim.json.decode(res.body)
        -- Then extract the assistant's message content.
        local assistant_content = full_response.choices
          and full_response.choices[1]
          and full_response.choices[1].message
          and full_response.choices[1].message.content

        -- Now, try to extract just the JSON code block from the assistant's content.
        local json_str = assistant_content and assistant_content:match("```json%s*(%b{})")
        if not json_str and assistant_content then
          json_str = assistant_content:match("({.+})")
        end

        -- Optionally, you can show the raw extracted JSON in a floating window for troubleshooting.
        -- vim.schedule(function()
        --   -- *** REMOVE THE FOLLOWING LINE AFTER TROUBLESHOOTING ***
        --   M.show_in_floating_window("Raw extracted JSON:\n" .. (json_str or assistant_content or res.body))
        -- end)

        -- Guard: If json_str is nil or only whitespace, do not attempt to decode.
        if not json_str or json_str:match("^%s*$") then
          vim.schedule(function()
            vim.notify("No valid JSON object could be extracted from the assistant's response.", vim.log.levels.ERROR)
          end)
          return
        end

        local status, data = pcall(vim.json.decode, json_str)
        if status then
          local changes = data.changes
          if changes then
            -- Immediately apply the changes without asking for confirmation.
            M.apply_changes(changes)
          else
            vim.schedule(function()
              vim.notify("DeepSeek did not return any structured changes.", vim.log.levels.ERROR)
            end)
          end
        else
          vim.schedule(function()
            vim.notify("Error decoding JSON: " .. data, vim.log.levels.ERROR)
          end)
        end
      end,
    })
  end)
end

-- Function to apply changes returned by DeepSeek.
M.apply_changes = function(changes)
  -- Use vim.loop.cwd() to get the current working directory.
  local cwd = vim.loop.cwd()
  -- Wrap the entire loop in vim.schedule to run on the main event loop.
  vim.schedule(function()
    for _, change in ipairs(changes) do
      local file = change.file
      local new_content = change.new_content
      if file and new_content then
        -- If the file is absolute (starts with "/"), then use it as-is.
        local full_path
        if file:sub(1, 1) == "/" then
          full_path = file
        else
          full_path = cwd .. "/" .. file
        end
        local ok, err = pcall(function()
          vim.fn.writefile(vim.split(new_content, "\n"), full_path)
        end)
        if ok then
          vim.notify("Updated file: " .. full_path, vim.log.levels.INFO)
        else
          vim.notify("Failed to update file: " .. full_path .. "\n" .. err, vim.log.levels.ERROR)
        end
      else
        vim.notify("Invalid change entry: missing 'file' or 'new_content'.", vim.log.levels.ERROR)
      end
    end
  end)
end

--------------------------------------------------------------------------------
-- Helper: Show output in a floating window.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Setup: Create user commands and key mappings.
--------------------------------------------------------------------------------
M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("DeepSeekAsk", function(opts)
    M.ask_deepseek(opts.line1, opts.line2)
  end, { range = true })

  vim.api.nvim_create_user_command("DeepSeekAskWorkspace", function()
    M.ask_deepseek_workspace()
  end, {})

  vim.api.nvim_create_user_command("DeepSeekRefactor", function()
    M.ask_deepseek_refactor()
  end, {})

  -- Map Command+Shift+D (i.e. <D-S-d>) to the workspace query.
  vim.api.nvim_set_keymap("n", "<D-S-d>", "<cmd>lua require('deepseek').ask_deepseek_workspace()<CR>", { noremap = true, silent = true })
end

return M
