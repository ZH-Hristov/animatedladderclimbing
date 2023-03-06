local CamEnabled = CreateClientConVar( "ALC_ClimbCam", 1, true, false, "Sets whether climbing should use a custom camera. Requres CVPS installed.", 0, 1 )
local HolsterEnabled = CreateConVar("ALC_HolsterWeapon", 1, bit.band(FCVAR_REPLICATED, FCVAR_ARCHIVE), "Sets whether the weapon should be holstered and re-equipped on ladder mount/dismount.", 0, 1)

local PlyMethods = FindMetaTable("Player")
local ALC_ClimbSeqDuration = 2.0333333015442
local Climbers = {}
local Dismounts = {}
local LadderProps = {}

local LadderModels = {
    "models/props_c17/metalladder004.mdl",
    "models/props_c17/metalladder005.mdl",
    "models/props_c17/metalladder001.mdl",
    "models/props_c17/metalladder002.mdl",
    "models/props_c17/metalladder002c_damaged.mdl",
    "models/props_c17/metalladder002d.mdl",
    "models/props_c17/metalladder003.mdl",
    "models/props_equipment/metal_ladder002_new.mdl",
    "models/props_equipment/metalladder002.mdl",
    "models/props_forest/ladderwood.mdl",
    "models/props_silo/ladderrung.mdl",
    "models/props/cs_assault/ladderaluminium128.mdl"
}

local function FindClosest(ents, pos)
	local closest = math.huge
	local closestent

	for _, v in pairs(ents) do
        if !IsValid(v) then continue end
		local d = v:GetPos():DistToSqr(pos)
		if d<closest then
			closest = d
			closestent = v
		end
	end

	return closestent
end

local function ReloadPropLadderDirections()
    if table.IsEmpty(LadderProps) then return end

    for _, Ladder in pairs(ents.FindByClass("func_useableladder")) do
        local ClosestProp = FindClosest(LadderProps, Ladder:GetPos())
        local Dist = ClosestProp:GetPos():DistToSqr(Ladder:GetPos())
        if Dist <= 60000 then
            Ladder.FrontPos = ClosestProp:GetPos() + Vector(-1000, -1000, -1000) * ClosestProp:GetForward()
        end
    end
end

local function ReloadLadderProps()
    for i = 1, #LadderModels do
        local Model = LadderModels[i]

        for _, ent in pairs(ents.FindByModel(Model)) do
            if ent:CreatedByMap() then
                table.insert(LadderProps, ent)
            end
        end
    end

    ReloadPropLadderDirections()
end

local function ReloadDismounts()
    Dismounts = ents.FindByClass("info_ladder_dismount")
end

local function angNorm(x)
    return (x + 180) % 360 - 180
end

local function CalcMainHook(ply, vel)
    ply:SetPoseParameter("alc_ladder_pitch", ply:GetNW2Float("ALC_LadderPitch"))

    local climbing = ply:GetNW2Bool("ALC_Climbing")

    if climbing then
        if vel.z > 0 then
            ply.ALC_GoingUp = true
        elseif vel.z < 0 then
            ply.ALC_GoingUp = false
        end

        if ply:GetPos().z < ply:GetNW2Float("ALC_LadderEndHeight", math.huge) - 170 then

            if SERVER then
                if vel.z != 0 then
                    local animprogress = ply:GetNW2Float("ALC_ClimbAnimProgress", 0)
                    local rate = math.abs(vel.z) * 0.02

                    if animprogress < 1 then
                        ply:SetNW2Float("ALC_ClimbAnimProgress", math.min(animprogress + FrameTime() / ALC_ClimbSeqDuration * rate, 1))
                    else
                        ply:SetNW2Float("ALC_ClimbAnimProgress", 0)
                    end
                end
            end

            ply:SetCycle(ply:GetNW2Float("ALC_ClimbAnimProgress"))

            if ply.ALC_GoingUp then
                return -1, ply:LookupSequence("wos_mma_climbladder_up")
            else
                return -1, ply:LookupSequence("wos_mma_climbladder_down")
            end
        else
            local endHeight = ply:GetNW2Float("ALC_LadderEndHeight")
            local cyc = math.Remap(ply:GetPos().z, endHeight - 170, endHeight, 0, 1)

            ply:SetCycle(cyc)
            return -1, ply:LookupSequence("wos_mma_bracedhang_to_crouch")
        end
    end
