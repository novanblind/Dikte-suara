require "import"
import "android.content.*"
import "android.content.ClipData"
import "android.speech.*"
import "android.widget.*"
import "android.os.Handler"
import "android.os.Looper"
import "android.os.Bundle"
import "android.view.accessibility.AccessibilityNodeInfo"
import "android.text.Html"
import "android.app.AlertDialog"
import "android.view.WindowManager"
import "android.view.View"
import "android.content.DialogInterface"
import "java.util.Locale"
import "java.net.URL"
import "java.net.URLEncoder"
import "java.net.HttpURLConnection"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.lang.Thread"
import "java.lang.Runnable"
import "java.lang.System"
import "java.lang.String"
import "org.json.JSONObject"
import "org.json.JSONArray"

local konteks = this or service
local CURRENT_VERSION = "v5.0"
local UPDATE_URL = "https://raw.githubusercontent.com/novanblind/Dikte-suara/main/inputsuara.lua"

local PREF_NAME = "translator_voice_config"
local PREF_KEY_ENGINE = "selected_translation_engine"
local PREF_KEY_GROQ_API = "groq_api_key"
local PREF_KEY_GEMINI_API = "gemini_api_key"

-- 3 Model Groq aktif pendukung terjemahan teks bahasa Indonesia (diurutkan berdasarkan prioritas kehalusan bahasa)
local GROQ_TRANSLATION_MODELS = {
    "qwen/qwen3.8-27b",    -- Prioritas 1: Bahasa Indonesia paling natural & luwes
    "openai/gpt-oss-20b",  -- Prioritas 2: Respons cepat & tata bahasa baku rapi
    "openai/gpt-oss-120b"  -- Prioritas 3: Parameter terbesar, akurasi tinggi kalimat kompleks
}

-- Model Gemini khusus varian Flash dan Flash-Lite untuk terjemahan cepat & hemat kuota
local GEMINI_TRANSLATION_MODELS = {
    "gemini-2.5-flash",
    "gemini-2.5-flash-lite",
    "gemini-flash-latest",
    "gemini-flash-lite-latest",
    "gemini-3-flash-preview",
    "gemini-3.1-flash-lite",
    "gemini-3.1-flash-lite-preview",
    "gemini-3.5-flash",
    "gemini-3.5-flash-lite",
    "gemini-3.6-flash",
    "gemini-3.7-flash",
    "gemini-3.8-flash",
    "gemini-omni-flash-preview",
    "gemini-omni-1.1-flash"
}

-- Pengelolaan Preferensi (SharedPreferences)
local function getEngine()
    local engine = "Google"
    pcall(function()
        local sp = konteks.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        engine = sp.getString(PREF_KEY_ENGINE, "Google")
    end)
    return (engine and engine ~= "") and engine or "Google"
end

local function saveEngine(engine)
    pcall(function()
        local sp = konteks.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        local editor = sp.edit()
        editor.putString(PREF_KEY_ENGINE, tostring(engine))
        editor.apply()
    end)
end

local function getGroqApiKey()
    local key = ""
    pcall(function()
        local sp = konteks.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        key = sp.getString(PREF_KEY_GROQ_API, "")
    end)
    return key or ""
end

local function saveGroqApiKey(newKey)
    pcall(function()
        local sp = konteks.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        local editor = sp.edit()
        editor.putString(PREF_KEY_GROQ_API, tostring(newKey))
        editor.apply()
    end)
end

local function getGeminiApiKey()
    local key = ""
    pcall(function()
        local sp = konteks.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        key = sp.getString(PREF_KEY_GEMINI_API, "")
    end)
    return key or ""
end

local function saveGeminiApiKey(newKey)
    pcall(function()
        local sp = konteks.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        local editor = sp.edit()
        editor.putString(PREF_KEY_GEMINI_API, tostring(newKey))
        editor.apply()
    end)
end

local function showToast(message)
    local handler = Handler(Looper.getMainLooper())
    handler.post(Runnable({
        run = function()
            Toast.makeText(konteks, tostring(message), Toast.LENGTH_SHORT).show()
        end
    }))
end

local function isConnected()
    local cm = konteks.getSystemService(Context.CONNECTIVITY_SERVICE)
    local activeNetwork = cm and cm.getActiveNetworkInfo()
    return activeNetwork ~= nil and activeNetwork.isConnected()
end

-- Menampilkan dialog aman untuk Accessibility Service
local function showSafeDialog(dialog)
    pcall(function()
        local win = dialog.getWindow()
        if win then
            local overlayType = 2032
            if WindowManager and WindowManager.LayoutParams and WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY then
                overlayType = WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            end
            win.setType(overlayType)
        end
    end)
    dialog.show()
end

