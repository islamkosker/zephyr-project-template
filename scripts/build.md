# Zephyr Build Script — `build.ps1`

This repository includes a PowerShell script to build Zephyr projects with a **single command**.  
This README explains the **setup**, **usage**, **parameters**, and **troubleshooting** tips for `build.ps1`.

---

## Features

- **One‑shot builds:** Prepares the `west build` call with the right arguments.
- **CMake/Ninja integration:** Automatically locates Ninja (via env var or PATH).
- **Device Tree overlay support:** Sets the `EXTRA_DTC_OVERLAY_FILE` argument for you.
- **.env support:** Reads configuration from your project and script directories.
- **Safe environment handling:** venv activation is optional; the script **always** restores the environment on success or failure.
- **Compile Commands:** Automatically generates `compile_commands.json`.

---

## Prerequisites

- **Windows** + **PowerShell 7+** (`pwsh`)  
- **Python** + venv (recommended for Zephyr)
- **Zephyr** (`west`) installed
- **Zephyr SDK** (e.g., 0.17.x)
- **CMake** and **Ninja**

> Make sure `west`, `ninja`, and the Zephyr SDK are installed and accessible. If you use a venv, the script can activate it for you.

---

## Installation / Configuration

1) **Clone** this repo (or copy it into your project).  
2) Create `scripts/.env` (example below) and adjust the paths.  
3) (Optional) Set up a Zephyr venv and install `west` there.

### Example `.env`

```ini
# Customizable environment variables for Zephyr build scripts
# Copy this file to scripts/.env and modify as needed
BOARD=nucleo_f070rb
DT_OVERLAY=boards/nucleo_f070rb.overlay
BUILD_DIR=.build
CLEAN=0
ACTIVATE=1

# Path to Zephyr installation and ninja executable (if not in PATH)
ZEPHYR_BASE=C:/Users/Admin/Developer/sdk/zephyr/zephyrproject/zephyr
ZEPHYR_SDK_INSTALL_DIR=C:/Users/Admin/Developer/sdk/zephyr/zephyr-sdk-0.17.2
NINJA_EXE=C:/Users/Admin/Developer/sdk/ninja-win/ninja.exe
```

> Note: `.env` values are loaded into the **Process** environment.

---

## Running

From the project root:

```powershell
pwsh .\scriptsuild.ps1
```

Examples you’ll often use:

```powershell
# Build while auto‑activating the (venv)
pwsh .\scriptsuild.ps1 -a

# Clean (pristine) build
pwsh .\scriptsuild.ps1 -c -a

# Use a different board and overlay
pwsh .\scriptsuild.ps1 -b nucleo_f070rb -dto boards
ucleo_f070rb.overlay -a

# Custom build directory
pwsh .\scriptsuild.ps1 -o out\zephyr-build -a

# Help
pwsh .\scriptsuild.ps1 -h
```

---

## Parameters

| Parameter | Alias(es)         | Description |
|---|---|---|
| `-Board <name>` | `-b` | Target board name (e.g., `nucleo_f070rb`). |
| `-DT_Overlay <path>` | `-dto`, `-overlay` | Device Tree overlay file. If omitted, `boards/<Board>.overlay` is assumed. |
| `-BuildDir <path>` | `-o`, `-out` | Build directory (e.g., `.build`). |
| `-Clean` | `-c`, `-pristine` | Use `west -p always` for a clean build; otherwise `auto`. |
| `-Activate` | `-a`, `-act` | Activates the venv if present; otherwise temporarily adds the west scripts folder to `PATH`. |
| `-Help` | `-h`, `-?` | Shows help and exits. |

### Value Precedence

1. **CLI parameters**
2. **Project‑root `.env`** (`<project>/.env`)
3. **`scripts/.env`**
4. **Script defaults**

> If the same key exists in both `.env` files, the **project‑root `.env`** wins because it’s loaded last.

---

## What Does It Do?

The core output of the script is this `west build` call:

```
west build -p <always|auto> -b <Board> <ProjectRoot> --   -DCMAKE_EXPORT_COMPILE_COMMANDS=ON   -DEXTRA_DTC_OVERLAY_FILE="<overlay.cmake.path>"   -G Ninja   -DCMAKE_MAKE_PROGRAM:FILEPATH="<ninja.exe>"
```

- `EXTRA_DTC_OVERLAY_FILE` is set automatically.
- `compile_commands.json` generation is **enabled**.
- Ninja is resolved via `NINJA_EXE`, then via `PATH`.

---

## Environment Activation and Safe Teardown

- With `-a/--Activate`:
  - It first looks for a project venv (`<project>/.venv`), then for a Zephyr venv (`<zephyrproject>/.venv`).
  - If no venv exists, the west scripts folder is **temporarily** appended to `PATH`.
- On **success or failure**, the script:
  - Calls `deactivate` if a venv was active.
  - Restores the original `PATH` if it was modified.

This ensures no persistent side‑effects in your Windows session.

---

## Special Behaviors

- **Overlay resolution:** If `-DT_Overlay` isn’t provided, `boards/<Board>.overlay` is assumed; if the file is missing, it errors.
- **Finding Ninja:** If `NINJA_EXE` isn’t set, the system `PATH` is searched for `ninja`.
- **ZEPHYR_BASE/ZEPHYR_SDK_INSTALL_DIR:** If not in the environment, values from `.env` or script defaults are used.
- **Exit code:** `0` on success; non‑zero on failure. On failure, a short, meaningful message is printed.

---

## Troubleshooting

**`[ERROR] west not found on PATH`**  
- Set `ACTIVATE=1` in `.env` **or** add `-a` to the command.  
- Check for a venv:  
  `Test-Path '<zephyrproject>/.venv/Scripts/Activate.ps1'`  
  If present, activate manually:  
  `. '<zephyrproject>/.venv/Scripts/Activate.ps1'` and `west --version`.

**`[ERROR] ninja.exe not found`**  
- Provide the full path in `.env` via `NINJA_EXE` **or** add Ninja to `PATH`.

**`Overlay not found`**  
- Ensure the path provided with `-dto` is correct.  
- If not provided, `boards/<Board>.overlay` is expected.

**`Unknown board` / build failed**  
- Verify that the board exists in Zephyr and that its board configuration is installed.

---

## FAQ

**Q: Do I have to use a venv?**  
A: No. Without `-a`, if `west` is on your `PATH`, the script runs directly.

**Q: Where does the build output go?**  
A: By default to `BUILD_DIR=.build`. You can change it with `-o`.

**Q: Why generate `compile_commands.json`?**  
A: It helps IDEs (e.g., VS Code) with navigation and auto‑completion.

---

## License

Add a license appropriate for your project (e.g., MIT).

---

You’re all set! Try:

```powershell
pwsh .\scriptsuild.ps1 -c -a
```
