# fish-async-prompt

Make your prompt asynchronous in Fish shell.

## Description

![Demo Video](demo.gif)

It runs `fish_prompt` and `fish_right_prompt` functions as another process and then, update the prompt asyncronously.

## Installation

Just say below!

```
$ fisher acomagu/fish-async-prompt
```

And then enjoy your creative time.

If your prompt don't work correctly, try changeing the configuration.

## Configuration

### Variable: `async_prompt_inherit_variables`

Define variables inherited to prompt functions. Set `all` to pass all global variables.

**Default:** `status`

## Author

- [acomagu](https://github.com/acomagu)
