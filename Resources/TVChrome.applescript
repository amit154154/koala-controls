on run argv
    set destination to item 1 of argv
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
        make new window
        set URL of active tab of front window to targetURL
        activate
    end tell
    return "Opened TV window"
end run
