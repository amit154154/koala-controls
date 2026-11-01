-- Use Chrome's own tab API. Never reads browser profiles, clipboard or page content.
on isKoalaURL(theURL)
    repeat with origin in {"http://localhost:8300", "http://127.0.0.1:8300"}
        set base to contents of origin
        if theURL is base or theURL starts with (base & "/") or theURL starts with (base & "?") or theURL starts with (base & "#") then return true
    end repeat
    return false
end isKoalaURL

tell application "Google Chrome"
    repeat with chromeWindow in windows
        set tabNumber to 0
        repeat with chromeTab in tabs of chromeWindow
            set tabNumber to tabNumber + 1
            if my isKoalaURL(URL of chromeTab as text) then
                set active tab index of chromeWindow to tabNumber
                set minimized of chromeWindow to false
                set index of chromeWindow to 1
                activate
                return "Focused existing Koala Viz tab"
            end if
        end repeat
    end repeat
    if (count of windows) is 0 then
        make new window
        set URL of active tab of front window to "http://localhost:8300/"
    else
        tell front window
            set newTab to make new tab at end of tabs with properties {URL:"http://localhost:8300/"}
            set active tab index to count of tabs
            set minimized to false
        end tell
    end if
    activate
end tell
return "Opened Koala Viz"
