-- Grain Rot Enemy Pattern Drops v0.1.0-alpha (Helden UE5.7 / UE4SS 3.x)
-- 100% TEST chance. Award one unseen PatternTexture/PatternColor per ENEMY death.
-- Do not alter UProfileSaveGame's TArray directly: native cosmetic pickup must do that.
-- Kill notifications and spawning are processed on the authoritative game thread.
local CFG = {
    Chance = 1.0, -- change to e.g. 0.05 AFTER real-game verification
    TickMs = 350,
    MaxQueue = 64,
    MaxLogErrors = 20,
}
local TAG = "[GrainRotEnemyPatternDrops] "
local function log(msg) print(TAG .. tostring(msg) .. "\n") end
local function get(o,k)
    if o==nil then return nil end
    local ok,value=pcall(function() return o[k] end)
    if ok then return value end
    return nil
end
local function valid(o)
    if o==nil then return false end
    local ok,result=pcall(function() return o:IsValid() end)
    return ok and result==true
end
local function unwrap(v)
    if v==nil then return nil end
    local ok,result=pcall(function() return v:get() end)
    if ok then return result end
    return v
end
local function objName(o)
    if not valid(o) then return "invalid" end
    local ok,s=pcall(function() return o:GetFullName() end)
    if ok then return tostring(s) end
    return tostring(o)
end
local function typename(v)
    if v==nil then return "" end
    local ok,s=pcall(function() return v:ToString() end)
    if ok and s then return tostring(s) end
    return tostring(v)
end
local function asInt(v)
    local n=tonumber(v)
    if n and n==n and n>=0 and n<=65535 then return math.floor(n) end
    return nil
end
local function enum(v)
    if type(v)=="number" then return v end
    if v==nil then return nil end
    local s=typename(v)
    return tonumber(s) or (s:find("Enemy",1,true) and 4)
        or (s:find("Dead",1,true) and 1) or nil