end

local function AddClimber(ply)
    if table.IsEmpty(Climbers) then
        hook.Add("CalcMainActivity", "ALC_CalcMainActivity", CalcMainHook)

        hook.Add("PlayerSwitchWeapon", "ALC_DisallowWeaponChange", function(ply)
            if ply:GetNW2Bool("ALC_CLIMBING") then return true end
        end)

        hook.Add("UpdateAnimation", "ALC_SetYaw", function(ply)
            if ply:GetNW2Float("ALC_LookAtYaw", nil) then
                ply:SetRenderAngles(Angle(0, ply:GetNW2Float("ALC_LookAtYaw"), 0))
            end
        end)
    end

    Climbers[ply] = true
end

local function RemoveClimber(ply)
    Climbers[ply] = nil
    ply:SetPoseParameter("alc_ladder_pitch", 0)

    if table.IsEmpty(Climbers) then
        hook.Remove("CalcMainActivity", "ALC_CalcMainActivity")
        hook.Remove("PlayerSwitchWeapon", "ALC_DisallowWeaponChange")
        hook.Remove("UpdateAnimation", "ALC_SetYaw")
    end
end

local function SetLookAt(ply, vec1, vec2)
    ply:SetNW2Float("ALC_LookAtYaw", (vec1 - vec2):Angle().y)
end

function PlyMethods:InitStickyLadder(Ladder)
    local TopPos = Ladder:LocalToWorld(Ladder:OBBMaxs())
    local nearestDismount = FindClosest(Dismounts, TopPos)
    local keyvals = Ladder:GetKeyValues()

    local tr = util.TraceLine( {start = Ladder:GetPos(), endpos = Ladder:GetPos() + keyvals.point0, mask = 0} )

    if HolsterEnabled:GetBool() then
        self.ALC_LastWeapon = self:GetActiveWeapon()
        self:SetActiveWeapon(nil)
    end

    self:SetNW2Bool("ALC_Climbing", true)

    self:SetNW2Entity("ALC_CurrentStickyLadder", Ladder)
    self:SetNW2Float("ALC_LadderEndHeight", TopPos.z)
    self:SetNW2Float("ALC_LadderPitch", tr.Normal.z - 1)

    if Ladder.FrontPos then
        SetLookAt(self, nearestDismount:GetPos(), Ladder.FrontPos)
    else
        SetLookAt(self, nearestDismount:GetPos(), Ladder:GetPos())
    end
end

function PlyMethods:DeInitStickyLadder()
    self:SetNW2Bool("ALC_Climbing", false)

    if IsValid(self.ALC_LastWeapon) then
        self:SelectWeapon(self.ALC_LastWeapon:GetClass())
    end
    self.ALC_LastWeapon = nil

    self:SetNW2Entity("ALC_CurrentStickyLadder", nil)
    self:SetNW2Float("ALC_LadderEndHeight", nil)
    self:SetNW2Float("ALC_LadderPitch", nil)

    timer.Simple(0.1, function()
        self:SetNW2Float("ALC_LookAtYaw", nil) -- This is delayed otherwise the view angles snap when getting off the ladder
    end)
end