-- Fitur Periksa Pembaruan Versi Baru
local function checkUpdate()
    if not isConnected() then
        showToast("Butuh koneksi internet untuk memeriksa versi")
        if service and service.speak then service.speak("Butuh internet") end
        return
    end

    showToast("Memeriksa versi baru...")
    if service and service.speak then service.speak("Memeriksa versi baru") end

    Thread(Runnable({
        run = function()
            local success = false
            local remoteCode = nil

            pcall(function()
                local url = URL(UPDATE_URL)
                local conn = url.openConnection()
                conn.setRequestMethod("GET")
                conn.setConnectTimeout(8000)
                conn.setReadTimeout(12000)
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                conn.setRequestProperty("Cache-Control", "no-cache")

                if conn.getResponseCode() == 200 then
                    local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                    local lines = {}
                    local line = reader.readLine()
                    while line ~= nil do
                        table.insert(lines, line)
                        line = reader.readLine()
                    end
                    reader.close()
                    remoteCode = table.concat(lines, "\n")
                    success = true
                end
                conn.disconnect()
            end)

            local handler = Handler(Looper.getMainLooper())
            handler.post(Runnable({
                run = function()
                    if success and remoteCode and #remoteCode > 0 then
                        local remoteVer = remoteCode:match('CURRENT_VERSION%s*=%s*["\']([^"\']+)["\']')
                        if not remoteVer then
                            remoteVer = remoteCode:match('[Vv]ersi%s*([%d%.]+)') or remoteCode:match('v([%d%.]+)')
                        end

                        local hasUpdate = false
                        if remoteVer then
                            if remoteVer ~= CURRENT_VERSION then
                                hasUpdate = true
                            end
                        else
                            remoteVer = "Tersedia di Server"
                            hasUpdate = true
                        end

                        local builder = AlertDialog.Builder(konteks)
                        if hasUpdate then
                            builder.setTitle("Pembaruan Ditemukan!")
                            builder.setMessage("Versi saat ini: " .. CURRENT_VERSION .. "\nVersi baru: " .. tostring(remoteVer) .. "\n\nApakah Anda ingin memperbarui script ini sekarang?")
                            
                            builder.setPositiveButton("Perbarui Sekarang", DialogInterface.OnClickListener({
                                onClick = function(dialog, which)
                                    local scriptPath = nil
                                    pcall(function()
                                        local info = debug.getinfo(1, "S")
                                        if info and info.source and info.source:sub(1, 1) == "@" then
                                            scriptPath = info.source:sub(2)
                                        end
                                    end)

                                    local fileSaved = false
                                    if scriptPath then
                                        pcall(function()
                                            local f = io.open(scriptPath, "w")
                                            if f then
                                                f:write(remoteCode)
                                                f:close()
                                                fileSaved = true
                                            end
                                        end)
                                    end

                                    pcall(function()
                                        local cm = konteks.getSystemService(Context.CLIPBOARD_SERVICE)
                                        local cd = ClipData.newPlainText("Script Update", remoteCode)
                                        cm.setPrimaryClip(cd)
                                    end)

                                    if fileSaved then
                                        showToast("Script berhasil diperbarui ke " .. tostring(remoteVer))
                                        if service and service.speak then service.speak("Script berhasil diperbarui") end
                                    else
                                        showToast("Script baru telah disalin ke papan klip")
                                        if service and service.speak then service.speak("Script baru disalin ke papan klip") end
                                    end
                                end
                            }))

                            builder.setNegativeButton("Batal", DialogInterface.OnClickListener({
                                onClick = function(dialog, which)
                                    dialog.dismiss()
                                end
                            }))
                        else
                            builder.setTitle("Versi Terbaru")
                            builder.setMessage("Script Anda sudah menggunakan versi paling baru (" .. CURRENT_VERSION .. "). Tidak ada pembaruan.")
                            builder.setPositiveButton("OK", DialogInterface.OnClickListener({
                                onClick = function(dialog, which)
                                    dialog.dismiss()
                                end
                            }))
                        end
                        showSafeDialog(builder.create())
                    else
                        showToast("Gagal memeriksa versi baru dari server")
                        if service and service.speak then service.speak("Gagal memeriksa pembaruan") end
                    end
                end
            }))
        end
    })).start()
end

-- Dialog Pilihan Mesin Terjemahan
local function showEngineSelectionDialog()
    local handler = Handler(Looper.getMainLooper())
    handler.post(Runnable({
        run = function()
            local engines = {"Google", "Groq", "Gemini"}
            local current = getEngine()
            local selectedIndex = 0
            for i, v in ipairs(engines) do
                if v == current then
                    selectedIndex = i - 1
                    break
                end
            end

            local chosen = current
            local builder = AlertDialog.Builder(konteks)
            builder.setTitle("Pilih Mesin Terjemahan")
            builder.setSingleChoiceItems(engines, selectedIndex, DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    chosen = engines[which + 1]
                end
            }))

            builder.setPositiveButton("Simpan", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    saveEngine(chosen)
                    showToast("Mesin terjemahan diatur ke: " .. chosen)
                    if service and service.speak then
                        service.speak("Mesin terjemahan " .. chosen)
                    end
                end
            }))

            builder.setNegativeButton("Batal", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    dialog.dismiss()
                end
            }))

            showSafeDialog(builder.create())
        end
    }))
end

