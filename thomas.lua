dofile("urlcode.lua")
dofile("table_show.lua")

local url_count = 0
local tries = 0
local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_value_filled = os.getenv('item_value_filled')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local downloaded = {}
local addedtolist = {}
local fields = {}

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url)
  if string.match(url, "[^0-9a-zA-Z]"..item_value) and not string.match(url, "[^0-9a-zA-Z]"..item_value.."[0-9]") then
    return true
  elseif string.match(url, "[^0-9]"..item_value_filled) and not (string.match(url, "[^0-9]"..item_value_filled.."[0-9]") or string.match(url, "[^0-9]"..item_value.."[^0-9]")) then
    return true
  else
    return false
  end
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[fF][iI][eE][lL][dD]%(") then
    fields[string.gsub(url, "&amp;", "&")] = true
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true) and (allowed(url) or string.match(url, "/https?://[^/]*gpo.gov/") or html == 0) then
    addedtolist[url] = true
    return true
  else
    return false
  end
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local url = string.match(urla, "^([^#]+)")
    if string.match(url, "[fF][iI][eE][lL][dD]%(") then
      fields[string.gsub(url, "&amp;", "&")] = true
    end
    if string.match(url, "/https?://?[^/].+") then
      newurl = string.gsub(string.match(url, "/(https?://?[^/].+)"), "/(https?)://?([^/].+)", "%1://%2")
      table.insert(urls, { url=newurl })
      addedtolist[newurl] = true
    end
    if (downloaded[url] ~= true and addedtolist[url] ~= true) and (allowed(url) or string.match(url, "/https?://[^/]*gpo.gov/")) then
      if string.match(url, "&amp;") then
        table.insert(urls, { url=string.gsub(url, "&amp;", "&") })
        addedtolist[url] = true
        addedtolist[string.gsub(url, "&amp;", "&")] = true
      else
        table.insert(urls, { url=url })
        addedtolist[url] = true
      end
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^//") then
      check("http:"..newurl)
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?://") or string.match(newurl, "^/") or string.match(newurl, "^[jJ]ava[sS]cript:") or string.match(newurl, "^[mM]ail[tT]o:") or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end
  
  if allowed(url) then
    html = read_file(file)
    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">([^<]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "PopWin%('([^']+)") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, 'PopWin%("([^"]+)') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, 'href="([^"]+)"') do
      checknewshorturl(newurl)
    end
  end

  return urls
end
  

wget.callbacks.httploop_result = function(url, err, http_stat)
  -- NEW for 2014: Slightly more verbose messages because people keep
  -- complaining that it's not moving or not working
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if downloaded[url["url"]] == true then
    return wget.actions.EXIT
  end

  if (status_code >= 200 and status_code <= 399) then
    if string.match(url.url, "https://") then
      local newurl = string.gsub(url.url, "https://", "http://")
      downloaded[newurl] = true
    else
      downloaded[url.url] = true
    end
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"]) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local usersfile = io.open(item_dir..'/'..warc_file_base..'_data.txt', 'w')
  for field, _ in pairs(fields) do
    usersfile:write(field.."\n")
  end
  usersfile:close()
end