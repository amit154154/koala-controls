-- Fixed destinations only; browser URLs are passed as separate arguments, never shell text.
on matchesHost(theURL, hostName)
    repeat with origin in {"https://" & hostName, "http://" & hostName}
        set base to contents of origin
        if theURL is base or theURL starts with (base & "/") or theURL starts with (base & "?") or theURL starts with (base & "#") then return true
    end repeat
    return false
end matchesHost

on matchesNBA(theURL)
    repeat with prefixURL in {"https://www.nba.com/games", "https://nba.com/games", "https://www.nba.com/game/", "https://nba.com/game/"}
        if theURL starts with (contents of prefixURL) then return true
    end repeat
    return false
end matchesNBA

on mediaService(theURL)
    if my matchesHost(theURL, "music.youtube.com") then return "youtubeMusic"
    if my matchesHost(theURL, "open.spotify.com") then return "spotify"
    if my matchesHost(theURL, "www.youtube.com") or my matchesHost(theURL, "youtube.com") then return "youtube"
    if my matchesHost(theURL, "gasdigital.com") or my matchesHost(theURL, "www.gasdigital.com") then return "gdn"
    if my matchesHost(theURL, "netflix.com") or my matchesHost(theURL, "www.netflix.com") then return "netflix"
    repeat with hostName in {"www.hbomax.com", "hbomax.com", "play.hbomax.com", "www.max.com", "max.com", "play.max.com"}
        if my matchesHost(theURL, contents of hostName) then return "hbo"
    end repeat
    if my matchesHost(theURL, "tv.apple.com") then return "appleTV"
    if my matchesNBA(theURL) then return "nba"
    return ""
end mediaService

on cleanTitle(theTitle)
    set oldDelimiters to AppleScript's text item delimiters
    repeat with delimiterValue in {tab, return, linefeed}
        set AppleScript's text item delimiters to contents of delimiterValue
        set pieces to text items of theTitle
        set AppleScript's text item delimiters to " "
        set theTitle to pieces as text
    end repeat
    set AppleScript's text item delimiters to oldDelimiters
    return theTitle
end cleanTitle

on run argv
    set destination to item 1 of argv
    if destination is "list" then
        set output to ""
        set columnSeparator to ASCII character 9
        tell application "Google Chrome"
            repeat with chromeWindow in windows
                if minimized of chromeWindow is false then
                    set serviceName to my mediaService(URL of active tab of chromeWindow as text)
                    if serviceName is not "" then
                        set b to bounds of chromeWindow
                        set titleText to my cleanTitle(name of chromeWindow as text)
                        set output to output & serviceName & columnSeparator & (item 1 of b as text) & columnSeparator & (item 2 of b as text) & columnSeparator & (item 3 of b as text) & columnSeparator & (item 4 of b as text) & columnSeparator & titleText & linefeed
                    end if
                end if
            end repeat
        end tell
        return output
    end if
    set separateWindow to false
    if (count of argv) > 1 then set separateWindow to item 2 of argv is "window"
    if destination is "youtubeMusic" then
        set targetURL to "https://music.youtube.com/"
        set hosts to {"music.youtube.com"}
    else if destination is "spotify" then
        set targetURL to "https://open.spotify.com/"
        set hosts to {"open.spotify.com"}
    else if destination is "youtube" then
        set targetURL to "https://www.youtube.com/"
        set hosts to {"www.youtube.com", "youtube.com"}
    else if destination is "gdn" then
        set targetURL to "https://gasdigital.com/"
        set hosts to {"gasdigital.com", "www.gasdigital.com"}
    else if destination is "netflix" then
        set targetURL to "https://www.netflix.com/browse"
        set hosts to {"www.netflix.com", "netflix.com"}
    else if destination is "hbo" then
        set targetURL to "https://www.hbomax.com/"
        set hosts to {"www.hbomax.com", "hbomax.com", "play.hbomax.com", "www.max.com", "max.com", "play.max.com"}
    else if destination is "appleTV" then
        set targetURL to "https://tv.apple.com/"
        set hosts to {"tv.apple.com"}
    else if destination is "nba" then
        set targetURL to "https://www.nba.com/games"
        set hosts to {"www.nba.com", "nba.com"}
    else
        error "Unknown media destination"
    end if
    tell application "Google Chrome"
        repeat with chromeWindow in windows
            set tabNumber to 0
            repeat with chromeTab in tabs of chromeWindow
                set tabNumber to tabNumber + 1
                repeat with hostName in hosts
                    if my matchesHost(URL of chromeTab as text, contents of hostName) and (destination is not "nba" or my matchesNBA(URL of chromeTab as text)) then
                        set active tab index of chromeWindow to tabNumber
                        set minimized of chromeWindow to false
                        set index of chromeWindow to 1
                        activate
                        if separateWindow and (count of tabs of chromeWindow) > 1 then return "detach"
                        return "ready"
                    end if
                end repeat
            end repeat
        end repeat
        if separateWindow or (count of windows) is 0 then
            make new window
            set URL of active tab of front window to targetURL
        else
            tell front window
                make new tab at end of tabs with properties {URL:targetURL}
                set active tab index to count of tabs
                set minimized to false
            end tell
        end if
        activate
    end tell
    return "Opened media tab"
end run