-- Dialog Pengaturan Kunci API Groq
local function showGroqApiKeyDialog()
    local handler = Handler(Looper.getMainLooper())
    handler.post(Runnable({
        run = function()
            local builder = AlertDialog.Builder(konteks)
            builder.setTitle("Kunci API Groq")

            local layout = LinearLayout(konteks)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(50, 30, 50, 30)

            local lbl = TextView(konteks)
            lbl.setText("Masukkan Kunci API Groq:")
            lbl.setTextSize(14)
            lbl.setPadding(0, 0, 0, 15)
            layout.addView(lbl)

            local input = EditText(konteks)
            input.setHint("Tempel kunci API (gsk_...)")
            local currentKey = getGroqApiKey()
            input.setText(currentKey)
            if currentKey and #currentKey > 0 then
                input.setSelection(#currentKey)
            end
            layout.addView(input)

            builder.setView(layout)

            builder.setPositiveButton("Simpan", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    local newKey = tostring(input.getText()):gsub("^%s+", ""):gsub("%s+$", "")
                    saveGroqApiKey(newKey)
                    showToast("Kunci API Groq disimpan")
                    if service and service.speak then
                        service.speak("Kunci API Groq disimpan")
                    end
                end
            }))

            builder.setNeutralButton("Kosongkan", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    saveGroqApiKey("")
                    input.setText("")
                    showToast("Kunci API Groq dikosongkan")
                    if service and service.speak then
                        service.speak("Kunci API Groq dikosongkan")
                    end
                end
            }))

            builder.setNegativeButton("Batal", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    dialog.dismiss()
                end
            }))

            showSafeDialog(builder.create())
        end
    }))
end

-- Dialog Pengaturan Kunci API Gemini
local function showGeminiApiKeyDialog()
    local handler = Handler(Looper.getMainLooper())
    handler.post(Runnable({
        run = function()
            local builder = AlertDialog.Builder(konteks)
            builder.setTitle("Kunci API Gemini")

            local layout = LinearLayout(konteks)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(50, 30, 50, 30)

            local lbl = TextView(konteks)
            lbl.setText("Masukkan Kunci API Google Gemini:")
            lbl.setTextSize(14)
            lbl.setPadding(0, 0, 0, 15)
            layout.addView(lbl)

            local input = EditText(konteks)
            input.setHint("Tempel kunci API Gemini...")
            local currentKey = getGeminiApiKey()
            input.setText(currentKey)
            if currentKey and #currentKey > 0 then
                input.setSelection(#currentKey)
            end
            layout.addView(input)

            builder.setView(layout)

            builder.setPositiveButton("Simpan", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    local newKey = tostring(input.getText()):gsub("^%s+", ""):gsub("%s+$", "")
                    saveGeminiApiKey(newKey)
                    showToast("Kunci API Gemini disimpan")
                    if service and service.speak then
                        service.speak("Kunci API Gemini disimpan")
                    end
                end
            }))

            builder.setNeutralButton("Kosongkan", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    saveGeminiApiKey("")
                    input.setText("")
                    showToast("Kunci API Gemini dikosongkan")
                    if service and service.speak then
                        service.speak("Kunci API Gemini dikosongkan")
                    end
                end
            }))

            builder.setNegativeButton("Batal", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    dialog.dismiss()
                end
            }))

            showSafeDialog(builder.create())
        end
    }))
end

-- Dialog Menu Utama
local function showMainMenu()
    local handler = Handler(Looper.getMainLooper())
    handler.post(Runnable({
        run = function()
            local builder = AlertDialog.Builder(konteks)
            builder.setTitle("Dikte Suara (" .. CURRENT_VERSION .. ")")

            local layout = LinearLayout(konteks)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(50, 30, 50, 30)

            local btnEngine = Button(konteks)
            btnEngine.setText("Pilihan Mesin: " .. getEngine())
            layout.addView(btnEngine)

            local btnGroq = Button(konteks)
            btnGroq.setText("Pengaturan Kunci API Groq")
            layout.addView(btnGroq)

            local btnGemini = Button(konteks)
            btnGemini.setText("Pengaturan Kunci API Gemini")
            layout.addView(btnGemini)

            local btnUpdate = Button(konteks)
            btnUpdate.setText("Periksa Versi Baru")
            layout.addView(btnUpdate)

            builder.setView(layout)
            builder.setNegativeButton("Tutup", DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    dialog.dismiss()
                end
            }))

            local dlg = builder.create()

            local function bindClick(btn, action)
                pcall(function()
                    btn.setOnClickListener(View.OnClickListener({
                        onClick = function(v)
                            dlg.dismiss()
                            action()
                        end
                    }))
                end)
                btn.onClick = function(v)
                    dlg.dismiss()
                    action()
                end
            end

            bindClick(btnEngine, showEngineSelectionDialog)
            bindClick(btnGroq, showGroqApiKeyDialog)
            bindClick(btnGemini, showGeminiApiKeyDialog)
            bindClick(btnUpdate, checkUpdate)

            showSafeDialog(dlg)
        end
    }))
end

