# Homebridge macOS Installer

This project builds the Homebridge macOS installer.

The project aims to deploy Homebridge and the Homebridge UI in a secure and stable way. It comes bundled with it's own Node.js runtime and runs Homebridge in an isolated environment as a service user with no sudo / admin priviledges.

:warning: This project is in the early stages of development and is not yet ready for production use. You should not use or install this package.

# Install Homebridge

Download the .pkg and run the installer. 

The installer is currently not signed, go to System Preferences -> Security & Privacy -> General -> Open Anyway to install.

![image](https://user-images.githubusercontent.com/3979615/166683650-11554c3a-097f-435b-a100-7f2e1297799c.png)

# Uninstall

Applications Folder -> Homebridge -> Uninstall Homebridge

## License

Copyright (C) 2022 oznu

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the [GNU General Public License](./LICENSE) for more details.
