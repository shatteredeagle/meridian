-- Localization: M.L[english text] returns the translation, or the English text itself when there is none.
-- Keys are the English strings, so a missing translation can never show a blank or a raw key.
-- Translations live in Locales/<locale>.lua (see Locales/deDE.lua); tools/extract_strings.py rebuilds Locales/enUS.lua,
-- the full key list, from every L["..."] in the code.
local ADDON, M = ...

M.L = setmetatable({}, { __index = function(_, key) return key end })