-- Periksa ketersediaan kolom ketik di layar
local currentEditNode = nil
if service and service.getEditText then
    currentEditNode = service.getEditText()
end

if not currentEditNode then
    _G._IS_SPEECH_ACTIVE = false
    showMainMenu()
    return true
end

-- Debounce & Lock Mic
local now = System.currentTimeMillis()
if _G._IS_SPEECH_ACTIVE or (_G._LAST_SPEECH_TIME and (now - _G._LAST_SPEECH_TIME < 1500)) then
    return true
end
_G._LAST_SPEECH_TIME = now
_G._IS_SPEECH_ACTIVE = true

local recognizerInstance = nil

local languages = {
    ["aceh"] = "ace", ["bali"] = "ban", ["banjar"] = "bjn", ["batak"] = "bbc",
    ["batak toba"] = "bbc", ["batak karo"] = "btx", ["batak simalungun"] = "bts",
    ["betawi"] = "bew", ["bugis"] = "bug", ["dayak"] = "day", ["jawa"] = "jw",
    ["lampung"] = "ljp", ["madura"] = "mad", ["makassar"] = "mak", ["manado"] = "xmm",
    ["melayu"] = "ms", ["minang"] = "min", ["minangkabau"] = "min", ["palembang"] = "plm",
    ["papua"] = "pmy", ["sasak"] = "sas", ["sunda"] = "su", ["toraja"] = "sda",
    ["afrikaans"] = "af", ["albania"] = "sq", ["amharik"] = "am", ["arab"] = "ar",
    ["armenia"] = "hy", ["azerbaijan"] = "az", ["basque"] = "eu", ["belanda"] = "nl",
    ["belarussia"] = "be", ["bengali"] = "bn", ["bosnia"] = "bs", ["bulgaria"] = "bg",
    ["burma"] = "my", ["ceko"] = "cs", ["china"] = "zh-CN", ["mandarin"] = "zh-CN",
    ["taiwan"] = "zh-TW", ["denmark"] = "da", ["esperanto"] = "eo", ["estonia"] = "et",
    ["finlandia"] = "fi", ["galicia"] = "gl", ["georgia"] = "ka", ["gujarati"] = "gu",
    ["haiti"] = "ht", ["hausa"] = "ha", ["hawaii"] = "haw", ["hindi"] = "hi",
    ["hmong"] = "hmn", ["hungaria"] = "hu", ["ibrani"] = "he", ["igbo"] = "ig",
    ["indonesia"] = "id", ["inggris"] = "en", ["irlandia"] = "ga", ["islandia"] = "is",
    ["italia"] = "it", ["jepang"] = "ja", ["jerman"] = "de", ["kannada"] = "kn",
    ["katalan"] = "ca", ["kazakh"] = "kk", ["khmer"] = "km", ["korea"] = "ko",
    ["kroasia"] = "hr", ["kurdi"] = "ku", ["laos"] = "lo", ["latin"] = "la",
    ["latvia"] = "lv", ["lithuania"] = "lt", ["luxembourg"] = "lb", ["makedonia"] = "mk",
    ["madagaskar"] = "mg", ["malayalam"] = "ml", ["malaysia"] = "ms", ["malta"] = "mt",
    ["maori"] = "mi", ["marathi"] = "mr", ["mongolia"] = "mn", ["nepal"] = "ne",
    ["norwegia"] = "no", ["pashto"] = "ps", ["persia"] = "fa", ["polandia"] = "pl",
    ["portugis"] = "pt", ["prancis"] = "fr", ["punjabi"] = "pa", ["rumania"] = "ro",
    ["rusia"] = "ru", ["samoa"] = "sm", ["serbia"] = "sr", ["sesotho"] = "st",
    ["shona"] = "sn", ["sindhi"] = "sd", ["sinhala"] = "si", ["slovakia"] = "sk",
    ["slovenia"] = "sl", ["somalia"] = "so", ["spanyol"] = "es", ["swahili"] = "sw",
    ["swedia"] = "sv", ["tagalog"] = "tl", ["tajik"] = "tg", ["tamil"] = "ta",
    ["telugu"] = "te", ["thai"] = "th", ["turki"] = "tr", ["ukraina"] = "uk",
    ["urdu"] = "ur", ["uzbek"] = "uz", ["vietnam"] = "vi", ["wales"] = "cy",
    ["xhosa"] = "xh", ["yiddish"] = "yi", ["yoruba"] = "yo", ["yunani"] = "el",
    ["zulu"] = "zu"
}

