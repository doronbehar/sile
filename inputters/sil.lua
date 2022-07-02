local lpeg = require("lpeg")
local epnf = require("epnf")

local base = require("inputters.base")
local sil = pl.class(base)
sil._name = "sil"

sil.order = 99
sil.appropriate = function () return true end

local bits = SILE.parserBits


sil.passthroughCommands = {
  ftl = true,
  math = true,
  script = true
}

function sil:_init (tree)
  self._parser = self:rebuildParser()
  base._init(self, tree)
end

-- luacheck: push ignore
function sil.parser (_ENV)
  local isPassthrough = function (_, _, command)
    return sil.passthroughCommands[command] or false
  end
  local isNotPassthrough = function (...)
    return not isPassthrough(...)
  end
  local isMatchingEndEnv = function (a, b, thisCommand, lastCommand)
    return thisCommand == lastCommand
  end
  local _ = WS^0
  local eol = S"\r\n"
  local specials = S"{}%\\"
  local escaped_specials = P"\\" * specials
  local unescapeSpecials = function (str)
    return str:gsub('\\([{}%%\\])', '%1')
  end
  local myID = C(bits.silidentifier) / 1
  local cmdID = myID - P"beign" - P"end"
  local wrapper = function (a) return type(a)=="table" and a or {} end
  local parameters = (P"[" * bits.parameters * P"]")^-1 / wrapper
  local comment = (
      P"%" *
      P(1-eol)^0 *
      eol^-1
    ) / ""

  START "document"
  document = V"texlike_stuff" * EOF"Unexpected character at end of input"
  texlike_stuff = Cg(
      V"environment" +
      comment +
      V"texlike_text" +
      V"texlike_braced_stuff" +
      V"texlike_command"
    )^0
  passthrough_stuff = C(Cg(
      V"passthrough_text" +
      V"passthrough_debraced_stuff"
    )^0)
  passthrough_env_stuff = Cg(
      V"passthrough_env_text"
    )^0
  texlike_text = C((1 - specials + escaped_specials)^1) / unescapeSpecials
  passthrough_text = C((1-S("{}"))^1)
  passthrough_env_text = C((1 - (P"\\end{" * Cmt(cmdID * Cb"command", isMatchingEndEnv) * P"}"))^1)
  texlike_braced_stuff = P"{" * V"texlike_stuff" * ( P"}" + E("} expected") )
  passthrough_braced_stuff = P"{" * V"passthrough_stuff" * ( P"}" + E("} expected") )
  passthrough_debraced_stuff = C(V"passthrough_braced_stuff")
  texlike_command = (
      P"\\" *
      Cg(cmdID, "command") *
      Cg(parameters, "options") *
      (
        (Cmt(Cb"command", isPassthrough) * V"passthrough_braced_stuff") +
        (Cmt(Cb"command", isNotPassthrough) * V"texlike_braced_stuff")
      )^0
    )
  local notpass_end =
      P"\\end{" *
      ( Cmt(cmdID * Cb"command", isMatchingEndEnv) + E"Environment mismatch") *
      ( P"}" * _ ) + E"Environment begun but never ended"
  local pass_end =
      P"\\end{" *
      ( cmdID * Cb"command" ) *
      ( P"}" * _ ) + E"Environment begun but never ended"
  environment =
    P"\\begin" *
    Cg(parameters, "options") *
    P"{" *
    Cg(cmdID, "command") *
    P"}" *
    (
      (Cmt(Cb"command", isPassthrough) * V"passthrough_env_stuff" * pass_end) +
      (Cmt(Cb"command", isNotPassthrough) * V"texlike_stuff" * notpass_end)
    )
end
-- luacheck: pop

local linecache = {}
local lno, col, lastpos
local function resetCache ()
  lno = 1
  col = 1
  lastpos = 0
  linecache = { { lno = 1, pos = 1} }
end

local function getline (str, pos)
  local start = 1
  lno = 1
  if pos > lastpos then
    lno = linecache[#linecache].lno
    start = linecache[#linecache].pos + 1
    col = 1
  else
    for j = 1, #linecache-1 do
      if linecache[j+1].pos >= pos then
        lno = linecache[j].lno
        col = pos - linecache[j].pos
        return lno, col
      end
    end
  end
  for i = start, pos do
    if string.sub( str, i, i ) == "\n" then
      lno = lno + 1
      col = 1
      linecache[#linecache+1] = { pos = i, lno = lno }
      lastpos = i
    end
    col = col + 1
  end
  return lno, col
end

local function massage_ast (tree, doc)
  -- Sort out pos
  if type(tree) == "string" then return tree end
  if tree.pos then
    tree.lno, tree.col = getline(doc, tree.pos)
  end
  if tree.id == "document"
      or tree.id == "texlike_braced_stuff"
      or tree.id == "passthrough_braced_stuff"
    then return massage_ast(tree[1], doc) end
  if tree.id == "texlike_text"
      or tree.id == "passthrough_text"
      or tree.id == "passthrough_env_text"
    then return tree[1] end
  for key, val in ipairs(tree) do
    if val.id == "texlike_stuff"
      or val.id == "passthrough_stuff"
      or val.id == "passthrough_env_stuff"
      then
      SU.splice(tree, key, key, massage_ast(val, doc))
    else
      tree[key] = massage_ast(val, doc)
    end
  end
  return tree
end

function sil:process (doc)
  local tree = self:docToTree(doc)
  local root = SILE.documentState.documentClass == nil
  if tree.command then
    if root and tree.command == "document" then
      self:classInit(tree)
    end
    SILE.process(tree)
  elseif not pcall(function () assert(load(doc))() end) then
    SU.error("Input not recognized as Lua or SILE content")
  end
  if root and not SILE.preamble then
    SILE.documentState.documentClass:finish()
  end
end

function sil:rebuildParser ()
  return epnf.define(self.parser)
end

function sil:docToTree (doc)
  local tree = epnf.parsestring(self._parser, doc)
  -- a document always consists of one texlike_stuff
  tree = tree[1][1]
  if tree.id == "texlike_text" then tree = {tree} end
  if not tree then return end
  resetCache()
  tree = massage_ast(tree, doc)
  return tree
end

return sil
