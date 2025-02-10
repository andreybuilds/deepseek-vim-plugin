# DeepSeek Neovim Plugin

A Neovim plugin that integrates with the DeepSeek API to provide code refactoring and assistance directly within your editor.

## Features

- **Code Snippet Query**: Ask DeepSeek about specific code snippets directly from your buffer.
- **Workspace Query**: Query DeepSeek about your entire project workspace, including multiple files.
- **Floating Window**: Responses from DeepSeek are displayed in a floating window for easy viewing.
- **Refactoring**: Automatically refactor your code based on DeepSeek's suggestions.

## Installation

1. Ensure you have [Neovim](https://neovim.io/) installed.
2. Install the plugin using your preferred plugin manager. For example, with [packer.nvim](https://github.com/wbthomason/packer.nvim):

   ```lua
   use {
     'your-username/deepseek.nvim',
     config = function()
       require('deepseek').setup({
         api_key = "your-api-key-here",  -- Set your DeepSeek API key
       })
     end
   }
   ```

3. Set your DeepSeek API key in the configuration.

## Usage

### Code Snippet Query

1. Select a range of lines in your buffer.
2. Run the command `:DeepSeekAsk` or map it to a keybinding.
3. Enter your question when prompted.

**Example**:
```lua
-- Select the following code and run :DeepSeekAsk
local function add(a, b)
  return a + b
end
```
Ask: "How can I make this function more robust?"

### Workspace Query

1. Run the command `:DeepSeekAskWorkspace` or use the default keybinding `<D-S-d>` (Command+Shift+D on macOS).
2. Enter your question when prompted.

**Example**:
Ask: "How can I improve the structure of my project?"

### Refactoring

1. Run the command `:DeepSeekRefactor`.
2. Enter your refactoring request when prompted.

**Example**:
Request: "Refactor the code to use async/await instead of callbacks."

### Keybindings

- `<D-S-d>`: Open a DeepSeek query for the entire workspace (macOS only).
- `q`: Close the floating window.

## Configuration

You can customize the plugin by passing options to the `setup` function:

```lua
require('deepseek').setup({
  endpoint = "https://api.deepseek.com/chat/completions",  -- DeepSeek API endpoint
  model = "deepseek-chat",  -- Model to use
  api_key = "your-api-key-here",  -- Your DeepSeek API key
  max_workspace_chars = 100000,  -- Maximum characters to send from the workspace
})
```

## Dependencies

- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim): Required for HTTP requests.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