local punctuationMap = {
    {"garis miring terbalik", "\\"}, {"buka kurung kurawal", "{"}, {"tutup kurung kurawal", "}"},
    {"buka kurung siku", "["}, {"tutup kurung siku", "]"}, {"tanda seru dua kali", "!!"},
    {"tanda tanya dua kali", "??"}, {"tanda titik tiga", "..."}, {"garis miring kanan", "/"},
    {"garis miring kiri", "\\"}, {"tanda petik satu", "'"}, {"tanda petik dua", "\""},
    {"tanda kutip dua", "\""}, {"tanda sama dengan", "="}, {"tanda titik dua", ":"},
    {"tanda titik koma", ";"}, {"tanda garis baru", "\n"}, {"tanda baris baru", "\n"},
    {"tanda garis miring", "/"}, {"tanda garis bawah", "_"}, {"tanda hubung", "-"},
    {"tanda kurang", "-"}, {"tanda minus", "-"}, {"tanda tambah", "+"}, {"tanda bintang", "*"},
    {"tanda persen", "%"}, {"tanda kutip", "\""}, {"tanda petik", "\""}, {"tanda tanya", "?"},
    {"tanda seru", "!"}, {"tanda titik", "."}, {"tanda koma", ","}, {"tanda tagar", "#"},
    {"tanda plus", "+"}, {"tanda derajat", "°"}, {"tanda dan", "&"}, {"tanda at", "@"},
    {"paragraf baru", "\n"}, {"baris baru", "\n"}, {"garis baru", "\n"}, {"garis miring", "/"},
    {"garis bawah", "_"}, {"buka kurung", "("}, {"tutup kurung", ")"}, {"titik dua", ":"},
    {"titik koma", ";"}, {"titik tiga", "..."}, {"petik satu", "'"}, {"petik dua", "\""},
    {"kutip satu", "'"}, {"kutip dua", "\""}, {"sama dengan", "="}, {"hashtag", "#"},
    {"persen", "%"}, {"bintang", "*"}, {"tagar", "#"}, {"minus", "-"}, {"strip", "-"},
    {"slash", "/"}, {"enter", "\n"}, {"titik", "."}, {"koma", ","}, {"plus", "+"}
}

local function destroyRecognizer()
    _G._IS_SPEECH_ACTIVE = false
    if recognizerInstance then
        pcall(function()
            recognizerInstance.cancel()
            recognizerInstance.destroy()
        end)
        recognizerInstance = nil
    end
end

local function replaceAllCaseInsensitive(text, target, replacement)
    local lowerText = text:lower()
    local lowerTarget = target:lower()
    local result = ""
    local lastIndex = 1
    local s, e = lowerText:find(lowerTarget, 1, true)
    while s do
        result = result .. text:sub(lastIndex, s - 1) .. replacement
        lastIndex = e + 1
        s, e = lowerText:find(lowerTarget, lastIndex, true)
    end
    result = result .. text:sub(lastIndex)
    return result
end

-- Format teks otomatis
local function formatText(text)
    if text:sub(-1) == "." then
        local testText = text:sub(1, -2)
        local hasSpokenDot = false
        local lowerTest = testText:lower():gsub("%s+$", "")
        for _, item in ipairs(punctuationMap) do
            if item[2] == "." or item[2] == "..." then
                if lowerTest == item[1] or lowerTest:match("%s" .. item[1] .. "$") then
                    hasSpokenDot = true
                    text = testText
                    break
                end
            end
        end
        if not hasSpokenDot then
            text = testText
        end
    end

    for _, item in ipairs(punctuationMap) do
        text = replaceAllCaseInsensitive(text, " " .. item[1], item[2])
        text = replaceAllCaseInsensitive(text, item[1], item[2])
    end

    text = text:gsub("%s+([%,%.%?!%:%;%)%]%}%_])", "%1")
    text = text:gsub("([%(%[%{])%s+", "%1")
    text = text:gsub("([%,%?!%:%;])(%a)", "%1 %2")
    text = text:gsub("(%.)(%a)", "%1 %2")
    text = text:gsub("%s*\n%s*", "\n")

    text = text:gsub("^%s*%l", string.upper)
    text = text:gsub("([%.%?!]%s*)(%l)", function(p, c) return p .. c:upper() end)
    text = text:gsub("(,%s*)(%u)", function(p, c) return p .. c:lower() end)
    return text:gsub("%s+$", "")
end

-- Memasukkan teks langsung ke kolom input
local function insertText(text, targetNode)
    text = text:gsub("%s+$", "")
    local handler = Handler(Looper.getMainLooper())
    handler.post(Runnable({
        run = function()
            local node = targetNode or (service and service.getEditText and service.getEditText())
            if node and service and service.insert then
                service.insert(node, text)
            elseif service and service.paste then
                service.paste(text)
            end

            showToast(text)
            if service and service.speak then
                service.speak(text)
            end
        end
    }))
end

local function clearAllText()
    local node = service.getEditText()
    if node then
        local args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
        local success = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        
        if not success then
            local selectArgs = Bundle()
            selectArgs.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, 0)
            selectArgs.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, 100000)
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selectArgs)
            service.insert(node, "")
        end
        showToast("Semua teks dihapus")
        if service and service.speak then
            service.speak("Semua teks dihapus")
        end
    else
        showToast("Kolom teks tidak ditemukan")
    end
end

