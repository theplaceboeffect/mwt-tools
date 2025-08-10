# Execute version v00.00.01 metadata
_Exported on 8/9/2025 at 21:25:38 CDT from Cursor (1.4.3)_

---

**User**

execute v00.00.01-meta.md

---

**Cursor**

Looking up the contents of the meta file and the related prompt to understand what "execute" entails before running any commands.

Reading the target prompt file to perform the review and correct language/technical terms as specified by the meta task.

I'll correct the language and technical wording in `mwt-g/prompts/v00.00.01.md` per the meta task, improving clarity and accuracy while preserving intent.

```markdown
# v00.00.01 - mwt-g

## Overview

mwt-g is a command-line tool for creating and launching URL aliases. It can be used within a project or installed globally.

## Features

- Custom URL scheme: `g:/<alias>` → `https://www.google.com/` (example)
- Settings are stored in:
  - A JSON file
  - Searched in the following order (first match wins):
    - Project-local: `./mwt-g/settings.json`
    - User-level: `~/.config/mwt-g/settings.json`

## Usage
- Adding an alias
  ```
  g y yahoo
  ```
  - `y` is the alias name
  - If the second parameter is a bare keyword (no scheme), it resolves to `https://www.<param2>.com`

- Visiting the alias
  ```
  g y
  ```
  - Opens the user's default browser to `https://www.yahoo.com/`

- Deep links
  ```
  g yn yahoo/news
  ```
  - `yn` is the alias name
  - Expands to `https://www.<param2>.com/news` → `https://www.yahoo.com/news`

- List aliases
  ```
  g +list
  ```
  - Lists all known aliases

- Register URL scheme
  ```
  g +register
  ```
  - Registers the custom `g:/` URL scheme with the OS so links like `g:/y` open via this tool

```

I reviewed `mwt-g/prompts/v00.00.01.md` per the meta task and edited for clarity and technical accuracy. Next, I'll check for any linter issues in the edited file.

- Edited `mwt-g/prompts/v00.00.01.md` to improve grammar, clarity, and technical precision:
  - Clarified overview to describe it as a CLI for URL aliases.
  - Made the custom URL scheme explicit with backticks and example.
  - Clarified settings lookup order and paths.
  - Refined usage examples, added explicit behavior for bare keywords, and improved deep link explanation.
  - Renamed list/register actions for clarity.

- Verified no linter errors in `mwt-g/prompts/v00.00.01.md`.

