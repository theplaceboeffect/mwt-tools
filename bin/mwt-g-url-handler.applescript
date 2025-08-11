on open location theURL
  set urlText to (theURL as text)
  try
    if urlText starts with "goto://" then
      set delimPos to offset of "://" in urlText
      set theAlias to text (delimPos + 3) thru -1 of urlText
      set projectDirQ to quoted form of "/Users/mwt/projects/mwt-tools/mwt-g"
      set ps1PathQ to quoted form of "/Users/mwt/projects/mwt-tools/mwt-g/bin/mwt-g.ps1"
      set aliasQ to quoted form of theAlias
      set shellCmd to "cd " & projectDirQ & " && /usr/bin/env pwsh -NoProfile -File " & ps1PathQ & " +b " & aliasQ 
      # display dialog ("About to run:\n" & shellCmd) buttons {"OK"} default button "OK" with icon note
      do shell script shellCmd
    end if
  on error errMsg number errNum
    display dialog ("ERROR: " & errMsg & " (" & errNum & ")") buttons {"OK"} default button "OK" with icon stop
  end try
end open location