----------------------------------------------------------------
-- 1. Jalur Terjemahan Google
----------------------------------------------------------------
local function translateWithGoogle(text, targetLang, callback)
    if not isConnected() then
        showToast("Butuh koneksi internet")
        if service and service.speak then service.speak("Butuh internet") end
        callback(text)
        return
    end

    Thread(Runnable({
        run = function()
            local resultText = nil
            local isSuccess = false

            pcall(function()
                local encodedText = URLEncoder.encode(text, "UTF-8")
                local urlString = string.format("https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=%s&dt=t&q=%s", targetLang, encodedText)
                local url = URL(urlString)
                local conn = url.openConnection()
                conn.setRequestMethod("GET")
                conn.setConnectTimeout(8000)
                conn.setReadTimeout(8000)
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                conn.setRequestProperty("Accept", "*/*")

                if conn.getResponseCode() == 200 then
                    local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                    local lines = {}
                    local line = reader.readLine()
                    while line ~= nil do
                        table.insert(lines, line)
                        line = reader.readLine()
                    end
                    reader.close()

                    local res = table.concat(lines, "\n")
                    local jsonArray = JSONArray(res)
                    local sentences = jsonArray.getJSONArray(0)
                    local translatedText = ""

                    for i = 0, sentences.length() - 1 do
                        local item = sentences.getJSONArray(i)
                        if not item.isNull(0) then
                            translatedText = translatedText .. item.getString(0)
                        end
                    end

                    if translatedText ~= "" then
                        resultText = translatedText
                        isSuccess = true
                    end
                end
                conn.disconnect()
            end)

            local handler = Handler(Looper.getMainLooper())
            handler.post(Runnable({
                run = function()
                    if isSuccess and resultText then
                        callback(resultText)
                    else
                        showToast("Gagal memproses hasil terjemahan Google")
                        if service and service.speak then service.speak("Gagal menerjemahkan") end
                        callback(text)
                    end
                end
            }))
        end
    })).start()
end

----------------------------------------------------------------
-- 2. Jalur Terjemahan Groq AI (Fallback Otomatis 3 Model Aktif)
----------------------------------------------------------------
local function tryGroqModel(modelIndex, promptText, customInstruction, apiKey, callback)
    if modelIndex > #GROQ_TRANSLATION_MODELS then
        callback(false, nil)
        return
    end

    local model = GROQ_TRANSLATION_MODELS[modelIndex]
    local endpoint = "https://api.groq.com/openai/v1/chat/completions"
    local instruction = customInstruction or "Terjemahkan teks secara langsung tanpa penjelasan."

    Thread(Runnable({
        run = function()
            local resultText = nil
            local isSuccess = false
            local maxRetries = 2
            local attempt = 0

            local jsonPayload = JSONObject()
            jsonPayload.put("model", model)
            jsonPayload.put("temperature", 0.2)
            jsonPayload.put("max_tokens", 1000)

            local messages = JSONArray()
            local sysObj = JSONObject()
            sysObj.put("role", "system")
            sysObj.put("content", instruction)
            messages.put(sysObj)

            local userObj = JSONObject()
            userObj.put("role", "user")
            userObj.put("content", promptText)
            messages.put(userObj)

            jsonPayload.put("messages", messages)
            local postData = String(jsonPayload.toString()).getBytes("UTF-8")

            while attempt < maxRetries and not isSuccess do
                attempt = attempt + 1
                local conn = nil
                local reader = nil

                pcall(function()
                    local url = URL(endpoint)
                    conn = url.openConnection()
                    conn.setRequestMethod("POST")
                    conn.setConnectTimeout(8000)
                    conn.setReadTimeout(12000)
                    conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                    conn.setRequestProperty("Authorization", "Bearer " .. apiKey)
                    conn.setDoOutput(true)

                    local os = conn.getOutputStream()
                    os.write(postData)
                    os.flush()
                    os.close()

                    if conn.getResponseCode() == 200 then
                        reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                        local lines = {}
                        local line = reader.readLine()
                        while line ~= nil do
                            table.insert(lines, line)
                            line = reader.readLine()
                        end
                        reader.close()
                        reader = nil

                        local resJson = JSONObject(table.concat(lines, "\n"))
                        local choices = resJson.optJSONArray("choices")
                        if choices and choices.length() > 0 then
                            local msgObj = choices.getJSONObject(0).optJSONObject("message")
                            if msgObj then
                                local content = msgObj.optString("content")
                                if content and content ~= "" then
                                    resultText = content
                                    isSuccess = true
                                end
                            end
                        end
                    end
                end)

                if reader then pcall(function() reader.close() end) end
                if conn then pcall(function() conn.disconnect() end) end

                if not isSuccess and attempt < maxRetries then
                    pcall(function() Thread.sleep(1200) end)
                end
            end

            local handler = Handler(Looper.getMainLooper())
            handler.post(Runnable({
                run = function()
                    if isSuccess and resultText then
                        callback(true, resultText)
                    else
                        tryGroqModel(modelIndex + 1, promptText, customInstruction, apiKey, callback)
                    end
                end
            }))
        end
    })).start()
end

