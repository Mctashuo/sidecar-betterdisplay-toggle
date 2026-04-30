use framework "Foundation"

-- ==========================================
-- 自动化连接 iPad (Sidecar) 增强脚本 (命令行优先 Toggle 版)
-- ==========================================

property MAX_SEARCH_DEPTH : 10
property ERROR_INFO : yes

global SOUND_START, SOUND_SUCCESS, SOUND_FAILURE
global PREFERRED_DEVICE_NAMES

set SOUND_START to "/System/Library/Sounds/Pop.aiff"
set SOUND_SUCCESS to "/System/Library/Sounds/Blow.aiff"
set SOUND_FAILURE to "/System/Library/Sounds/Hero.aiff"
set PREFERRED_DEVICE_NAMES to {"Example iPad", "Example Tablet"}

set openedSettings to false

try
	my playSound(SOUND_START)
	
	set cliResult to my togglePreferredDeviceByCommandLine()
	if (item 1 of cliResult) is true then
		my playSound(SOUND_SUCCESS)
	else
		my runCommand("/usr/bin/open", {"x-apple.systempreferences:com.apple.preference.displays"})
		set openedSettings to true
		
		if not my waitForApp("System Settings", 5) then error "无法打开系统设置"
		if not my waitForWindow("System Settings", 5) then error "系统设置窗口未就绪"
		
		tell application "System Events"
			tell process "System Settings"
				set targetWindow to window 1
				set menuBtn to my findAddButton(targetWindow, 0, true)
				if menuBtn is missing value then
					set menuBtn to my findAddButton(targetWindow, 0, false)
				end if
				
				if menuBtn is not missing value then
					click menuBtn
					delay 0.5
					
					set found to my selectDeviceFromMenu(menuBtn)
					if not found then
						error "命令行切换失败，且系统设置中未发现优先设备"
					else
						my playSound(SOUND_SUCCESS)
					end if
				else
					error "找不到添加按钮"
				end if
			end tell
		end tell
	end if
	
on error errMsg
	if ERROR_INFO is yes then
		my runCommand("/usr/bin/say", {errMsg})
	end if
	my playSound(SOUND_FAILURE)
end try

-- 收尾：退出
delay 0.5
if openedSettings is true then
	tell application "System Settings" to quit
end if

-- ==========================================
-- 工具函数库
-- ==========================================

on playSound(path)
	my launchCommand("/usr/bin/afplay", {path})
end playSound

on waitForApp(appName, maxSeconds)
	repeat maxSeconds * 10 times
		tell application "System Events"
			if exists (process appName) then return true
		end tell
		delay 0.1
	end repeat
	return false
end waitForApp

on waitForWindow(appName, maxSeconds)
	repeat maxSeconds * 10 times
		tell application "System Events"
			if exists (process appName) then
				tell process appName
					if (count of windows) > 0 then return true
				end tell
			end if
		end tell
		delay 0.1
	end repeat
	return false
end waitForWindow

