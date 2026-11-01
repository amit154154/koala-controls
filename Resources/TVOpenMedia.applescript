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
    if (count of theTitle) > 100 then set theTitle to text 1 thru 100 of theTitle
    return theTitle
end cleanTitle

-- Reads only recognized media tabs. Never navigates, reloads, or runs page JavaScript.
on run argv
    if application "Google Chrome" is not running then return ""
    set actionName to item 1 of argv
    set separator to ASCII character 9
    with timeout of 8 seconds
        tell application "Google Chrome"
            if actionName is "list" then
                set output to ""
                set foundCount to 0
                repeat with w in windows
                    if mode of w is "normal" then
                        repeat with t in tabs of w
                            set serviceName to my mediaService(URL of t as text)
                            if serviceName is not "" then
                                set b to bounds of w
                                set isActive to "0"
                                if (id of active tab of w as text) is (id of t as text) then set isActive to "1"
                                set output to output & serviceName & separator & (id of w as text) & separator & (id of t as text) & separator & (item 1 of b as text) & separator & (item 2 of b as text) & separator & (item 3 of b as text) & separator & (item 4 of b as text) & separator & my cleanTitle(title of t as text) & separator & isActive & linefeed
                                set foundCount to foundCount + 1
                                if foundCount >= 24 then return output
                            end if
                        end repeat
                    end if
                end repeat
                return output
            end if
            if actionName is not "select" and actionName is not "locate" and actionName is not "place" then error "Unknown resume action"
            set wantedWindow to item 2 of argv
            set wantedTab to item 3 of argv
            set wantedService to item 4 of argv
            repeat with w in windows
                if mode of w is "normal" and (actionName is "locate" or actionName is "place" or (id of w as text) is wantedWindow) then
                    set tabNumber to 0
                    repeat with t in tabs of w
                        set tabNumber to tabNumber + 1
                        if (id of t as text) is wantedTab then
                            if my mediaService(URL of t as text) is not wantedService then error "This tab is no longer a media service. Refresh Continue watching."
                            if actionName is "select" then
                                set active tab index of w to tabNumber
                                set minimized of w to false
                                set index of w to 1
                                activate
                            end if
                            if actionName is "place" then
                                set minimized of w to false
                                set zoomed of w to false
                                set bounds of w to {(item 5 of argv as integer), (item 6 of argv as integer), (item 7 of argv as integer), (item 8 of argv as integer)}
                            end if
                            set b to bounds of w
                            return (id of w as text) & separator & (count of tabs of w as text) & separator & (item 1 of b as text) & separator & (item 2 of b as text) & separator & (item 3 of b as text) & separator & (item 4 of b as text) & separator & my cleanTitle(title of t as text)
                        end if
                    end repeat
                end if
            end repeat
        end tell
    end timeout
    error "This media tab closed. Refresh Continue watching."
end run