local function translateWithGroq(text, targetLang, callback)
    local apiKey = getGroqApiKey()
    if not apiKey or apiKey == "" then
        showToast("Kunci API Groq kosong, beralih ke Google")
        if service and service.speak then service.speak("Kunci API Groq kosong") end
        translateWithGoogle(text, targetLang, callback)
        return
    end

    if not isConnected() then
        showToast("Butuh koneksi internet")
        if service and service.speak then service.speak("Butuh internet") end
        callback(text)
        return
    end

    local langName = targetLang
    for name, code in pairs(languages) do
        if code == targetLang then
            langName = name
            break
        end
    end

    local sysInstruction = "Kamu adalah penerjemah profesional. Terjemahkan teks yang diberikan ke bahasa " .. langName .. " (" .. targetLang .. ").\n" ..
        "ATURAN:\n" ..
        "- Kembalikan HANYA hasil terjemahan langsung.\n" ..
        "- DILARANG menambahkan kalimat pembuka atau penjelasan.\n" ..
        "- DILARANG memberi tanda petik pembungkus."

    tryGroqModel(1, text, sysInstruction, apiKey, function(ok, res)
        if ok and res and res:match("%S") then
            local cleanTrans = res:gsub('^%s*"', ''):gsub('"%s*$', '')
            cleanTrans = cleanTrans:gsub("^%s*[Bb]erikut terjemahannya%s*:?%s*", "")
            cleanTrans = cleanTrans:gsub("^%s+", ""):gsub("%s+$", "")
            callback(cleanTrans)
        else
            showToast("Groq bermasalah, beralih ke Google")
            translateWithGoogle(text, targetLang, callback)
        end
    end)
end

----------------------------------------------------------------
-- 3. Jalur Terjemahan Gemini AI (Fallback Otomatis Flash/Flash-Lite)
----------------------------------------------------------------
local function tryGeminiModel(modelIndex, promptText, apiKey, callback)
    if modelIndex > #GEMINI_TRANSLATION_MODELS then
        callback(false, nil)
        return
    end

    local model = GEMINI_TRANSLATION_MODELS[modelIndex]
    local endpoint = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent?key=" .. apiKey

    Thread(Runnable({
        run = function()
            local resultText = nil
            local isSuccess = false
            local maxRetries = 2
            local attempt = 0

            local jsonPayload = JSONObject()
            local contents = JSONArray()
            local contentObj = JSONObject()
            local parts = JSONArray()
            local partObj = JSONObject()

            partObj.put("text", promptText)
            parts.put(partObj)
            contentObj.put("parts", parts)
            contents.put(contentObj)
            jsonPayload.put("contents", contents)

            local postData = String(jsonPayload.toString()).getBytes("UTF-8")

            while attempt < maxRetries and not isSuccess do
                attempt = attempt + 1
                local conn = nil
                local reader = nil

                pcall(function()
                    local url = URL(endpoint)
                    conn = url.openConnection()
                    conn.setRequestMethod("POST")
                    conn.setConnectTimeout(8000)
                    conn.setReadTimeout(12000)
                    conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                    conn.setDoOutput(true)

                    local os = conn.getOutputStream()
                    os.write(postData)
                    os.flush()
                    os.close()

                    if conn.getResponseCode() == 200 then
                        reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
                        local lines = {}
                        local line = reader.readLine()
                        while line ~= nil do
                            table.insert(lines, line)
                            line = reader.readLine()
                        end
                        reader.close()
                        reader = nil

                        local resJson = JSONObject(table.concat(lines, "\n"))
                        local candidates = resJson.optJSONArray("candidates")
                        if candidates and candidates.length() > 0 then
                            local cObj = candidates.getJSONObject(0)
                            local cContent = cObj.optJSONObject("content")
                            if cContent then
                                local cParts = cContent.optJSONArray("parts")
                                if cParts and cParts.length() > 0 then
                                    local out = cParts.getJSONObject(0).optString("text")
                                    if out and out ~= "" then
                                        resultText = out
                                        isSuccess = true
                                    end
                                end
                            end
                        end
                    end
                end)

                if reader then pcall(function() reader.close() end) end
                if conn then pcall(function() conn.disconnect() end) end

                if not isSuccess and attempt < maxRetries then
                    pcall(function() Thread.sleep(1200) end)
                end
            end

            local handler = Handler(Looper.getMainLooper())
            handler.post(Runnable({
                run = function()
                    if isSuccess and resultText then
                        callback(true, resultText)
                    else
                        tryGeminiModel(modelIndex + 1, promptText, apiKey, callback)
                    end
                end
            }))
        end
    })).start()
end