if SERVER then
    ReloadLadderProps()
    ReloadDismounts()

    local function SetupMapLua()
        local MapLua = ents.Create( "lua_run" )
        MapLua:SetName( "ladderhook" )
        MapLua:Spawn()
    
        for _, v in ipairs( ents.FindByClass( "func_useableladder" ) ) do
            v:Fire( "AddOutput", "OnPlayerGotOnLadder ladderhook:RunPassedCode:hook.Run( 'GetOnUseableLadder' ):0:-1" )
            v:Fire( "AddOutput", "OnPlayerGotOffLadder ladderhook:RunPassedCode:hook.Run( 'GetOffUseableLadder' ):0:-1" )
        end

        ReloadLadderProps()
        ReloadDismounts()
    end
    
    hook.Add( "InitPostEntity", "SetupMapLua", SetupMapLua )
    hook.Add( "PostCleanupMap", "SetupMapLua", SetupMapLua )

    hook.Add("GetOnUseableLadder", "AnimatedLadderClimbing_GetOn", function()
        local ladder, ply = ACTIVATOR, CALLER
        ply:InitStickyLadder(ladder)
    end)

    hook.Add("GetOffUseableLadder", "AnimatedLadderClimbing_GetOff", function()
        local ply = CALLER
        ply:DeInitStickyLadder()
    end)
end

hook.Add("EntityNetworkedVarChanged", "ALC_NWVarChanged", function(ent, varname, old, new)
    if varname == "ALC_Climbing" then
        if new == true then
            AddClimber(ent)

            if CLIENT and ent == LocalPlayer() then
                if !CalcViewPS or !CamEnabled:GetBool() then return end
                local attId = LocalPlayer():LookupAttachment("eyes")
                if attId <= 0 then return end

                local Prog = CurTime()
                local EndTime = CurTime() + 0.2
                local LerpProg = 0

                local View = {drawviewer = true}
                local head = LocalPlayer():LookupBone("ValveBiped.Bip01_Head1")

                if head then
                    LocalPlayer().ALC_HeadScale = LocalPlayer():GetManipulateBoneScale(head)
                    LocalPlayer():ManipulateBoneScale(head, Vector(0, 0, 0))
                end

                CalcViewPS.AddToTop("ALC_CVPS_CAM", function(ply, pos)
                    local att = LocalPlayer():GetAttachment(attId)

                    if Prog < EndTime then
                        LerpProg = math.Approach(LerpProg, 1, FrameTime() / 0.2)
                        Prog = math.Approach(Prog, EndTime, FrameTime())
                        View.origin = LerpVector(LerpProg, pos, att.Pos)
                    else
                        View.origin = att.Pos
                    end

                    return View
                end)
            end
        else
            RemoveClimber(ent)

            if CLIENT and ent == LocalPlayer() then
                hook.Remove("InputMouseApply", "ALC_ForceLook")

                if !CalcViewPS or !CamEnabled:GetBool() then return end
                local attId = LocalPlayer():LookupAttachment("eyes")
                if attId <= 0 then return end

                local Prog = CurTime()
                local EndTime = CurTime() + 0.2
                local LerpProg = 0

                local View = {}

                CalcViewPS.AddToTop("ALC_CVPS_CAM_OUT", function(ply, pos)
                    local att = LocalPlayer():GetAttachment(attId)

                    if Prog < EndTime then
                        LerpProg = math.Approach(LerpProg, 1, FrameTime() / 0.2)
                        Prog = math.Approach(Prog, EndTime, FrameTime())
                        View.origin = LerpVector(LerpProg, att.Pos, pos)
                    else
                        CalcViewPS.Remove("ALC_CVPS_CAM_OUT")
                        if LocalPlayer().ALC_HeadScale then
                            local head = LocalPlayer():LookupBone("ValveBiped.Bip01_Head1")
        
                            LocalPlayer():ManipulateBoneScale(head, LocalPlayer().ALC_HeadScale or Vector(1, 1, 1))
                            LocalPlayer().ALC_HeadScale = nil
                        end
                    end

                    return View
                end)
                CalcViewPS.Remove("ALC_CVPS_CAM")
            end
        end
    end
end)