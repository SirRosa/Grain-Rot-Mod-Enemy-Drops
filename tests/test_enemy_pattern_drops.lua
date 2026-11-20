-- Deterministic smoke/regression tests. These are MOCKS, not a live Grain Rot session.
local FILE="ue4ss/Mods/GrainRotEnemyPatternDrops/Scripts/main.lua"
local DEATH="/Script/Helden.HeldenDungeonEnemyManager:OnCharacterDeath"
local SPAWN="/Script/Helden.HeldenDungeonEnemyManager:OnCharacterSpawned"
local total=0
local function check(condition,message)
    assert(condition,message)
    total=total+1
end
local function obj(name,t)
    local o=t or {}
    o._valid=true
    function o:IsValid() return self._valid end
    function o:GetFullName() return name end
    return o
end
local function runCase(cfg)
    cfg=cfg or {}
    local hooks,logs={},{}
    local profile=obj("HostProfile",{UnlockedCosmetics=cfg.owned or {}})
    local state=obj("PlayerState",{NewCosmeticUnlocks={}})
    local world=obj("World")
    local pawn=obj("HostPlayer",{PlayerState=state,
        AppliedCharacterPreset=obj("PlayerPreset",{CharacterType=1})})
    function pawn:K2_GetActorLocation() return {X=10,Y=20,Z=30} end
    local controller=obj("HostController",{PlayerState=state,LastPlayerChar=pawn})
    function controller:GetPawn() return pawn end
    function controller:IsLocalController() return cfg.remote~=true end
    local rows=cfg.rows or {
        {UniqueID=101,DataName="PatternTexture_A",Category="PatternTexture",SteamInventoryID=0},
        {UniqueID=102,DataName="PatternColor_B",Category="PatternColor",SteamInventoryID=0},
        {UniqueID=103,DataName="DefaultHat",Category="Hat",SteamInventoryID=0},
    }
    local dt=obj("CosmeticDataTable")
    local stats={spawned=0,picked=0,destroyed=0,attempted={},loot={},
        tableScans=0,findAllCalls=0,staticCalls=0}
    function dt:ForEachRow(fn)
        stats.tableScans=stats.tableScans+1
        for _,r in ipairs(rows) do fn(r.DataName,r) end
    end
    local data=obj("DataSingleton",{CosmeticDataTable=dt})
    local gi=obj("GameInstance",{ProfileSaveGame=profile})
    local gm=obj("GameMode")
    local blueprint=obj("BP_CosmeticLoot_Class")
    function world:SpawnActor(cls,position,rotation)
        assert(cls==blueprint)
        stats.spawned=stats.spawned+1
        local loot=obj("Loot_"..stats.spawned,{CosmeticID=0,bPickedUp=false})
        function loot:OnRep_CosmeticID() end
        function loot:Interact(character)
            assert(character==pawn)
            if cfg.interactError then error("simulated pickup error") end
            stats.picked=stats.picked+1
            table.insert(stats.attempted,self.CosmeticID)
            if cfg.nativeSuccess~=false then
                self.bPickedUp=true
                if not cfg.remote then profile.UnlockedCosmetics[#profile.UnlockedCosmetics+1]=self.CosmeticID end
                state.NewCosmeticUnlocks[#state.NewCosmeticUnlocks+1]=self.CosmeticID
            end
        end
        function loot:K2_DestroyActor()
            self._valid=false
            stats.destroyed=stats.destroyed+1
        end
        stats.loot[#stats.loot+1]=loot
        return loot
    end
    _G.RegisterHook=function(name,callback) hooks[name]=callback end
    local timer
    _G.LoopInGameThreadWithDelay=function(ms,callback)
        assert(ms==350)
        timer=callback
    end
    _G.FindFirstOf=function(class)
        if class=="HeldenGameMode" or class=="GameModeBase" then
            if cfg.client then return nil else return gm end
        elseif class=="HeldenDataSingleton" then return data
        elseif class=="HeldenGameInstance" then return gi end
    end
    _G.FindAllOf=function(class)
        stats.findAllCalls=stats.findAllCalls+1
        if class=="HeldenPlayerController" then return {controller} end
        return {}
    end
    _G.StaticFindObject=function(path)
        stats.staticCalls=stats.staticCalls+1
        if path:find("BP_HeldenCosmeticLoot",1,true) then
            if cfg.missingBlueprint then return nil else return blueprint end
        end
    end
    local originalPrint=print
    _G.print=function(s) logs[#logs+1]=tostring(s) end
    local ok,err=pcall(function()
        -- Force a deterministic drop roll for gameplay regression cases,
        -- independently of the random pattern index.
        local mockMath=setmetatable({
            random=function(a,b)
                if a==nil then return cfg.roll or 0.0 end
                if b~=nil then return math.random(a,b) end
                return math.random(a)
            end,
            randomseed=function() end,
        },{__index=math})
        local env=setmetatable({math=mockMath},{__index=_G})
        local mod=assert(loadfile(FILE,"t",env))
        mod()
    end)
    _G.print=originalPrint
    assert(ok,"load failed: "..tostring(err))
    local function event(typeId,name)
        local enemy=obj(name or "Enemy_1",{AppliedCharacterPreset=obj("EnemyPreset",{CharacterType=typeId or 4})})
        function enemy:K2_GetActorLocation() return {X=11,Y=20,Z=30} end
        function enemy:GetWorld() return world end
        assert(hooks[DEATH])
        hooks[DEATH](nil,{get=function() return enemy end})
        return enemy
    end
    local function tick(n)
        for i=1,(n or 1) do
            local old=print
            _G.print=function(s) logs[#logs+1]=tostring(s) end
            local pass,reason=pcall(timer)
            _G.print=old
            assert(pass,reason)
        end
    end
    return {event=event,tick=tick,stats=stats,hooks=hooks,
        logs=logs,profile=profile,state=state,pawn=pawn}
end

-- A real cosmetic must use a native interact call, not just a fake profile entry.
do
    local e=runCase({owned={101}})
    check(type(e.hooks[DEATH])=="function","death hook registered")
    check(type(e.hooks[SPAWN])=="function","spawn hook registered")
    e.event(4,"EnemyA")
    e.tick(2)
    check(e.stats.spawned==1,"one dead enemy -> one cosmetic pickup")
    check(e.stats.attempted[1]==102,"owned pattern 101 excluded; hat 103 excluded")
    check(e.profile.UnlockedCosmetics[2]==102,"profile received new ID via mocked pickup")
    check(e.stats.destroyed==1,"transient pickup removed")
    e.event(4,"EnemyA")
    e.tick(2)
    check(e.stats.spawned==1,"no duplicate reward for repeat death callback")
end
do
    local e=runCase({owned={101,102}})
    e.event(4,"EnemyB");e.tick(2)
    check(e.stats.spawned==0,"full pattern collection -> no reward")
end
do
    local e=runCase({})
    e.event(1,"PlayerDeath");e.event(3,"FriendlyNPCDeath")
    e.tick(2)
    check(e.stats.spawned==0,"no cosmetics for players or friendly NPCs")
end
do
    local e=runCase({client=true})
    e.event(4,"EnemyC");e.tick(2)
    check(e.stats.spawned==0,"client without authority never grants pattern")
end
do
    local e=runCase({})
    e.event(4,"EnemyD");e.event(4,"EnemyE")
    e.tick(3)
    check(e.stats.spawned==2,"one cosmetic per distinct enemy")
    check(e.stats.attempted[1]~=e.stats.attempted[2],"pending or owned pattern cannot drop twice")
end
do
    local e=runCase({interactError=true})
    e.event(4,"EnemyF");e.tick(3)
    check(e.stats.spawned==1,"pickup was attempted once")
    check(e.stats.destroyed==1,"failed pickup actor cleaned up")
    check(#e.profile.UnlockedCosmetics==0,"no fake direct save mutation on pickup error")
end
do
    local e=runCase({nativeSuccess=false})
    e.event(4,"EnemyG");e.tick(10)
    check(e.stats.destroyed==1,"unconfirmed pickup actor cleaned after bounded wait")
    check(#e.profile.UnlockedCosmetics==0,"no false unlock when native interaction does nothing")
end
do
    local e=runCase({missingBlueprint=true})
    e.event(4,"EnemyH");e.tick(2)
    check(e.stats.spawned==0,"missing Blueprint refuses mutation")
end
do
    local e=runCase({})
    e.event(4,"EnemyI");e.tick(2)
    e.hooks[SPAWN](nil,{get=function()
        return obj("EnemyI",{AppliedCharacterPreset=obj("EnemyPreset",{CharacterType=4})})
    end})
    e.event(4,"EnemyI");e.tick(2)
    check(e.stats.spawned==2,"respawned enemy same name may drop again")
end
do
    local e=runCase({remote=true})
    e.event(4,"EnemyJ");e.tick(2)
    check(e.stats.spawned==1,"native cosmetic pickup supports remote controller")
    check(#e.profile.UnlockedCosmetics==0,"remote player's cosmetic must not touch host profile")
    check(#e.state.NewCosmeticUnlocks==1,"remote player's state receives notification")
end
-- The death callback should contain no object-registry or DataTable traversal.
do
    local e=runCase({})
    e.event(4,"FastEnemyA")
    check(e.stats.findAllCalls==0,"death callback does not enumerate UObjects")
    check(e.stats.tableScans==0,"death callback does not scan cosmetic DataTable")
    check(e.stats.staticCalls==0,"death callback does not load cosmetic Blueprints")
    check(e.stats.spawned==0,"no native actor spawned inside death callback")
    e.tick(1)
    check(e.stats.tableScans==1,"table prewarmed exactly once")
    check(e.stats.staticCalls==1,"native loot class prewarmed exactly once")
    e.event(4,"FastEnemyB")
    e.tick(2)
    check(e.stats.tableScans==1,"cosmetic DataTable not rescanned for later enemy")
    check(e.stats.staticCalls==1,"cosmetic Blueprint not reloaded per kill")
end
-- Bursts are queued, not executed on the same frame, while every kill retains its grant.
do
    local e=runCase({rows={
        {UniqueID=101,DataName="PatternTexture_A",Category="PatternTexture",SteamInventoryID=0},
        {UniqueID=102,DataName="PatternTexture_B",Category="PatternTexture",SteamInventoryID=0},
        {UniqueID=103,DataName="PatternTexture_C",Category="PatternTexture",SteamInventoryID=0},
        {UniqueID=104,DataName="PatternTexture_D",Category="PatternTexture",SteamInventoryID=0},
    }})
    e.event(4,"Burst1");e.event(4,"Burst2");e.event(4,"Burst3");e.event(4,"Burst4")
    check(e.stats.spawned==0,"four simultaneous deaths cause no synchronous pickup")
    e.tick(1)
    check(e.stats.spawned==1,"burst budget allows one cosmetic on first tick")
    e.tick(1)
    check(e.stats.spawned==1,"minimum gap enforces no second cosmetic on adjacent tick")
    e.tick(1)
    check(e.stats.spawned==2,"second unlock is staggered")
    e.tick(4)
    check(e.stats.spawned==4,"all four enemy kills eventually reward")
    check(e.stats.tableScans==1,"no burst DataTable rescan")
    check(e.stats.staticCalls==1,"no burst Blueprint lookup")
end
-- At 5%, 0.0500 does NOT drop and 0.0499 DOES drop.
do
    local e=runCase({roll=0.05})
    e.event(4,"RollExactlyFivePercent")
    e.tick(2)
    check(e.stats.spawned==0,"roll at 5% threshold must not award")
    check(e.stats.findAllCalls==0,"failed roll skips player lookup")
end
do
    local e=runCase({roll=0.99})
    e.event(4,"RollNearOne")
    e.tick(2)
    check(e.stats.spawned==0,"failed 99% roll must not award")
end
do
    local e=runCase({roll=0.0499})
    e.event(4,"RollBelowFivePercent")
    e.tick(2)
    check(e.stats.spawned==1,"roll below 5% awards one native cosmetic")
end
print("PASS: "..total.." assertions across 15 mock scenarios (NOT a real-game test)")