end
local function arrayEach(arr,fn)
    if arr==nil then return end
    local ok,n=pcall(function() return #arr end)
    if not ok or type(n)~="number" then return end
    for i=1,math.min(n,10000) do
        local yes,v=pcall(function() return unwrap(arr[i]) end)
        if yes then fn(v,i) end
    end
end
local function first(cls)
    local ok,result=pcall(FindFirstOf,cls)
    if ok and valid(result) and not objName(result):find("Default__",1,true) then return result end
    ok,result=pcall(FindAllOf,cls)
    if ok and type(result)=="table" then
        for _,v in ipairs(result) do
            if valid(v) and not objName(v):find("Default__",1,true) then return v end
        end
    end
    return nil
end
local function isHost()
    return valid(first("HeldenGameMode")) or valid(first("GameModeBase"))
end
local function characterType(c)
    if not valid(c) then return nil end
    local preset=get(c,"AppliedCharacterPreset") or get(c,"CharacterPreset")
    local result=enum(get(preset,"CharacterType"))
    if result~=nil then return result end
    local ok,v=pcall(function() return c:GetCharacterType() end)
    if ok then return enum(v) end
    return nil
end
local function pos(c)
    if not valid(c) then return nil end
    local ok,p=pcall(function() return c:K2_GetActorLocation() end)
    if not ok or not p then return nil end
    local x,y,z=tonumber(get(p,"X")),tonumber(get(p,"Y")),tonumber(get(p,"Z"))
    if not x or not y or not z then return nil end
    return {X=x,Y=y,Z=z}
end
local function dist2(a,b)
    if not a or not b then return math.huge end
    return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2
end
local function pawnOf(pc)
    local ok,p=pcall(function() return pc:GetPawn() end)
    if not ok or characterType(p)~=1 then
        p=get(pc,"LastPlayerChar")
    end
    if characterType(p)==1 then return p end
    return nil
end
local function nearestPlayer(enemyPos)
    local ok,pcs=pcall(FindAllOf,"HeldenPlayerController")
    if not ok or type(pcs)~="table" then return nil end
    local nearest,best=nil,math.huge
    for _,pc in ipairs(pcs) do
        if valid(pc) then
            local pawn=pawnOf(pc)
            local st=valid(pawn) and get(pawn,"PlayerState") or nil
            if not valid(st) then st=get(pc,"PlayerState") end
            if valid(pawn) and valid(st) and enum(get(pawn,"CharacterState"))~=1 then
                local d=dist2(pos(pawn),enemyPos)
                if d<best then
                    nearest={pc=pc,pawn=pawn,state=st}
                    best=d
                end
            end
        end
    end
    return nearest
end
local function isPattern(row)
    local id=asInt(get(row,"UniqueID"))
    if not id or id==0 then return nil end
    local cat=typename(get(row,"Category")):lower()
    local name=typename(get(row,"DataName")):lower()
    local asset=typename(get(row,"CosmeticAssetID")):lower()
    if not (cat:find("pattern",1,true) or name:find("pattern",1,true)
            or asset:find("pattern",1,true)) then return nil end
    -- Restrict to pattern texture/color; never award hats, badges, Twitch items.
    if (cat:find("pattern",1,true) and
        (cat:find("color",1,true) or cat:find("texture",1,true)))
        or name:find("pattern",1,true) or asset:find("pattern",1,true) then
        if tonumber(get(row,"SteamInventoryID")) and tonumber(get(row,"SteamInventoryID"))>0 then
            return nil
        end
        return id
    end
    return nil
end
local function eachRow(dt,fn)
    if not valid(dt) then return false,0 end
    local count=0
    local function apply(name,row)
        if row then count=count+1;fn(name,row) end
    end
    local ok=pcall(function()
        dt:ForEachRow(function(n,r) apply(typename(n),r) end)
    end)
    if ok and count>0 then return true,count end
    count=0
    ok=pcall(function()
        for name,row in pairs(dt:GetRowMap()) do apply(name,row) end
    end)
    if ok and count>0 then return true,count end
    count=0
    ok=pcall(function()
        local names=dt:GetRowNames()
        arrayEach(names,function(n) apply(typename(n),dt:FindRow(n)) end)
    end)
    return ok and count>0,count
end
local candidatesCache=nil
local function candidates()
    if candidatesCache then return candidatesCache end
    local data=first("HeldenDataSingleton")
    local dt=get(data,"CosmeticDataTable")
    local results,seen={},{}
    local ok,n=eachRow(dt,function(_,row)
        local id=isPattern(row)
        if id and not seen[id] then seen[id]=true;results[#results+1]=id end
    end)
    if not ok or #results==0 then
        return nil,"CosmeticDataTable unreadable or no pattern rows (rows="..n..")"
    end
    candidatesCache=results
    log("pattern table loaded: "..#results.." candidate pattern IDs")
    return results
end
local function ownsFromArray(arr,id)
    local found=false
    arrayEach(arr,function(v) if asInt(v)==id then found=true end end)
    return found
end
local function localProfile(player)
    -- Local GI represents the host, NOT the profiles of remote players.
    if not valid(player.pc) then return nil end
    local ok,localPC=pcall(function() return player.pc:IsLocalController() end)
    if not ok or localPC~=true then return nil end
    return get(first("HeldenGameInstance"),"ProfileSaveGame")
end
local sessionAwarded={}
local sessionPending={}
local function playerKey(player)
    local ok,id=pcall(function() return player.state:GetFullName() end)
    return (ok and tostring(id)) or objName(player.pc)
end
local function alreadyOwned(player,id)
    local key=playerKey(player)
    if sessionAwarded[key] and sessionAwarded[key][id] then return true end
    if sessionPending[key] and sessionPending[key][id] then return true end
    if ownsFromArray(get(player.state,"NewCosmeticUnlocks"),id) then return true end
    local profile=localProfile(player)
    if valid(profile) and ownsFromArray(get(profile,"UnlockedCosmetics"),id) then return true end
    return false
end
local function setPending(player,id,yes)
    local key=playerKey(player)
    sessionPending[key]=sessionPending[key] or {}
    sessionPending[key][id]=yes and true or nil
end
local function remember(player,id)
    local key=playerKey(player)
    sessionAwarded[key]=sessionAwarded[key] or {}
    sessionAwarded[key][id]=true
end
local function choose(player,items)
    local available={}
    for _,id in ipairs(items) do
        if not alreadyOwned(player,id) then available[#available+1]=id end
    end
    if #available==0 then return nil,0 end
    return available[math.random(1,#available)],#available
end
local function lootClass()
    for _,path in ipairs({
        "/Game/Gameplay/Loot/CosmeticLoot/BP_HeldenCosmeticLoot_TexturePattern_01.BP_HeldenCosmeticLoot_TexturePattern_01_C",
        "/Game/Gameplay/Loot/CosmeticLoot/BP_HeldenCosmeticLoot_01.BP_HeldenCosmeticLoot_01_C"
    }) do
        local ok,cls=pcall(StaticFindObject,path)
        if ok and valid(cls) then return cls,path end
    end
    return nil
end
local function nativeAward(job,player,id)
    local cls=lootClass()
    if not valid(cls) then return false,"cosmetic loot Blueprint class not loaded" end
    local p=pos(player.pawn)
    if not p or not valid(job.world) then return false,"world/player invalid" end
    -- Spawn close to the receiving player, immediately invoke the game's
    -- existing authoritative pickup, then remove the transient actor.
    local spawnPos={X=p.X,Y=p.Y,Z=p.Z+40}
    local ok,loot=pcall(function()
        return job.world:SpawnActor(cls,spawnPos,{Pitch=0,Yaw=0,Roll=0})
    end)
    if not ok or not valid(loot) then return false,"SpawnActor failed: "..tostring(loot) end
    local wrote=pcall(function() loot.CosmeticID=id end)
    if not wrote or asInt(get(loot,"CosmeticID"))~=id then
        pcall(function() loot:K2_DestroyActor() end)
        return false,"CosmeticID write/readback failed"
    end
    pcall(function() loot:OnRep_CosmeticID() end)
    -- Interact(InCharacter) is reflected on the inherited HeldenInteractableObject.
    -- No fictional Interact_Auth method, no visual-only PickedUpBy_Multicast payout.
    -- Native code may confirm pickup on a later tick, so keep actor alive briefly.
    local acted,err=pcall(function() loot:Interact(player.pawn) end)
    if not acted then
        pcall(function() loot:K2_DestroyActor() end)
        return false,"native Interact failed: "..tostring(err)
    end
    return true,loot
end
local S={seen={},queue={},pending={},errors=0,kills=0,awards=0,skips=0}
local function warn(msg)
    if S.errors<CFG.MaxLogErrors then
        S.errors=S.errors+1
        log("WARN "..msg)
    end
end
local function finishPending()
    for i=#S.pending,1,-1 do
        local job=S.pending[i]
        local picked=valid(job.loot) and get(job.loot,"bPickedUp")==true
        -- Query actual profile/state (not the session pending reservation).
        local profile=localProfile(job.player)
        local owned=(valid(profile) and ownsFromArray(get(profile,"UnlockedCosmetics"),job.id))
            or ownsFromArray(get(job.player.state,"NewCosmeticUnlocks"),job.id)
        job.ticks=job.ticks+1
        if picked or owned or job.ticks>=8 then
            setPending(job.player,job.id,false)
            if picked or owned then
                remember(job.player,job.id)
                S.awards=S.awards+1
                log("PICKUP CONFIRMED pattern="..job.id.." enemy="..job.enemy..
                    " proof="..(owned and "profile/state" or "native bPickedUp"))
            else
                warn("PICKUP NOT CONFIRMED pattern="..job.id.." enemy="..job.enemy..
                    " (no profile/state or bPickedUp after 8 ticks)")
            end
            if valid(job.loot) then pcall(function() job.loot:K2_DestroyActor() end) end
            table.remove(S.pending,i)
        end
    end
end
local function flush()
    finishPending()
    if not isHost() then return end
    local budget=math.min(#S.queue,CFG.MaxQueue)
    for _=1,budget do
        local job=table.remove(S.queue,1)
        local list,why=candidates()
        if not list then
            warn(why)
        else
            local id,available=choose(job.player,list)
            if not id then
                S.skips=S.skips+1
                if S.skips<=5 then log("SKIP: receiving player has all visible pattern candidates") end
            elseif math.random()<CFG.Chance then
                local ok,success,lootOrError=pcall(nativeAward,job,job.player,id)
                if ok and success and valid(lootOrError) then
                    setPending(job.player,id,true)
                    S.pending[#S.pending+1]={loot=lootOrError,id=id,
                        player=job.player,enemy=job.enemy,ticks=0}
                    log("PICKUP ATTEMPT pattern="..id.." candidatesRemaining="..available..
                        " enemy="..job.enemy.."; verifying native confirmation")
                else
                    warn("GRANT FAILED pattern="..id.." enemy="..job.enemy..
                        " reason="..tostring(ok and lootOrError or success))
                end
            end
        end
    end
end
local function onDeath(_,arg)
    if not isHost() then return end
    local enemy=unwrap(arg)
    if characterType(enemy)~=4 then return end
    local key=objName(enemy)
    if S.seen[key] then return end
    S.seen[key]=true
    S.kills=S.kills+1
    local ep=pos(enemy)
    local player=nearestPlayer(ep)
    if not player then
        warn("NO PLAYER near enemy "..key)
        return
    end
    local ok,world=pcall(function() return enemy:GetWorld() end)
    if not ok or not valid(world) then
        warn("NO WORLD for "..key)
        return
    end
    if #S.queue>=CFG.MaxQueue then
        warn("queue capacity reached, refusing reward for "..key)
        return
    end
    S.queue[#S.queue+1]={player=player,world=world,enemy=key}
end
local function onSpawn(_,arg)
    local enemy=unwrap(arg)
    -- Manager only invokes this for spawned enemies; the type may not yet be initialized.
    if valid(enemy) then S.seen[objName(enemy)]=nil end
end
local function hook(method,fn)
    local ok,result=pcall(RegisterHook,method,fn)
    if ok then
        log("HOOK registered "..method.." (real callback not yet confirmed)")
    else
        warn("HOOK FAILED "..method..": "..tostring(result))
    end
end
math.randomseed(os.time())
hook("/Script/Helden.HeldenDungeonEnemyManager:OnCharacterDeath",onDeath)
hook("/Script/Helden.HeldenDungeonEnemyManager:OnCharacterSpawned",onSpawn)
local ok,err=pcall(LoopInGameThreadWithDelay,CFG.TickMs,function()
    local success,why=pcall(flush)
    if not success then warn("flush: "..tostring(why)) end
end)
if not ok then
    -- Do not write into UObject from an asynchronous worker thread.
    warn("game-thread timer unavailable; no rewards until scheduler works: "..tostring(err))
end
log("loaded v0.1.0-alpha chance=100% modes=Story+Expedition; native cosmetic pickup; runtime verification required")