on sidecarLauncherPath()
	return ((current application's NSHomeDirectory()) as text) & "/.local/bin/SidecarLauncher"
end sidecarLauncherPath

on runCommand(executablePath, argumentList)
	set task to current application's NSTask's alloc()'s init()
	task's setLaunchPath:(executablePath)
	task's setArguments:(argumentList)
	
	set outputPipe to current application's NSPipe's pipe()
	set errorPipe to current application's NSPipe's pipe()
	task's setStandardOutput:(outputPipe)
	task's setStandardError:(errorPipe)
	
	try
		task's |launch|()
		task's waitUntilExit()
	on error errMsg
		return {false, errMsg}
	end try
	
	set outputData to outputPipe's fileHandleForReading()'s readDataToEndOfFile()
	set errorData to errorPipe's fileHandleForReading()'s readDataToEndOfFile()
	set outputText to my textFromData(outputData)
	set errorText to my textFromData(errorData)
	set exitCode to (task's terminationStatus()) as integer
	
	if exitCode is 0 then
		return {true, outputText}
	end if
	return {false, outputText & errorText}
end runCommand

on launchCommand(executablePath, argumentList)
	set task to current application's NSTask's alloc()'s init()
	task's setLaunchPath:(executablePath)
	task's setArguments:(argumentList)
	try
		task's |launch|()
	end try
end launchCommand

on textFromData(theData)
	set theText to current application's NSString's alloc()'s initWithData:theData encoding:(current application's NSUTF8StringEncoding)
	if theText is missing value then return ""
	return theText as text
end textFromData

on togglePreferredDeviceByCommandLine()
	set launcherPath to my sidecarLauncherPath()
	
	set executableCheck to my runCommand("/bin/test", {"-x", launcherPath})
	if (item 1 of executableCheck) is false then
		return {false, "未找到可执行 SidecarLauncher: " & launcherPath}
	end if
	
	if my isSidecarDisplayConnected() then
		set lastError to ""
		repeat with preferredDevice in PREFERRED_DEVICE_NAMES
			set preferredName to preferredDevice as text
			set disconnectResult to my runCommand(launcherPath, {"disconnect", preferredName})
			if (item 1 of disconnectResult) is true then
				return {true, "已通过命令行断开: " & preferredName}
			end if
			set lastError to preferredName & ": " & (item 2 of disconnectResult)
		end repeat
		
		if lastError is not "" then
			return {false, "已检测到 Sidecar Display，但断开失败: " & lastError}
		end if
	end if
	
	set deviceResult to my runCommand(launcherPath, {"devices", "list"})
	if (item 1 of deviceResult) is false then
		return {false, "SidecarLauncher devices list 失败: " & (item 2 of deviceResult)}
	end if
	set deviceOutput to item 2 of deviceResult
	
	set reachableDevices to paragraphs of deviceOutput
	set lastError to ""
	repeat with preferredDevice in PREFERRED_DEVICE_NAMES
		set preferredName to preferredDevice as text
		repeat with reachableDevice in reachableDevices
			set reachableName to reachableDevice as text
			if reachableName is preferredName then
				set connectResult to my runCommand(launcherPath, {"connect", preferredName})
				if (item 1 of connectResult) is true then
					return {true, "已通过命令行连接: " & preferredName}
				end if
				set lastError to preferredName & ": " & (item 2 of connectResult)
			end if
		end repeat
	end repeat
	
	if lastError is not "" then
		return {false, "命令行切换失败: " & lastError}
	end if
	return {false, "命令行未发现优先设备"}
end togglePreferredDeviceByCommandLine

on isSidecarDisplayConnected()
	set statusScript to "/usr/sbin/system_profiler SPDisplaysDataType | /usr/bin/awk '/^        Sidecar Display:/{inside=1; next} /^        [^ ].*:/{inside=0} inside && /Virtual Device: Yes/{found=1} END{exit !found}'"
	set statusResult to my runCommand("/bin/sh", {"-c", statusScript})
	return ((item 1 of statusResult) is true)
end isSidecarDisplayConnected

on findAddButton(theElement, currentDepth, strictMode)
	tell application "System Events"
		if currentDepth > MAX_SEARCH_DEPTH then return missing value
		try
			set elClass to class of theElement
			set isMenuLikeButton to false
			if (elClass is menu button) or (elClass is pop up button) then
				set isMenuLikeButton to true
			end if
			
			if elClass is button then
				if exists menu 1 of theElement then set isMenuLikeButton to true
			end if
			
			if isMenuLikeButton then
				if strictMode is false then return theElement
				if my isLikelyAddDisplayButton(theElement) then return theElement
			end if
			
			set children to every UI element of theElement
			repeat with child in children
				set resultBtn to my findAddButton(child, currentDepth + 1, strictMode)
				if resultBtn is not missing value then return resultBtn
			end repeat
		end try
	end tell
	return missing value
end findAddButton

on isLikelyAddDisplayButton(theElement)
	tell application "System Events"
		set labelText to ""
		try
			set labelText to labelText & " " & ((name of theElement) as text)
		end try
		try
			set labelText to labelText & " " & ((description of theElement) as text)
		end try
		try
			set labelText to labelText & " " & ((help of theElement) as text)
		end try
	end tell
	
	return ((labelText contains "Add Display") or (labelText contains "Add") or (labelText contains "添加") or (labelText contains "加入") or (labelText contains "+"))
end isLikelyAddDisplayButton

on selectDeviceFromMenu(btn)
	tell application "System Events"
		try
			set menuItems to name of menu items of menu 1 of btn
			repeat with preferredDevice in PREFERRED_DEVICE_NAMES
				set preferredName to preferredDevice as text
				repeat with i from 1 to (count of menuItems)
					if (item i of menuItems) contains preferredName then
						click menu item i of menu 1 of btn
						return true
					end if
				end repeat
			end repeat
		end try
	end tell
	return false
end selectDeviceFromMenu
