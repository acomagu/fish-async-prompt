# fish-async-prompt

Make your prompt asynchronous in [Fish](https://fishshell.com/).

## Description

![Demo Video](demo.png)

We run your `fish_prompt` and `fish_right_prompt` functions as a separate process to update your prompt asynchronously.

## Installation

With [Fisher](https://github.com/jorgebucaran/fisher):

```
$ fisher install acomagu/fish-async-prompt
```

## Configuration

### `async_prompt_inherit_variables`

Define variables inherited to prompt functions. Set `all` to pass all global variables.

**Default:** `status SHLVL CMD_DURATION`

### `async_prompt_functions`

Define functions replaced to run asynchronously. Usually one or both of `fish_prompt` and `fish_right_prompt`.

Other functions can be specified, but they must be called from `fish_prompt` or `fish_right_prompt` and function arguments can't be passed to it.

**Default:** `fish_prompt fish_right_prompt`

## Author

- [acomagu](https://github.com/acomagu)

## License

[MIT](LICENSE.md)