local function translateWithGemini(text, targetLang, callback)
    local apiKey = getGeminiApiKey()
    if not apiKey or apiKey == "" then
        showToast("Kunci API Gemini kosong, beralih ke Google")
        if service and service.speak then service.speak("Kunci API Gemini kosong") end
        translateWithGoogle(text, targetLang, callback)
        return
    end

    if not isConnected() then
        showToast("Butuh koneksi internet")
        if service and service.speak then service.speak("Butuh internet") end
        callback(text)
        return
    end

    local langName = targetLang
    for name, code in pairs(languages) do
        if code == targetLang then
            langName = name
            break
        end
    end

    local prompt = "Kamu adalah penerjemah profesional. Terjemahkan teks berikut secara langsung dan akurat ke bahasa " .. langName .. " (" .. targetLang .. ").\n" ..
        "ATURAN MUTLAK:\n" ..
        "- Kembalikan HANYA hasil terjemahan langsung.\n" ..
        "- DILARANG menambahkan kalimat pembuka atau penjelasan.\n" ..
        "- DILARANG memberi tanda petik pembungkus.\n\n" .. text

    tryGeminiModel(1, prompt, apiKey, function(ok, res)
        if ok and res and res:match("%S") then
            local cleanTrans = res:gsub('^%s*"', ''):gsub('"%s*$', '')
            cleanTrans = cleanTrans:gsub("^%s*[Bb]erikut terjemahannya%s*:?%s*", "")
            cleanTrans = cleanTrans:gsub("^%s+", ""):gsub("%s+$", "")
            callback(cleanTrans)
        else
            showToast("Semua model Gemini Flash gagal, beralih ke Google")
            translateWithGoogle(text, targetLang, callback)
        end
    end)
end

-- Distributor Terjemahan Berdasarkan Pilihan
local function executeTranslation(text, targetLang, callback)
    local engine = getEngine()
    if engine == "Groq" then
        translateWithGroq(text, targetLang, callback)
    elseif engine == "Gemini" then
        translateWithGemini(text, targetLang, callback)
    else
        translateWithGoogle(text, targetLang, callback)
    end
end

----------------------------------------------------------------
-- Pengenal Suara (Speech Recognizer)
----------------------------------------------------------------
local function startListening()
    local handler = Handler(Looper.getMainLooper())
    handler.post(Runnable({
        run = function()
            if recognizerInstance then
                pcall(function()
                    recognizerInstance.cancel()
                    recognizerInstance.destroy()
                end)
                recognizerInstance = nil
            end

            recognizerInstance = SpeechRecognizer.createSpeechRecognizer(konteks)
            local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "id-ID")

            if isConnected() then
                intent.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            else
                intent.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            end

            intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 10000)
            intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 20000)
            intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 10000)
            intent.putExtra("android.speech.extra.PROFANITY_FILTER", false)

            local timeoutRunnable = Runnable({
                run = function()
                    destroyRecognizer()
                end
            })
            handler.postDelayed(timeoutRunnable, 5000)

            local listener = RecognitionListener({
                onReadyForSpeech = function() end,
                onBeginningOfSpeech = function()
                    handler.removeCallbacks(timeoutRunnable)
                end,
                onRmsChanged = function(rmsdB) end,
                onBufferReceived = function(buffer) end,
                onEndOfSpeech = function() end,
                onError = function(error)
                    handler.removeCallbacks(timeoutRunnable)
                    destroyRecognizer()
                end,
                onResults = function(results)
                    handler.removeCallbacks(timeoutRunnable)
                    local matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    if matches and matches.size() > 0 then
                        local spokenText = matches.get(0)
                        local targetNode = service.getEditText()

                        local cleanCmd = spokenText:lower():gsub("[%p]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                        
                        -- 1. Perintah suara hapus semua teks
                        if cleanCmd == "hapus semua" then
                            clearAllText()
                            destroyRecognizer()
                            return
                        end

                        -- 2. Deteksi Perintah Terjemahan: [teks] terjemahkan [bahasa]
                        local cleanText = spokenText
                        local targetCode = nil
                        local lowerSpoken = spokenText:lower()

                        local lastS, lastE = nil, nil
                        local searchPos = 1
                        while true do
                            local s, e = lowerSpoken:find("terjemahkan", searchPos, true)
                            if s then
                                lastS, lastE = s, e
                                searchPos = e + 1
                            else
                                break
                            end
                        end

                        if lastS and lastS > 1 then
                            local textBefore = spokenText:sub(1, lastS - 1)
                            if textBefore:match("%S") then
                                local textAfter = lowerSpoken:sub(lastE + 1)
                                textAfter = textAfter:gsub("[%p]", " ")
                                textAfter = textAfter:gsub("%s+", " ")
                                textAfter = textAfter:gsub("^%s+", ""):gsub("%s+$", "")

                                if languages[textAfter] then
                                    targetCode = languages[textAfter]
                                    cleanText = textBefore
                                end
                            end
                        end

                        -- Format tanda baca yang diucapkan
                        cleanText = formatText(cleanText)

                        if targetCode then
                            executeTranslation(cleanText, targetCode, function(translated)
                                insertText(translated, targetNode)
                            end)
                        else
                            insertText(cleanText, targetNode)
                        end
                    end
                    destroyRecognizer()
                end,
                onPartialResults = function(partialResults)
                    handler.removeCallbacks(timeoutRunnable)
                end,
                onEvent = function(eventType, params) end
            })

            recognizerInstance.setRecognitionListener(listener)
            recognizerInstance.startListening(intent)
        end
    }))
end

startListening()
return true
